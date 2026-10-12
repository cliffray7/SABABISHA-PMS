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
    if (path === '/admin/observability') return route.fulfill({ json: {
      range: '1h', queriedAt: '2026-10-10T09:00:00Z',
      metrics: { status: 'not_configured', requestsPerSecond: null, serverErrorsPerSecond: null, serverErrorPercent: null, p95DurationMilliseconds: null, message: 'Grafana metrics read access is not configured.' },
      logs: { status: 'not_configured', items: [], message: 'Grafana logs read access is not configured.' },
      traces: { status: 'not_configured', items: [], message: 'Grafana traces read access is not configured.' }
    } });
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
  await page.getByText('Unable to load system health.', { exact: false }).waitFor();
  await page.getByRole('button', { name: 'Refresh checks' }).click();
  await page.getByText('Unable to load system health.', { exact: false }).waitFor();
  await page.getByRole('button', { name: 'Refresh checks' }).click();
  await page.getByText('Platform core: unknown.', { exact: false }).waitFor();
  await page.getByText('configured', { exact: true }).first().waitFor();
  await page.getByText('not instrumented', { exact: true }).first().waitFor();
  assert.equal(healthRequests.length, 3, 'Timeout and server failure recover only after explicit retries.');
  assert.equal(await page.locator('.admin-health-overall').getAttribute('class').then(value => value.includes('MuiAlert-standardSuccess')), false,
    'Unknown overall status must not be rendered as healthy.');
  console.log('System Health smoke passed: timeout/server failure, explicit retry, and unknown/configured semantics.');
} finally {
  await browser.close();
}
