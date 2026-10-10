import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';
const baseUrl = process.env.VITE_SMOKE_URL ?? 'http://127.0.0.1:5173';

const browser = await chromium.launch({ channel: 'msedge', headless: true });
const orgOne = '11111111-1111-4111-8111-111111111111';
const orgTwo = '22222222-2222-4222-8222-222222222222';
const projectOne = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const projectTwo = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const projectTrashed = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const activityRequests = [];
const errors = [];

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.setDefaultTimeout(10000);
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    localStorage.setItem('taskflow.accessToken', 'superadmin-smoke');
    localStorage.setItem('taskflow.refreshToken', 'superadmin-refresh');
    localStorage.setItem('taskflow.userId', 'superadmin-1');
    location.hash = 'admin/activity';
  });
  await page.route('**/api/v1/**', async route => {
    const url = new URL(route.request().url());
    const path = url.pathname.replace(/^.*\/api\/v1/, '');
    if (path === '/account') return route.fulfill({ json: { id: 'superadmin-1', firstName: 'Platform', lastName: 'Admin', email: 'admin@example.invalid' } });
    if (path === '/admin/dashboard') return route.fulfill({ json: {} });
    if (path === '/admin/organizations') return route.fulfill({ json: [
      { id: orgOne, name: 'Northwind' }, { id: orgTwo, name: 'Contoso' }
    ] });
    if (path === '/admin/projects') {
      assert.equal(url.searchParams.get('includeTrashed'), 'true');
      if (url.searchParams.get('organizationId') === orgOne) return route.fulfill({ json: [
        { id: projectOne, name: 'Alpha', status: 'ACTIVE', archivedAt: null, deletedAt: null },
        { id: projectTrashed, name: 'Legacy', status: 'ACTIVE', archivedAt: null, deletedAt: '2026-10-01T00:00:00Z' }
      ] });
      if (url.searchParams.get('organizationId') === orgTwo) return route.fulfill({ json: [
        { id: projectTwo, name: 'Beta', status: 'ACTIVE', archivedAt: null, deletedAt: null }
      ] });
      return route.fulfill({ json: [] });
    }
    if (path === '/admin/activity-events') {
      activityRequests.push(Object.fromEntries(url.searchParams.entries()));
      const filtered = url.searchParams.get('projectId') === projectTwo;
      const organizationId = url.searchParams.get('organizationId');
      const projectId = filtered ? projectTwo : projectOne;
      return route.fulfill({ json: {
        items: [{
          eventId: filtered ? 'event-two' : 'event-one', organizationId: organizationId || orgOne,
          organizationName: filtered ? 'Contoso' : 'Northwind', projectId,
          projectName: filtered ? 'Beta' : 'Alpha', actorUserId: 'actor-1', actorName: 'Project Owner',
          category: 'Projects', action: 'project.updated', entityType: 'project', entityId: projectId,
          entityName: filtered ? 'Beta' : 'Alpha', description: 'updated project details',
          status: 'succeeded', correlationId: 'request-123', createdAt: '2026-10-10T08:00:00Z'
        }], nextCursor: null
      } });
    }
    return route.fulfill({ json: [] });
  });

  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
  await page.getByRole('heading', { name: 'Activity', exact: true }).waitFor();
  await page.getByText('updated project details').waitFor();
  assert.equal(await page.locator('.admin-activity-project [role="combobox"]').getAttribute('aria-disabled'), 'true',
    'Project selection waits for an organization.');

  await page.locator('.admin-activity-organization [role="combobox"]').click();
  await page.getByRole('option', { name: 'Northwind' }).click();
  await page.locator('.admin-activity-project [role="combobox"]').waitFor();
  await page.locator('.admin-activity-project [role="combobox"]').click();
  await page.getByRole('option', { name: 'Legacy · In Trash' }).waitFor();
  await page.keyboard.press('Escape');
  await page.locator('.admin-activity-project [role="combobox"]').click();
  await page.getByRole('option', { name: 'Alpha' }).click();
  await page.getByText('updated project details').waitFor();
  assert.ok(activityRequests.some(request => request.organizationId === orgOne && request.projectId === projectOne),
    'The selected organization and project are sent to the platform activity endpoint.');

  await page.locator('.admin-activity-organization [role="combobox"]').click();
  await page.getByRole('option', { name: 'Contoso' }).click();
  await page.locator('.admin-activity-project [role="combobox"]').click();
  await page.getByRole('option', { name: 'Beta' }).click();
  await page.getByText('updated project details').waitFor();
  assert.ok(activityRequests.some(request => request.organizationId === orgTwo && request.projectId === projectTwo),
    'Changing organizations clears the old project and scopes the next query to the new project.');
  await page.locator('.activity-timeline-content summary').click();
  await page.getByText(`Project: Beta (${projectTwo})`, { exact: true }).waitFor();
  await page.getByText(`Organization: Contoso (${orgTwo})`, { exact: true }).waitFor();
  await page.getByText(`Actor: Project Owner (actor-1)`, { exact: true }).waitFor();
  assert.deepEqual(errors, []);
  console.log('PASS: Super Admin organization-to-project activity drill-down, retained Trash labelling, scoped server query, and event details.');
} finally {
  await browser.close();
}
