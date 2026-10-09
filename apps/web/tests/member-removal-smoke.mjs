import assert from 'node:assert/strict';
import { chromium } from 'playwright-core';

const organizationId = 'org-1';
const projectId = 'project-1';
const actorId = 'actor-1';
const memberId = 'member-1';
const browser = await chromium.launch({ channel: 'msedge', headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
page.setDefaultTimeout(10000);
page.setDefaultNavigationTimeout(30000);
page.on('pageerror', error => console.error('Browser page error:', error.message));
const state = {
  projectPreviewCount: 0,
  latestProjectSnapshot: '',
  projectConfirmCount: 0,
  organizationConfirmCount: 0,
  directDeleteCalls: [],
  removedProjectMember: false,
  removedOrganizationMember: false,
  denyProjectPreview: false,
  oversizedPreview: false,
  archivedPreview: false,
  rejectOrganizationConfirmOnce: true
};

const member = (userId, firstName, role) => ({
  id: userId,
  userId,
  firstName,
  lastName: 'Member',
  email: `${userId}@example.invalid`,
  role
});
const preview = (snapshotHash, { multipleProjects = false, oversized = false, archived = false } = {}) => {
  const tasks = oversized
    ? Array.from({ length: 101 }, (_, index) => task(`task-${index + 1}`, `Task ${index + 1}`))
    : multipleProjects
      ? [task('task-1', 'Organization task one')]
      : [task('task-1', 'Implement client workflow')];
  const affectedProjects = [projectPreview(projectId, tasks, archived)];
  if (multipleProjects) affectedProjects.push(projectPreview('project-2', [task('task-2', 'Organization task two')]));
  return {
    projectId: multipleProjects ? null : projectId,
    organizationId,
    memberId,
    snapshotHash,
    affectedTaskCount: oversized ? 101 : multipleProjects ? 2 : 1,
    affectedProjects,
    expiredTrashCleanup: []
  };
};
const task = (taskId, title) => ({
  taskId,
  parentTaskId: null,
  title,
  status: 'TO DO',
  currentAssigneeIds: [memberId],
  requiredResolution: 'REASSIGN_OR_UNASSIGN'
});
const projectPreview = (id, tasks, archived = false) => ({
  projectId: id,
  lifecycle: archived ? 'ARCHIVED' : 'ACTIVE',
  ownerTransferRequired: false,
  managerInvariantBlocked: false,
  eligibleReplacementMembers: archived ? [] : [{ userId: 'replacement-1', displayName: 'Morgan Eligible' }],
  tasks: tasks.map(item => ({ ...item, requiredResolution: archived ? 'ACCEPT_LIFECYCLE_INACTIVATION' : item.requiredResolution })),
  historicalAttributionsToInactivate: archived ? [{ taskId: 'done-task', status: 'DONE', taskInTrash: false, currentAssigneeIds: [memberId], actionOnConfirm: 'UNASSIGNED' }] : []
});
const json = (route, status, body) => route.fulfill({
  status,
  contentType: 'application/json',
  body: JSON.stringify(body)
});

await context.addInitScript(({ actorId, organizationId, projectId }) => {
  localStorage.setItem('taskflow.accessToken', 'mock-access-token');
  localStorage.setItem('taskflow.refreshToken', 'mock-refresh-token');
  localStorage.setItem('taskflow.userId', actorId);
  localStorage.setItem('taskflow.organizationId', organizationId);
  localStorage.setItem('taskflow.projectId', projectId);
}, { actorId, organizationId, projectId });

await context.route('**/api/v1/**', async route => {
  const url = new URL(route.request().url());
  const path = url.pathname.replace('/api/v1', '');
  const method = route.request().method();
  if (method === 'DELETE' && /\/members\/[^/]+$/.test(path)) {
    state.directDeleteCalls.push(path);
    return json(route, 500, { message: 'Legacy direct member DELETE must not be called.' });
  }
  if (method === 'GET' && path === '/account') {
    return json(route, 200, { id: actorId, firstName: 'Project', lastName: 'Admin', email: 'admin@example.invalid', timezone: 'UTC' });
  }
  if (method === 'GET' && path === '/admin/dashboard') return json(route, 403, { message: 'Forbidden' });
  if (method === 'GET' && path === '/organizations') {
    return json(route, 200, [{ id: organizationId, name: 'Example Organization', slug: 'example', role: 'OWNER' }]);
  }
  if (method === 'GET' && path === '/projects') {
    return json(route, 200, [{ id: projectId, organizationId, name: 'Removal Project', status: 'ACTIVE', role: 'PROJECT_MANAGER' }]);
  }
  if (method === 'GET' && path === `/organizations/${organizationId}/members`) {
    const rows = [member(actorId, 'Project', 'OWNER')];
    if (!state.removedOrganizationMember) rows.push(member(memberId, 'Taylor', 'MEMBER'));
    return json(route, 200, rows);
  }
  if (method === 'GET' && path === `/projects/${projectId}/members`) {
    const rows = [member(actorId, 'Project', 'PROJECT_MANAGER')];
    if (!state.removedProjectMember) rows.push(member(memberId, 'Taylor', 'CONTRIBUTOR'));
    return json(route, 200, rows);
  }
  if (method === 'GET' && path === `/organizations/${organizationId}/invitations`) return json(route, 200, []);
  if (method === 'GET' && path === '/tasks') return json(route, 200, { data: [] });
  if (method === 'GET' && path === '/dashboard/metrics') return json(route, 200, { myTasks: 0, overdueTasks: 0, completedTasks: 0, inProgressTasks: 0, totalTasks: 0 });
  if (method === 'GET' && path === `/projects/${projectId}/progress`) return json(route, 200, {
    projectId, projectStatus: 'ACTIVE', hasTasks: false, totalEligibleTasks: 0,
    completedTasks: 0, progressPercent: null, outstandingTaskCount: 0,
    overdueTaskCount: 0, timezoneIdUsed: 'UTC'
  });
  if (method === 'GET' && path === `/projects/${projectId}/members/${memberId}/removal-preview`) {
    if (state.denyProjectPreview) return json(route, 403, { code: 'MEMBER_REMOVAL_FORBIDDEN', message: 'Forbidden' });
    state.projectPreviewCount++;
    state.latestProjectSnapshot = `snapshot-${state.projectPreviewCount}`;
    return json(route, 200, preview(state.latestProjectSnapshot, { oversized: state.oversizedPreview, archived: state.archivedPreview }));
  }
  if (method === 'POST' && path === `/projects/${projectId}/members/${memberId}/remove`) {
    state.projectConfirmCount++;
    const body = route.request().postDataJSON();
    if (state.archivedPreview) {
      assert.deepEqual(body, {
        snapshotHash: state.latestProjectSnapshot,
        resolutions: [{ taskId: 'task-1', action: 'ACCEPT_LIFECYCLE_INACTIVATION', replacementUserId: null }]
      });
      return route.fulfill({ status: 204, body: '' });
    }
    if (state.projectConfirmCount === 1) {
      assert.deepEqual(body, {
        snapshotHash: state.latestProjectSnapshot,
        resolutions: [{ taskId: 'task-1', action: 'REASSIGN', replacementUserId: 'replacement-1' }]
      });
      return json(route, 409, { code: 'MEMBER_REMOVAL_PREVIEW_STALE', message: 'Stale preview.' });
    }
    assert.deepEqual(body, {
      snapshotHash: state.latestProjectSnapshot,
      resolutions: [{ taskId: 'task-1', action: 'UNASSIGN', replacementUserId: null }]
    });
    state.removedProjectMember = true;
    return route.fulfill({ status: 204, body: '' });
  }
  if (method === 'GET' && path === `/organizations/${organizationId}/members/${memberId}/deactivation-preview`) {
    return json(route, 200, preview('org-snapshot', { multipleProjects: true }));
  }
  if (method === 'POST' && path === `/organizations/${organizationId}/members/${memberId}/deactivate`) {
    state.organizationConfirmCount++;
    const expected = {
      snapshotHash: 'org-snapshot',
      resolutions: [
        { taskId: 'task-1', action: 'UNASSIGN', replacementUserId: null },
        { taskId: 'task-2', action: 'UNASSIGN', replacementUserId: null }
      ]
    };
    assert.deepEqual(route.request().postDataJSON(), expected);
    if (state.rejectOrganizationConfirmOnce) {
      state.rejectOrganizationConfirmOnce = false;
      return json(route, 409, { code: 'PROJECT_MUST_RETAIN_MANAGER', message: 'Server manager invariant.' });
    }
    state.removedOrganizationMember = true;
    return route.fulfill({ status: 204, body: '' });
  }
  return json(route, 404, { message: `Unmocked API request: ${method} ${path}` });
});

try {
  await page.goto('http://127.0.0.1:5173/', { waitUntil: 'domcontentloaded' });
  await page.getByRole('button', { name: 'Members', exact: true }).click();
  await page.locator('.view-tabs').getByRole('button', { name: 'Removal Project' }).click();
  const projectRow = page.locator('.member-row').filter({ hasText: 'member-1@example.invalid' });

  state.denyProjectPreview = true;
  await projectRow.getByRole('button', { name: 'Remove from project' }).click();
  await page.getByRole('alert').filter({ hasText: 'You do not have permission to remove this member.' }).waitFor();
  assert.equal(await projectRow.count(), 1, 'Permission failure must leave the member in the list.');
  await page.getByRole('button', { name: 'Close dialog' }).click();
  state.denyProjectPreview = false;

  state.oversizedPreview = true;
  await projectRow.getByRole('button', { name: 'Remove from project' }).click();
  await page.getByRole('alert').filter({ hasText: 'This operation exceeds the 100-task limit' }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Remove member', exact: true }).isDisabled(), true);
  assert.equal(state.projectConfirmCount, 0, 'Oversized previews must not be submitted.');
  await page.getByRole('button', { name: 'Close dialog' }).click();
  state.oversizedPreview = false;
  state.projectPreviewCount = 0;

  state.archivedPreview = true;
  await projectRow.getByRole('button', { name: 'Remove from project' }).click();
  await page.getByText('This assignment will be inactivated because the project is archived or in retained Trash.').waitFor();
  assert.equal(await page.getByLabel('Replacement for Implement client workflow').count(), 0);
  const lifecycleAcknowledgement = page.getByLabel('Acknowledge lifecycle inactivation for Implement client workflow');
  await lifecycleAcknowledgement.check();
  const removeMemberButton = page.getByRole('button', { name: 'Remove member', exact: true });
  await lifecycleAcknowledgement.uncheck();
  assert.equal(await removeMemberButton.isDisabled(), true, 'Clearing the lifecycle acknowledgement must disable confirmation.');
  assert.equal(state.projectConfirmCount, 0, 'Clearing the lifecycle acknowledgement must not submit a confirmation.');
  await lifecycleAcknowledgement.check();
  await removeMemberButton.click();
  await page.getByRole('button', { name: 'Remove from project' }).waitFor();
  state.archivedPreview = false;
  state.projectConfirmCount = 0;
  state.projectPreviewCount = 0;

  await projectRow.getByRole('button', { name: 'Remove from project' }).click();
  await page.getByText('Implement client workflow', { exact: true }).waitFor();
  await page.getByLabel('Resolution for Implement client workflow').selectOption('REASSIGN');
  await page.getByLabel('Replacement for Implement client workflow').selectOption('replacement-1');
  await page.getByRole('button', { name: 'Remove member', exact: true }).click();
  await page.getByText('The previous preview was stale. Review this updated preview and confirm again.').waitFor();
  assert.equal(await page.getByLabel('Resolution for Implement client workflow').inputValue(), '', 'Stale preview must clear prior choices.');
  assert.equal(state.projectConfirmCount, 1, 'Stale response must not auto-confirm the replacement preview.');
  await page.getByLabel('Resolution for Implement client workflow').selectOption('UNASSIGN');
  await page.getByRole('button', { name: 'Remove member', exact: true }).click();
  await projectRow.waitFor({ state: 'detached' });

  await page.locator('.view-tabs').getByRole('button', { name: 'Organization', exact: true }).click();
  const organizationRow = page.locator('.member-row').filter({ hasText: 'member-1@example.invalid' });
  await organizationRow.getByRole('button', { name: 'Deactivate member' }).click();
  await page.getByText('Organization task one', { exact: true }).waitFor();
  await page.getByText('Organization task two', { exact: true }).waitFor();
  await page.getByLabel('Resolution for Organization task one').selectOption('UNASSIGN');
  await page.getByLabel('Resolution for Organization task two').selectOption('UNASSIGN');
  const deactivateDialog = page.getByRole('dialog', { name: 'Deactivate organization member' });
  await deactivateDialog.getByRole('button', { name: 'Deactivate member', exact: true }).click();
  await deactivateDialog.getByRole('alert').filter({ hasText: 'The project must retain at least one eligible active manager.' }).waitFor();
  assert.equal(await organizationRow.count(), 1, 'Manager conflict must not remove the member locally.');
  await deactivateDialog.getByRole('button', { name: 'Deactivate member', exact: true }).click();
  await organizationRow.waitFor({ state: 'detached' });

  assert.ok(state.projectPreviewCount >= 2, 'Stale confirmation must fetch a new preview.');
  assert.equal(state.projectConfirmCount, 2);
  assert.equal(state.organizationConfirmCount, 2, 'Organization resolutions are sent as one atomic request, and retry remains one request.');
  assert.deepEqual(state.directDeleteCalls, [], 'Member controls must not call the legacy DELETE routes.');
  console.log('PASS: preview permission rejection, 100-task limit, archived lifecycle acknowledgement, stale reset and explicit reconfirmation, organization-wide multi-project resolution, manager-conflict rollback/retry, success refresh, and no direct DELETE calls.');
} finally {
  await context.close();
  await browser.close();
}
