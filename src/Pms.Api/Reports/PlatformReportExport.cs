using System.Globalization;
using System.IO.Compression;
using System.Text;
using System.Xml.Linq;

namespace Pms.Api.Reports;

public sealed record PlatformUserReport(Guid Id, string FirstName, string LastName, string Email, DateTime CreatedAt);
public sealed record PlatformOrganizationReport(Guid Id, string Name, DateTime CreatedAt);
public sealed record PlatformProjectReport(Guid Id, Guid OrganizationId, string Name, string Status, DateTime CreatedAt);
public sealed record PlatformTaskReport(Guid Id, Guid ProjectId, string Title, string Status, string Priority, DateTime? DueDate, DateTime CreatedAt);

public sealed record PlatformReportData(
    string ReportId,
    DateTime GeneratedAtUtc,
    IReadOnlyList<PlatformUserReport> Users,
    IReadOnlyList<PlatformOrganizationReport> Organizations,
    IReadOnlyList<PlatformProjectReport> Projects,
    IReadOnlyList<PlatformTaskReport> Tasks);

public static class PlatformReportExport
{
    private static readonly XNamespace Main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    private static readonly XNamespace OfficeRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    private static readonly XNamespace PackageRel = "http://schemas.openxmlformats.org/package/2006/relationships";

    public static byte[] Csv(PlatformReportData data)
    {
        using var stream = new MemoryStream();
        using (var writer = new StreamWriter(stream, new UTF8Encoding(true), leaveOpen: true))
        using (var csv = new CsvHelper.CsvWriter(writer, CultureInfo.InvariantCulture))
        {
            csv.WriteField("Record Type"); csv.WriteField("Id"); csv.WriteField("Name");
            csv.WriteField("Email"); csv.WriteField("Organization Id"); csv.WriteField("Project Id");
            csv.WriteField("Status"); csv.WriteField("Priority"); csv.WriteField("Due Date UTC"); csv.WriteField("Created At UTC");
            csv.NextRecord();
            foreach (var user in data.Users)
                WriteRow(csv, "User", user.Id, $"{user.FirstName} {user.LastName}", user.Email, null, null, null, null, null, user.CreatedAt);
            foreach (var organization in data.Organizations)
                WriteRow(csv, "Organization", organization.Id, organization.Name, null, null, null, null, null, null, organization.CreatedAt);
            foreach (var project in data.Projects)
                WriteRow(csv, "Project", project.Id, project.Name, null, project.OrganizationId, null, project.Status, null, null, project.CreatedAt);
            foreach (var task in data.Tasks)
                WriteRow(csv, "Task", task.Id, task.Title, null, null, task.ProjectId, task.Status, task.Priority, task.DueDate, task.CreatedAt);
            writer.Flush();
        }
        return stream.ToArray();
    }

    private static void WriteRow(CsvHelper.CsvWriter csv, string type, Guid id, string name,
        string? email, Guid? organizationId, Guid? projectId, string? status, string? priority,
        DateTime? dueDate, DateTime createdAt)
    {
        csv.WriteField(type); csv.WriteField(id); csv.WriteField(name); csv.WriteField(email);
        csv.WriteField(organizationId); csv.WriteField(projectId); csv.WriteField(status);
        csv.WriteField(priority); csv.WriteField(dueDate?.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture));
        csv.WriteField(createdAt.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture));
        csv.NextRecord();
    }

    public static byte[] Xlsx(PlatformReportData data)
    {
        using var stream = new MemoryStream();
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, true))
        {
            XNamespace contentTypes = "http://schemas.openxmlformats.org/package/2006/content-types";
            AddXml(archive, "[Content_Types].xml", new XDocument(
                new XElement(contentTypes + "Types",
                    new XElement(contentTypes + "Default", new XAttribute("Extension", "rels"), new XAttribute("ContentType", "application/vnd.openxmlformats-package.relationships+xml")),
                    new XElement(contentTypes + "Default", new XAttribute("Extension", "xml"), new XAttribute("ContentType", "application/xml")),
                    new XElement(contentTypes + "Override", new XAttribute("PartName", "/xl/workbook.xml"), new XAttribute("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml")),
                    new XElement(contentTypes + "Override", new XAttribute("PartName", "/xl/styles.xml"), new XAttribute("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml")),
                    new XElement(contentTypes + "Override", new XAttribute("PartName", "/xl/worksheets/sheet1.xml"), new XAttribute("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml")),
                    new XElement(contentTypes + "Override", new XAttribute("PartName", "/xl/worksheets/sheet2.xml"), new XAttribute("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml")))));
            AddXml(archive, "_rels/.rels", new XDocument(
                new XElement(PackageRel + "Relationships",
                    new XElement(PackageRel + "Relationship", new XAttribute("Id", "rId1"),
                        new XAttribute("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"),
                        new XAttribute("Target", "xl/workbook.xml")))));
            AddXml(archive, "xl/workbook.xml", new XDocument(
                new XElement(Main + "workbook", new XAttribute(XNamespace.Xmlns + "r", OfficeRel),
                    new XElement(Main + "sheets",
                        new XElement(Main + "sheet", new XAttribute("name", "Summary"), new XAttribute("sheetId", 1), new XAttribute(OfficeRel + "id", "rId1")),
                        new XElement(Main + "sheet", new XAttribute("name", "Data"), new XAttribute("sheetId", 2), new XAttribute(OfficeRel + "id", "rId2"))))));
            AddXml(archive, "xl/_rels/workbook.xml.rels", new XDocument(
                new XElement(PackageRel + "Relationships",
                    new XElement(PackageRel + "Relationship", new XAttribute("Id", "rId1"), new XAttribute("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"), new XAttribute("Target", "worksheets/sheet1.xml")),
                    new XElement(PackageRel + "Relationship", new XAttribute("Id", "rId2"), new XAttribute("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"), new XAttribute("Target", "worksheets/sheet2.xml")),
                    new XElement(PackageRel + "Relationship", new XAttribute("Id", "rId3"), new XAttribute("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"), new XAttribute("Target", "styles.xml")))));
            AddXml(archive, "xl/styles.xml", Styles());
            AddXml(archive, "xl/worksheets/sheet1.xml", SummarySheet(data));
            AddXml(archive, "xl/worksheets/sheet2.xml", DataSheet(data));
        }
        return stream.ToArray();
    }

    private static XDocument Styles()
    {
        var numFmts = new XElement(Main + "numFmts", new XAttribute("count", 1),
            new XElement(Main + "numFmt", new XAttribute("numFmtId", 164), new XAttribute("formatCode", "yyyy-mm-dd hh:mm")));
        var fonts = new XElement(Main + "fonts", new XAttribute("count", 2),
            new XElement(Main + "font", new XElement(Main + "sz", new XAttribute("val", 11)), new XElement(Main + "name", new XAttribute("val", "Aptos"))),
            new XElement(Main + "font", new XElement(Main + "b"), new XElement(Main + "color", new XAttribute("rgb", "FFFFFFFF")), new XElement(Main + "sz", new XAttribute("val", 11)), new XElement(Main + "name", new XAttribute("val", "Aptos"))));
        var fills = new XElement(Main + "fills", new XAttribute("count", 3),
            new XElement(Main + "fill", new XElement(Main + "patternFill", new XAttribute("patternType", "none"))),
            new XElement(Main + "fill", new XElement(Main + "patternFill", new XAttribute("patternType", "gray125"))),
            new XElement(Main + "fill", new XElement(Main + "patternFill", new XAttribute("patternType", "solid"), new XElement(Main + "fgColor", new XAttribute("rgb", "FF5146D8")), new XElement(Main + "bgColor", new XAttribute("indexed", 64)))));
        var borders = new XElement(Main + "borders", new XAttribute("count", 1),
            new XElement(Main + "border", new XElement(Main + "left"), new XElement(Main + "right"), new XElement(Main + "top"), new XElement(Main + "bottom"), new XElement(Main + "diagonal")));
        var styleXfs = new XElement(Main + "cellStyleXfs", new XAttribute("count", 1),
            new XElement(Main + "xf", new XAttribute("numFmtId", 0), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0)));
        var cellXfs = new XElement(Main + "cellXfs", new XAttribute("count", 3),
            new XElement(Main + "xf", new XAttribute("numFmtId", 0), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0), new XAttribute("xfId", 0), new XAttribute("applyAlignment", 1), new XElement(Main + "alignment", new XAttribute("vertical", "center"))),
            new XElement(Main + "xf", new XAttribute("numFmtId", 0), new XAttribute("fontId", 1), new XAttribute("fillId", 2), new XAttribute("borderId", 0), new XAttribute("xfId", 0), new XAttribute("applyAlignment", 1), new XElement(Main + "alignment", new XAttribute("vertical", "center"))),
            new XElement(Main + "xf", new XAttribute("numFmtId", 164), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0), new XAttribute("xfId", 0), new XAttribute("applyNumberFormat", 1), new XAttribute("applyAlignment", 1), new XElement(Main + "alignment", new XAttribute("vertical", "center"))));
        var cellStyles = new XElement(Main + "cellStyles", new XAttribute("count", 1),
            new XElement(Main + "cellStyle", new XAttribute("name", "Normal"), new XAttribute("xfId", 0), new XAttribute("builtinId", 0)));
        return new XDocument(new XElement(Main + "styleSheet", numFmts, fonts, fills, borders, styleXfs, cellXfs, cellStyles));
    }

    private static XDocument SummarySheet(PlatformReportData data)
    {
        var rows = new List<string[]> {
            new[] { "TASKFLOW", "PLATFORM REPORT" },
            new[] { "Report ID", data.ReportId },
            new[] { "Generated at (UTC)", data.GeneratedAtUtc.ToString("O", CultureInfo.InvariantCulture) },
            new[] { "Scope", "All platform records; no date filters" },
            new[] { "" }, new[] { "SUMMARY", "COUNT" },
            new[] { "Users", data.Users.Count.ToString(CultureInfo.InvariantCulture) },
            new[] { "Organizations", data.Organizations.Count.ToString(CultureInfo.InvariantCulture) },
            new[] { "Projects", data.Projects.Count.ToString(CultureInfo.InvariantCulture) },
            new[] { "Tasks", data.Tasks.Count.ToString(CultureInfo.InvariantCulture) },
            new[] { "Completed tasks", data.Tasks.Count(task => IsDone(task.Status)).ToString(CultureInfo.InvariantCulture) },
            new[] { "Overdue tasks", data.Tasks.Count(task => !IsDone(task.Status) && task.DueDate < data.GeneratedAtUtc).ToString(CultureInfo.InvariantCulture) },
            new[] { "" }, new[] { "TASK STATUS", "COUNT" }
        };
        rows.AddRange(data.Tasks.GroupBy(task => task.Status).OrderBy(group => group.Key)
            .Select(group => new[] { group.Key, group.Count().ToString(CultureInfo.InvariantCulture) }));
        return Sheet(rows, 1, [26, 64], false);
    }

    private static XDocument DataSheet(PlatformReportData data)
    {
        var rows = new List<string[]> {
            new[] { "Record Type", "Id", "Name", "Email", "Organization Id", "Project Id", "Status", "Priority", "Due Date UTC", "Created At UTC" }
        };
        rows.AddRange(data.Users.Select(user => new[] { "User", user.Id.ToString(), $"{user.FirstName} {user.LastName}", user.Email, "", "", "", "", "", user.CreatedAt.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture) }));
        rows.AddRange(data.Organizations.Select(org => new[] { "Organization", org.Id.ToString(), org.Name, "", "", "", "", "", "", org.CreatedAt.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture) }));
        rows.AddRange(data.Projects.Select(project => new[] { "Project", project.Id.ToString(), project.Name, "", project.OrganizationId.ToString(), "", project.Status, "", "", project.CreatedAt.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture) }));
        rows.AddRange(data.Tasks.Select(task => new[] { "Task", task.Id.ToString(), task.Title, "", "", task.ProjectId.ToString(), task.Status, task.Priority, task.DueDate?.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture) ?? "", task.CreatedAt.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture) }));
        return Sheet(rows, 1, [18, 38, 36, 32, 38, 38, 18, 16, 28, 28], true);
    }

    private static XDocument Sheet(IReadOnlyList<string[]> rows, int frozenRows, int[] widths, bool filter)
    {
        var sheetData = new XElement(Main + "sheetData");
        for (var rowIndex = 0; rowIndex < rows.Count; rowIndex++)
        {
            var row = new XElement(Main + "row", new XAttribute("r", rowIndex + 1), new XAttribute("ht", rowIndex == 0 ? 24 : 19), new XAttribute("customHeight", 1));
            for (var colIndex = 0; colIndex < rows[rowIndex].Length; colIndex++)
            {
                var value = rows[rowIndex][colIndex];
                var cell = new XElement(Main + "c", new XAttribute("r", CellRef(rowIndex + 1, colIndex + 1)));
                if (rowIndex == 0) cell.Add(new XAttribute("s", 1));
                if (rowIndex > 0 && ((colIndex == 1 && int.TryParse(value, out _))
                    || (colIndex is 8 or 9 && DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out _))))
                {
                    if (colIndex is 8 or 9)
                    {
                        var date = DateTime.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind).ToUniversalTime();
                        var serial = (date - new DateTime(1899, 12, 30, 0, 0, 0, DateTimeKind.Utc)).TotalDays;
                        cell.Add(new XAttribute("s", 2), new XElement(Main + "v", serial.ToString("0.########", CultureInfo.InvariantCulture)));
                    }
                    else cell.Add(new XAttribute("t", "n"), new XElement(Main + "v", value));
                }
                else
                    cell.Add(new XAttribute("t", "inlineStr"), new XElement(Main + "is", new XElement(Main + "t", new XAttribute(XNamespace.Xml + "space", "preserve"), value)));
                row.Add(cell);
            }
            sheetData.Add(row);
        }
        var elements = new List<object> {
            new XElement(Main + "sheetViews", new XElement(Main + "sheetView", new XAttribute("workbookViewId", 0),
                new XElement(Main + "pane", new XAttribute("ySplit", frozenRows), new XAttribute("topLeftCell", $"A{frozenRows + 1}"), new XAttribute("activePane", "bottomLeft"), new XAttribute("state", "frozen")))),
            new XElement(Main + "sheetFormatPr", new XAttribute("defaultRowHeight", 19)),
            new XElement(Main + "cols", widths.Select((width, index) => new XElement(Main + "col", new XAttribute("min", index + 1), new XAttribute("max", index + 1), new XAttribute("width", width), new XAttribute("customWidth", 1)))),
            sheetData
        };
        if (filter && rows.Count > frozenRows)
            elements.Add(new XElement(Main + "autoFilter", new XAttribute("ref", $"A{frozenRows}:J{rows.Count}")));
        return new XDocument(new XElement(Main + "worksheet", elements));
    }

    private static string CellRef(int row, int column)
    {
        var letters = "";
        while (column > 0) { column--; letters = (char)('A' + column % 26) + letters; column /= 26; }
        return $"{letters}{row}";
    }

    private static void AddXml(ZipArchive archive, string path, XDocument document)
    {
        var entry = archive.CreateEntry(path, CompressionLevel.Optimal);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false));
        document.Save(writer);
    }

    public static byte[] Pdf(PlatformReportData data)
    {
        var taskGroups = data.Tasks.GroupBy(task => task.Status).OrderBy(group => group.Key).ToArray();
        var projectsPerPage = 18;
        var pageCount = Math.Max(1, (int)Math.Ceiling(data.Projects.Count / (double)projectsPerPage));
        var pageContents = new List<string>();
        for (var page = 0; page < pageCount; page++)
        {
            var commands = new StringBuilder();
            Text(commands, 42, 800, "TASKFLOW", 18, "5146D8", true);
            Text(commands, 390, 801, "PLATFORM REPORT", 10, "596579", true);
            Line(commands, 42, 786, 553, 786, "D8DCE5");
            Text(commands, 42, 756, "PLATFORM PERFORMANCE REPORT", 15, "20232B", true);
            Text(commands, 42, 737, "All platform records", 10, "687080");
            Text(commands, 42, 718, $"Generated: {data.GeneratedAtUtc:dd MMM yyyy, HH:mm} UTC", 9, "687080");
            Text(commands, 42, 703, $"Report ID: {data.ReportId}", 9, "687080");
            DrawMetric(commands, 42, 644, "USERS", data.Users.Count.ToString("N0", CultureInfo.InvariantCulture));
            DrawMetric(commands, 174, 644, "ORGANIZATIONS", data.Organizations.Count.ToString("N0", CultureInfo.InvariantCulture));
            DrawMetric(commands, 306, 644, "PROJECTS", data.Projects.Count.ToString("N0", CultureInfo.InvariantCulture));
            DrawMetric(commands, 438, 644, "TASKS", data.Tasks.Count.ToString("N0", CultureInfo.InvariantCulture));
            Text(commands, 42, 616, "TASK STATUS", 11, "20232B", true);
            var y = 594;
            var max = Math.Max(1, taskGroups.Select(group => group.Count()).DefaultIfEmpty(0).Max());
            foreach (var group in taskGroups.Take(6))
            {
                Text(commands, 46, y, Limit(group.Key, 22), 9, "596579");
                Rect(commands, 168, y - 2, 260, 9, "F0F1F5");
                Rect(commands, 168, y - 2, 260d * group.Count() / max, 9, "7165D8");
                Text(commands, 445, y, group.Count().ToString("N0", CultureInfo.InvariantCulture), 9, "20232B", true);
                y -= 20;
            }
            Text(commands, 42, 446, "PROJECT PROGRESS", 11, "20232B", true);
            Text(commands, 42, 427, "Project", 8, "687080", true);
            Text(commands, 284, 427, "Status", 8, "687080", true);
            Text(commands, 385, 427, "Tasks done", 8, "687080", true);
            Text(commands, 489, 427, "Progress", 8, "687080", true);
            Line(commands, 42, 420, 553, 420, "D8DCE5");
            var selected = data.Projects.Skip(page * projectsPerPage).Take(projectsPerPage);
            y = 402;
            foreach (var project in selected)
            {
                var projectTasks = data.Tasks.Where(task => task.ProjectId == project.Id).ToArray();
                var done = projectTasks.Count(task => IsDone(task.Status));
                var percent = projectTasks.Length == 0 ? 0 : (int)Math.Round(done * 100d / projectTasks.Length);
                Text(commands, 42, y, Limit(project.Name, 36), 8, "20232B");
                Text(commands, 284, y, Limit(project.Status, 15), 8, "596579");
                Text(commands, 397, y, $"{done}/{projectTasks.Length}", 8, "596579");
                Text(commands, 489, y, $"{percent}%", 8, "20232B", true);
                Line(commands, 42, y - 6, 553, y - 6, "ECEEF2");
                y -= 17;
            }
            Line(commands, 42, 42, 553, 42, "D8DCE5");
            Text(commands, 42, 27, $"{data.ReportId} · Generated by TaskFlow · {data.GeneratedAtUtc:dd MMM yyyy HH:mm} UTC", 7, "687080");
            Text(commands, 492, 27, $"Page {page + 1} of {pageCount}", 7, "687080");
            pageContents.Add(commands.ToString());
        }

        return BuildPdf(pageContents);
    }

    private static byte[] BuildPdf(IReadOnlyList<string> pages)
    {
        var objects = new List<byte[]>();
        void Add(string value) => objects.Add(Encoding.ASCII.GetBytes(value));
        Add("<< /Type /Catalog /Pages 2 0 R >>");
        var firstPageObject = 3;
        var fontRegular = firstPageObject + pages.Count * 2;
        var fontBold = fontRegular + 1;
        Add($"<< /Type /Pages /Kids [{string.Join(' ', Enumerable.Range(0, pages.Count).Select(i => $"{firstPageObject + i * 2} 0 R"))}] /Count {pages.Count} >>");
        for (var i = 0; i < pages.Count; i++)
        {
            var pageObject = firstPageObject + i * 2;
            var contentObject = pageObject + 1;
            var stream = Encoding.ASCII.GetBytes(pages[i]);
            objects.Add(Encoding.ASCII.GetBytes($"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 {fontRegular} 0 R /F2 {fontBold} 0 R >> >> /Contents {contentObject} 0 R >>"));
            objects.Add(Encoding.ASCII.GetBytes($"<< /Length {stream.Length} >>\nstream\n{pages[i]}\nendstream"));
        }
        Add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
        Add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
        using var output = new MemoryStream();
        void Write(string value) { var bytes = Encoding.ASCII.GetBytes(value); output.Write(bytes); }
        Write("%PDF-1.4\n%TaskFlow\n");
        var offsets = new List<long> { 0 };
        for (var i = 0; i < objects.Count; i++)
        {
            offsets.Add(output.Position);
            Write($"{i + 1} 0 obj\n"); output.Write(objects[i]); Write("\nendobj\n");
        }
        var xref = output.Position;
        Write($"xref\n0 {objects.Count + 1}\n0000000000 65535 f \n");
        foreach (var offset in offsets.Skip(1)) Write($"{offset:0000000000} 00000 n \n");
        Write($"trailer\n<< /Size {objects.Count + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF");
        return output.ToArray();
    }

    private static void DrawMetric(StringBuilder commands, double x, double y, string label, string value)
    {
        Rect(commands, x, y, 116, 54, "F7F8FB", "E1E4EA");
        Text(commands, x + 10, y + 34, label, 7, "687080", true);
        Text(commands, x + 10, y + 11, value, 20, "20232B", true);
    }

    private static void Text(StringBuilder commands, double x, double y, string text, int size, string color, bool bold = false)
    {
        var safe = new string(text.Select(ch => ch is >= ' ' and <= '~' ? ch : ch switch { '·' => '-', '–' or '—' => '-', '’' or '‘' => '\'', '“' or '”' => '"', _ => '?' }).ToArray());
        safe = safe.Replace("\\", "\\\\").Replace("(", "\\(").Replace(")", "\\)");
        commands.AppendFormat(CultureInfo.InvariantCulture, "BT /F{0} {1} Tf {2} rg {3:0.##} {4:0.##} Td ({5}) Tj ET\n", bold ? 2 : 1, size, Rgb(color), x, y, safe);
    }

    private static void Rect(StringBuilder commands, double x, double y, double width, double height, string fill, string? stroke = null)
    {
        if (stroke != null) commands.AppendFormat(CultureInfo.InvariantCulture, "{0} RG ", Rgb(stroke));
        commands.AppendFormat(CultureInfo.InvariantCulture, "{0} rg {1:0.##} {2:0.##} {3:0.##} {4:0.##} re {5}\n", Rgb(fill), x, y, width, height, stroke == null ? "f" : "B");
    }

    private static void Line(StringBuilder commands, double x1, double y1, double x2, double y2, string color) =>
        commands.AppendFormat(CultureInfo.InvariantCulture, "{0} RG {1:0.##} {2:0.##} m {3:0.##} {4:0.##} l S\n", Rgb(color), x1, y1, x2, y2);

    private static string Rgb(string hex) => string.Join(' ', Enumerable.Range(0, 3).Select(i => (Convert.ToInt32(hex.Substring(i * 2, 2), 16) / 255d).ToString("0.###", CultureInfo.InvariantCulture)));
    private static string Limit(string value, int length) => value.Length <= length ? value : value[..(length - 1)] + "…";
    private static bool IsDone(string status) => string.Equals(status, "DONE", StringComparison.OrdinalIgnoreCase) || string.Equals(status, "COMPLETED", StringComparison.OrdinalIgnoreCase);
}
