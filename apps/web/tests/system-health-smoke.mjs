import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';

const baseUrl = process.env.VITE_SMOKE_URL ?? 'http://127.0.0.1:5173';
const browser = await chromium.launch({ channel: 'msedge', headless: true });

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.setDefaultTimeout(10000);
  const healthRequests = [];
  await page.addInitScript(() => {
    localStorage.setItem('taskflow.accessToken', 'health-smoke-token');
    localStorage.setItem('taskflow.refreshToken', 'health-smoke-refresh');
    localStorage.setItem('taskflow.userId', 'health-smoke-admin');
    location.hash = 'admin/health';
  });
  await page.route('**/api/v1/**', async route => {
    const path = new URL(route.request().url()).pathname.replace(/^.*\/api\/v1/, '');
    if (path === '/account') return route.fulfill({ json: { id: 'health-smoke-admin', firstName: 'Platform', lastName: 'Admin', email: 'admin@example.invalid' } });
    if (path === '/admin/dashboard') return route.fulfill({ json: {} });
    if (path === '/admin/observability') {
      const range = new URL(route.request().url()).searchParams.get('range') ?? '1h';
      const isConfigured = range === '7d';
      return route.fulfill({ json: {
        range, queriedAt: '2026-10-10T09:00:00Z',
        metrics: isConfigured ? {
          status: 'available', requestsPerSecond: 10, serverErrorsPerSecond: 1, serverErrorPercent: 10,
          p95DurationMilliseconds: 250, message: 'Prometheus time-series results.',
          series: [
            { timestamp: '2026-10-10T08:00:00Z', requestsPerSecond: 8, serverErrorsPerSecond: 0, serverErrorPercent: 0, p50DurationMilliseconds: 80, p95DurationMilliseconds: 180, p99DurationMilliseconds: 300 },
            { timestamp: '2026-10-10T09:00:00Z', requestsPerSecond: 10, serverErrorsPerSecond: 1, serverErrorPercent: 10, p50DurationMilliseconds: 100, p95DurationMilliseconds: 250, p99DurationMilliseconds: 420 }
          ]
        } : {
          status: 'not_configured', requestsPerSecond: null, serverErrorsPerSecond: null, serverErrorPercent: null,
          p95DurationMilliseconds: null, message: 'Grafana metrics read access is not configured.', series: []
        },
        logs: { status: 'not_configured', items: [], message: 'Grafana logs read access is not configured.' },
        traces: { status: 'not_configured', items: [], message: 'Grafana traces read access is not configured.' }
      } });
    }
    if (path === '/admin/system-health') {
      healthRequests.push(route.request());
      if (healthRequests.length === 1) return route.abort('timedout');
      if (healthRequests.length === 2) return route.fulfill({ status: 503, json: { code: 'HEALTH_TEMPORARILY_UNAVAILABLE' } });
      return route.fulfill({ json: {
        overallStatus: 'unknown', checkedAt: '2026-10-10T09:00:00Z', components: [
          { id: 'api', name: 'ASP.NET Core API', status: 'healthy', signal: 'request', summary: 'The API is responding to this authenticated health request.' },
          { id: 'database', name: 'SQL Server', status: 'healthy', signal: 'connectivity', summary: 'SQL Server accepted a connectivity check.' },
          { id: 'email', name: 'Email service', status: 'configured', signal: 'configuration', summary: 'Configuration exists; delivery is not probed.' },
          { id: 'ai', name: 'AI provider', status: 'configured', signal: 'configuration', summary: 'Configuration exists; provider availability is not probed.' },
          { id: 'realtime', name: 'Realtime (SignalR)', status: 'not_instrumented', signal: 'not_instrumented', summary: 'Realtime delivery is not measured.' },
          { id: 'background_jobs', name: 'Background jobs', status: 'not_instrumented', signal: 'not_instrumented', summary: 'Job runs are not measured.' }
        ]
      } });
    }
    return route.fulfill({ json: {} });
  });

  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
  await page.getByRole('heading', { name: 'System health', exact: true }).waitFor();
  await page.getByRole('heading', { name: 'Telemetry overview' }).waitFor();
  await page.getByText('Grafana metrics read access is not configured.').waitFor();
  await page.getByText('No matching metric samples for this chart and time range. Missing data is not shown as zero.').first().waitFor();
  await page.getByRole('combobox', { name: 'Time range' }).click();
  await page.getByRole('option', { name: 'Last 7 days' }).click();
  await page.locator('.recharts-line').first().waitFor();
  assert.equal(await page.locator('.recharts-line').count(), 6, 'Historical metrics render request, error, and latency percentile lines.');
  await page.getByText('Unable to load system health.', { exact: false }).waitFor();
  await page.getByRole('button', { name: 'Refresh checks' }).click();
  await page.getByText('Unable to load system health.', { exact: false }).waitFor();
  await page.getByRole('button', { name: 'Refresh checks' }).click();
  await page.getByText('Core health: healthy.', { exact: false }).waitFor();
  await page.getByText('configured', { exact: true }).first().waitFor();
  await page.getByText('not instrumented', { exact: true }).first().waitFor();
  assert.equal(healthRequests.length, 3, 'Timeout and server failure recover only after explicit retries.');
  assert.equal(await page.locator('.admin-health-overall').getAttribute('class').then(value => value.includes('MuiAlert-standardSuccess')), true,
    'The core status is healthy because both API and database checks passed; unmeasured services remain separate.');
  console.log('System Health smoke passed: no-data states, historical charts, and health retry/status semantics.');
} finally {
  await browser.close();
}
