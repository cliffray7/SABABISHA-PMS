import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';
import { account, request, mailToken, cleanup, prefix } from './helpers.mjs';

const browser = await chromium.launch({ channel: 'msedge', headless: true });
try {
  const owner = await account('owner');
  const teammate = await account('teammate');
  const guest = await account('guest');
  const lead = await account('lead');
  const manager = await account('manager');
  const organization = await request('/organizations', { token: owner.accessToken, body: { name: prefix, slug: prefix } });
  const project = await request('/projects', { token: owner.accessToken, body: { organizationId: organization.id, name: 'Role control project', status: 'ACTIVE' } });

  for (const [person, role] of [[teammate, 'MEMBER'], [guest, 'GUEST'], [lead, 'MEMBER'], [manager, 'MEMBER']]) {
    await request(`/organizations/${organization.id}/invitations`, { token: owner.accessToken, body: { email: person.email, role } });
    const token = await mailToken(person.email, 'Join');
    await request('/organizations/invitations/accept', { token: person.accessToken, body: { token } });
  }
  await request(`/projects/${project.id}/members`, { token: owner.accessToken, body: { userId: teammate.userId, role: 'CONTRIBUTOR' }, status: 204 });
  await request(`/projects/${project.id}/members`, { token: owner.accessToken, body: { userId: guest.userId, role: 'VIEWER' }, status: 204 });
  await request(`/projects/${project.id}/members`, { token: owner.accessToken, body: { userId: lead.userId, role: 'TEAM_LEAD' }, status: 204 });
  await request(`/projects/${project.id}/members`, { token: owner.accessToken, body: { userId: manager.userId, role: 'PROJECT_MANAGER' }, status: 204 });

  let persistedRole = 'CONTRIBUTOR';
  const updateCodes = [
    ['invalid_project_role', 400, 'Choose one of the supported project roles.'],
    ['self_role_change_not_allowed', 400, 'You cannot change your own project role this way.'],
    ['guest_project_role_must_be_viewer', 400, 'Organization guests can only have the Viewer project role.'],
    ['project_must_retain_manager', 400, 'This project must keep at least one active project manager.'],
    ['project_role_update_forbidden', 403, 'You do not have permission to change project member roles.'],
    ['project_manager_grant_forbidden', 403, 'Only organization admins and project managers can grant the Project Manager role.'],
    ['project_role_update_conflict', 409, 'The project is busy. Refresh the member list, then try again.']
  ];
  let updateIndex = -1;
  const context = await browser.newContext();
  const page = await context.newPage();
  page.setDefaultTimeout(30000);
  await context.route(url => new URL(url).pathname === `/api/v1/projects/${project.id}/members`, async route => {
    const rows = await request(`/projects/${project.id}/members`, { token: owner.accessToken });
    for (const row of rows) if (row.userId === teammate.userId) row.role = persistedRole;
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(rows) });
  });
  await context.route(url => new URL(url).pathname === `/api/v1/projects/${project.id}/members/${teammate.userId}`, async route => {
    if (route.request().method() !== 'PATCH') return route.continue();
    updateIndex++;
    const body = route.request().postDataJSON();
    if (updateIndex === 0) {
      assert.equal(body.role, 'TEAM_LEAD');
      await new Promise(resolve => setTimeout(resolve, 350));
      persistedRole = body.role;
      return route.fulfill({ status: 204 });
    }
    if (updateIndex === 1) return route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'project_must_retain_manager', message: 'Server message' }) });
    if (updateIndex === 2) return route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ message: 'Temporary service failure.' }) });
    const [code, status] = updateCodes[updateIndex - 3];
    return route.fulfill({ status, contentType: 'application/json', body: JSON.stringify({ code, message: 'Server message' }) });
  });

  async function login(target, user) {
    await target.goto('http://127.0.0.1:5173/', { waitUntil: 'domcontentloaded' });
    await target.evaluate(auth => {
      localStorage.setItem('taskflow.accessToken', auth.accessToken);
      localStorage.setItem('taskflow.refreshToken', auth.refreshToken);
      localStorage.setItem('taskflow.userId', auth.userId);
    }, user);
    await target.reload({ waitUntil: 'domcontentloaded' });
    await target.locator('.sidebar').getByRole('button', { name: 'Members', exact: true }).click();
    await target.locator('.view-tabs').getByRole('button', { name: 'Role control project', exact: true }).click();
  }

  await login(page, owner);
  const teammateRow = page.locator('.member-row').filter({ hasText: teammate.email });
  const roleSelect = teammateRow.locator('select');
  await roleSelect.waitFor();
  assert.equal(await roleSelect.getAttribute('aria-label'), 'Project role for Teammate Smoke');
  assert.equal(await roleSelect.locator('option[value="PROJECT_MANAGER"]').count(), 1, 'Authorized organization admins can grant project manager.');
  const guestRow = page.locator('.member-row').filter({ hasText: guest.email });
  assert.equal(await guestRow.getByRole('combobox').count(), 0, 'Guest target should show a fixed viewer role.');
  assert.equal((await guestRow.innerText()).includes('VIEWER'), true);
  const waitForRole = async expected => page.waitForFunction(({ email, expectedRole }) => {
    const row = [...document.querySelectorAll('.member-row')].find(element => element.textContent?.includes(email));
    const control = row?.querySelector('select');
    return control?.value === expectedRole && !control.disabled;
  }, { email: teammate.email, expectedRole: expected });

  await roleSelect.selectOption('TEAM_LEAD');
  assert.equal(await roleSelect.isDisabled(), true, 'The control is disabled while the request is in flight.');
  await waitForRole('TEAM_LEAD');
  assert.equal(await roleSelect.inputValue(), 'TEAM_LEAD', 'A successful mocked update is reflected after refresh.');

  await roleSelect.selectOption('VIEWER');
  await page.getByRole('alert').filter({ hasText: 'This project must keep at least one active project manager.' }).waitFor();
  await waitForRole('TEAM_LEAD');
  assert.equal(await roleSelect.inputValue(), 'TEAM_LEAD', 'Last-manager failure restores the confirmed role.');
  await roleSelect.selectOption('CONTRIBUTOR');
  await page.getByRole('alert').filter({ hasText: 'Temporary service failure.' }).waitFor();
  await waitForRole('TEAM_LEAD');
  assert.equal(await roleSelect.inputValue(), 'TEAM_LEAD', 'Unexpected failure restores the confirmed role.');

  for (const [code, , expectedMessage] of updateCodes) {
    const nextRole = await roleSelect.inputValue() === 'VIEWER' ? 'TEAM_LEAD' : 'VIEWER';
    await roleSelect.selectOption(nextRole);
    await page.getByRole('alert').filter({ hasText: expectedMessage }).waitFor();
    await waitForRole('TEAM_LEAD');
    assert.equal(await roleSelect.inputValue(), 'TEAM_LEAD', `${code} must restore the last confirmed role.`);
  }

  const leadContext = await browser.newContext();
  const leadPage = await leadContext.newPage();
  leadPage.setDefaultTimeout(30000);
  await login(leadPage, lead);
  assert.equal(await leadPage.getByRole('combobox', { name: /^Project role for / }).count(), 0, 'Team leads cannot edit project roles.');
  assert.equal(await leadPage.locator('option[value="PROJECT_MANAGER"]').count(), 0, 'Non-grantors never receive a manager option.');
  await leadContext.close();
  const managerContext = await browser.newContext();
  const managerPage = await managerContext.newPage();
  managerPage.setDefaultTimeout(30000);
  await login(managerPage, manager);
  const managerTargetRow = managerPage.locator('.member-row').filter({ hasText: teammate.email });
  assert.equal(await managerTargetRow.locator('select').count(), 1, 'Project managers can edit project member roles.');
  assert.equal(await managerTargetRow.locator('select option[value="PROJECT_MANAGER"]').count(), 1, 'Project managers may grant Project Manager.');
  await managerContext.close();
  await context.close();
  console.log('PASS: organization-admin/project-manager visibility, team-lead read-only display, guest viewer-only display, manager option permissions, success, in-flight disable, stable API error mapping, and failure rollback.');
} finally {
  await browser.close();
  cleanup();
}
