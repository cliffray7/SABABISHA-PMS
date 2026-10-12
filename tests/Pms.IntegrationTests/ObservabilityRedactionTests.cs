using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Logs;
using Pms.Api.Auth;
using Pms.Api.Observability;

namespace Pms.IntegrationTests;

public sealed class ObservabilityRedactionTests
{
    [Fact]
    public void TelemetryProcessorRemovesCredentialAndPrivatePayloadAttributes()
    {
        using var activity = new Activity("outbound request");
        activity.SetTag("url.full", "https://provider.invalid/v1?key=secret-value");
        activity.SetTag("url.path", "/invite/private-token");
        activity.SetTag("http.route", "/api/v1/invitations/{id}");
        activity.SetTag("db.statement", "SELECT * FROM Users WHERE Email='private@example.com'");
        activity.SetTag("api.token", "credential-value");
        activity.Start();

        new TelemetrySanitizingActivityProcessor().OnEnd(activity);

        Assert.Null(activity.GetTagItem("url.full"));
        Assert.Null(activity.GetTagItem("url.path"));
        Assert.Null(activity.GetTagItem("db.statement"));
        Assert.Null(activity.GetTagItem("api.token"));
        Assert.Equal("/api/v1/invitations/{id}", activity.GetTagItem("http.route"));
    }

    [Fact]
    public async Task MailLogsDoNotContainRecipientOtpOrInvitationLink()
    {
        var logger = new CapturingLogger<AppMail>();
        var configuration = new ConfigurationBuilder().Build();
        var mail = new AppMail(configuration, new StubHttpClientFactory(), logger);

        await mail.Send("private-recipient@example.com", "Invitation", "https://taskflow.invalid/invite?token=private-link-token");
        await mail.SendOtp("private-recipient@example.com", "918273");

        var output = string.Join("\n", logger.Messages);
        Assert.DoesNotContain("private-recipient@example.com", output, StringComparison.Ordinal);
        Assert.DoesNotContain("private-link-token", output, StringComparison.Ordinal);
        Assert.DoesNotContain("918273", output, StringComparison.Ordinal);
    }

    [Fact]
    public void OtlpLogProcessorExportsOnlyAllowlistedFields()
    {
        var capture = new CapturingLogProcessor();
        using var factory = LoggerFactory.Create(builder => builder.AddOpenTelemetry(options =>
        {
            options.IncludeScopes = true;
            options.ParseStateValues = true;
            options.IncludeFormattedMessage = true;
            options.AddProcessor(new TelemetrySanitizingLogProcessor());
            options.AddProcessor(capture);
        }));

        var logger = factory.CreateLogger("TaskFlow.SecurityTest");
        var correlationId = Guid.NewGuid().ToString("N");
        logger.LogError(new InvalidOperationException("password=do-not-export"),
            "Rejected sign-in {CorrelationId} {ExceptionType} for {Email} with code {Otp}",
            correlationId, "System.InvalidOperationException", "sensitive@example.com", "654321");

        var record = Assert.Single(capture.Records);
        Assert.Equal("TaskFlow application event", record.Body);
        Assert.Null(record.FormattedMessage);
        Assert.Null(record.Exception);
        Assert.Contains(record.Attributes, attribute => attribute.Key == "CorrelationId" && Equals(attribute.Value, correlationId));
        Assert.DoesNotContain(record.Attributes, attribute => attribute.Key is "Email" or "Otp");
        Assert.DoesNotContain("sensitive@example.com", string.Join("|", record.Attributes.Select(attribute => attribute.Value)));
        Assert.DoesNotContain("654321", string.Join("|", record.Attributes.Select(attribute => attribute.Value)));
    }

    [Fact]
    public async Task OtlpExporterSendsSanitizedExceptionWithCorrelationIdToLocalReceiver()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var requestTask = CaptureHttpRequest(listener);
        var factory = LoggerFactory.Create(builder => builder.AddOpenTelemetry(options =>
        {
            options.ParseStateValues = true;
            options.IncludeFormattedMessage = true;
            options.AddProcessor(new TelemetrySanitizingLogProcessor());
            options.AddOtlpExporter((exporter, processor) =>
            {
                exporter.Endpoint = new Uri($"http://127.0.0.1:{port}/v1/logs");
                exporter.Protocol = OtlpExportProtocol.HttpProtobuf;
                exporter.TimeoutMilliseconds = 5000;
                processor.BatchExportProcessorOptions.MaxQueueSize = 8;
                processor.BatchExportProcessorOptions.MaxExportBatchSize = 8;
                processor.BatchExportProcessorOptions.ScheduledDelayMilliseconds = 100;
                processor.BatchExportProcessorOptions.ExporterTimeoutMilliseconds = 5000;
                processor.ExportProcessorType = ExportProcessorType.Simple;
            });
        }));

        var correlationId = Guid.NewGuid().ToString("N");
        factory.CreateLogger("TaskFlow.ObservabilityTest").LogError(
            new InvalidOperationException("secret-value-must-not-export"),
            "Synthetic exception {ExceptionType} {CorrelationId} {Email}",
            "System.InvalidOperationException", correlationId, "private@example.com");
        factory.Dispose();

        var payload = await requestTask.WaitAsync(TimeSpan.FromSeconds(10));
        var exported = Encoding.UTF8.GetString(payload);
        Assert.Contains("TaskFlow application event", exported, StringComparison.Ordinal);
        Assert.Contains(correlationId, exported, StringComparison.Ordinal);
        Assert.Contains("System.InvalidOperationException", exported, StringComparison.Ordinal);
        Assert.DoesNotContain("secret-value-must-not-export", exported, StringComparison.Ordinal);
        Assert.DoesNotContain("private@example.com", exported, StringComparison.Ordinal);
    }

    [Fact]
    public void TelemetryProviderFailureDoesNotThrowIntoApplicationLoggingCall()
    {
        using var reservation = new TcpListener(IPAddress.Loopback, 0);
        reservation.Start();
        var port = ((IPEndPoint)reservation.LocalEndpoint).Port;
        reservation.Stop();

        using var factory = LoggerFactory.Create(builder => builder.AddOpenTelemetry(options =>
        {
            options.AddProcessor(new TelemetrySanitizingLogProcessor());
            options.AddOtlpExporter((exporter, processor) =>
            {
                exporter.Endpoint = new Uri($"http://127.0.0.1:{port}/v1/logs");
                exporter.Protocol = OtlpExportProtocol.HttpProtobuf;
                exporter.TimeoutMilliseconds = 250;
                processor.BatchExportProcessorOptions.ScheduledDelayMilliseconds = 100;
                processor.BatchExportProcessorOptions.ExporterTimeoutMilliseconds = 250;
            });
        }));

        var logger = factory.CreateLogger("TaskFlow.ObservabilityFailureTest");
        var exception = Record.Exception(() => logger.LogError("Synthetic telemetry transport failure test"));
        Assert.Null(exception);
    }

    private sealed class StubHttpClientFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new();
    }

    private static async Task<byte[]> CaptureHttpRequest(TcpListener listener)
    {
        using var client = await listener.AcceptTcpClientAsync();
        using var stream = client.GetStream();
        using var headerBytes = new MemoryStream();
        var endOfHeaders = new byte[] { 13, 10, 13, 10 };
        var tail = new Queue<byte>(4);
        while (true)
        {
            var value = stream.ReadByte();
            if (value < 0) throw new EndOfStreamException("OTLP exporter closed before sending headers.");
            headerBytes.WriteByte((byte)value);
            tail.Enqueue((byte)value);
            if (tail.Count > 4) tail.Dequeue();
            if (tail.SequenceEqual(endOfHeaders)) break;
        }

        var headers = Encoding.ASCII.GetString(headerBytes.ToArray());
        var contentLength = headers.Split("\r\n", StringSplitOptions.RemoveEmptyEntries)
            .First(header => header.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
            .Split(':', 2)[1].Trim();
        var body = new byte[int.Parse(contentLength)];
        await stream.ReadExactlyAsync(body);
        var response = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        await stream.WriteAsync(response);
        return body;
    }

    private sealed class CapturingLogger<T> : ILogger<T>
    {
        public List<string> Messages { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter) => Messages.Add(formatter(state, exception));
    }

    private sealed class CapturingLogProcessor : BaseProcessor<LogRecord>
    {
        public List<CapturedLog> Records { get; } = [];

        public override void OnEnd(LogRecord logRecord) => Records.Add(new CapturedLog(
            logRecord.Body?.ToString(),
            logRecord.FormattedMessage,
            logRecord.Exception,
            logRecord.Attributes?.ToArray() ?? []));
    }

    private sealed record CapturedLog(string? Body, string? FormattedMessage, Exception? Exception,
        KeyValuePair<string, object?>[] Attributes);
}
