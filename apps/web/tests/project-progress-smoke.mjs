import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';

const browser = await chromium.launch({ channel: 'msedge', headless: true });
const projectStates = [
  { id: 'project-1', organizationId: 'org-1', name: 'Progress Alpha', status: 'ACTIVE', role: 'PROJECT_MANAGER' },
  { id: 'project-2', organizationId: 'org-1', name: 'Progress Beta', status: 'ON_HOLD', role: 'CONTRIBUTOR' }
];
const tasks = [
  { id: 'task-1', projectId: 'project-1', title: 'Assigned to me', status: 'TO DO', priority: 'MEDIUM', assigneeIds: ['user-1'] },
  { id: 'task-2', projectId: 'project-1', title: 'Assigned elsewhere', status: 'DONE', priority: 'LOW', assigneeIds: ['user-2'] }
];
let progressMode = 'normal';
let progressRequests = 0;
let mutationRequests = 0;
let delayProjectOneProgress = false;
let delayedProjectOneProgressStarted = false;
let releaseDelayedProjectOneProgress;
let delayProjectTwoProgress = false;
let delayedProjectTwoProgressStarted = false;
let releaseDelayedProjectTwoProgress;
let accessibleProjectIds;
let page;

function progress(projectId = 'project-1') {
  if (progressMode === 'empty') return {
    projectId, projectStatus: projectId === 'project-2' ? 'ON_HOLD' : 'ACTIVE', hasTasks: false,
    totalEligibleTasks: 0, completedTasks: 0, progressPercent: null,
    outstandingTaskCount: 0, overdueTaskCount: 0, timezoneIdUsed: 'Africa/Nairobi'
  };
  if (progressMode === 'zero') return {
    projectId, projectStatus: 'ACTIVE', hasTasks: true,
    totalEligibleTasks: 3, completedTasks: 0, progressPercent: 0,
    outstandingTaskCount: 3, overdueTaskCount: 1, timezoneIdUsed: 'Africa/Nairobi'
  };
  const afterMutation = projectId === 'project-2' && mutationRequests > 0;
  const completed = projectId === 'project-2'
    ? (afterMutation ? 7 : 6)
    : 4;
  return {
    projectId, projectStatus: projectId === 'project-2' ? 'ON_HOLD' : 'ACTIVE', hasTasks: true,
    totalEligibleTasks: 10, completedTasks: completed, progressPercent: completed * 10,
    outstandingTaskCount: 10 - completed, overdueTaskCount: 2, timezoneIdUsed: 'Africa/Nairobi'
  };
}

try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  page = await context.newPage();
  page.setDefaultTimeout(10000);
  page.setDefaultNavigationTimeout(30000);
  await page.addInitScript(() => {
    localStorage.setItem('taskflow.accessToken', 'smoke-access');
    localStorage.setItem('taskflow.refreshToken', 'smoke-refresh');
    localStorage.setItem('taskflow.userId', 'user-1');
    localStorage.setItem('taskflow.organizationId', 'org-1');
    localStorage.setItem('taskflow.projectId', 'project-1');
  });

  await page.route('**/api/v1/**', async route => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^.*\/api\/v1/, '');
    if (path === '/account') return route.fulfill({ json: { id: 'user-1', firstName: 'Smoke', lastName: 'Member', email: 'smoke@example.invalid', timezone: 'Africa/Nairobi' } });
    if (path === '/admin/dashboard') return route.fulfill({ status: 403, json: { message: 'Not a platform administrator.' } });
    if (path === '/organizations') return route.fulfill({ json: [{ id: 'org-1', name: 'Smoke Workspace', slug: 'smoke', role: 'MEMBER' }] });
    if (path === '/organizations/org-1/members') return route.fulfill({ json: [] });
    if (path === '/notifications') return route.fulfill({ json: [] });
    if (path === '/activity') return route.fulfill({ json: { items: [], nextCursor: null } });
    if (path === '/projects') {
      for (const item of projectStates) {
        if (item.id === 'project-1') item.role = projectStates[0].role;
      }
      return route.fulfill({ json: accessibleProjectIds
        ? projectStates.filter(item => accessibleProjectIds.includes(item.id))
        : projectStates });
    }
    if (/^\/projects\/[^/]+\/members$/.test(path)) return route.fulfill({ json: [] });
    if (path === '/dashboard/metrics') return route.fulfill({ json: { myTasks: 1, overdueTasks: 0, completedTasks: 0, inProgressTasks: 0, totalTasks: 1 } });
    if (/^\/projects\/[^/]+\/tasks$/.test(path) && request.method() === 'POST') {
      mutationRequests++;
      return route.fulfill({ status: 201, json: { id: 'created-task' } });
    }
    if (path === '/tasks' && request.method() === 'GET') {
      const projectId = url.searchParams.get('projectId');
      const rows = tasks.filter(task => task.projectId === projectId);
      if (projectId === 'project-2' && mutationRequests > 0) rows.push({ id: 'created-task', projectId, title: 'Progress refresh task', status: 'TO DO', priority: 'MEDIUM', assigneeIds: ['user-1'] });
      return route.fulfill({ json: { data: rows } });
    }
    if (/^\/projects\/[^/]+\/progress$/.test(path)) {
      progressRequests++;
      if (progressMode === 'error') return route.fulfill({ status: 503, json: { message: 'Progress service unavailable.' } });
      const projectId = url.pathname.split('/')[4];
      if (accessibleProjectIds && !accessibleProjectIds.includes(projectId)) {
        return route.fulfill({ status: 403, json: { message: 'Project access denied.' } });
      }
      if (projectId === 'project-1' && delayProjectOneProgress) {
        delayedProjectOneProgressStarted = true;
        await new Promise(resolve => { releaseDelayedProjectOneProgress = resolve; });
      }
      if (projectId === 'project-2' && delayProjectTwoProgress) {
        delayProjectTwoProgress = false;
        delayedProjectTwoProgressStarted = true;
        await new Promise(resolve => { releaseDelayedProjectTwoProgress = resolve; });
      }
      return route.fulfill({ json: progress(projectId) });
    }
    if (/^\/tasks\/[^/]+$/.test(path) && request.method() === 'PATCH') {
      assert.equal(request.postDataJSON().status, 'DONE', 'API writes keep the stored status value.');
      return route.fulfill({ status: 204 });
    }
    return route.fulfill({ json: [] });
  });

  await page.goto('http://127.0.0.1:5173/', { waitUntil: 'domcontentloaded' });
  await page.getByRole('heading', { name: 'Project health' }).waitFor();
  await page.getByText('40%').waitFor();
  for (const label of ['Total tasks: 10', 'Open: 6', 'Overdue: 2', 'Completed: 4']) {
    assert.equal(await page.getByRole('button', { name: label }).count(), 1, label);
  }
  assert.equal(await page.getByText('4 of 10 tasks complete').count(), 1, await page.locator('body').innerText());
  assert.equal(await page.locator('.dashboard-health-meta').getByText('Overdue 2').count(), 1);
  const initialProgressRequests = progressRequests;

  // Contributor sees only their assigned task rows, but the project aggregate remains project-wide.
  projectStates[0].role = 'CONTRIBUTOR';
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.getByText('40%').waitFor();
  assert.equal(await page.getByText('4 of 10 tasks complete').count(), 1, await page.locator('body').innerText());
  assert.equal(await page.getByText('My tasks').count(), 1);
  assert.equal(await page.getByRole('button', { name: 'My tasks: 1. View matching tasks' }).count(), 1);
  assert.equal(await page.getByRole('button', { name: 'My overdue: 0. View matching tasks' }).count(), 1);

  // Empty and numeric-zero projects remain distinct.
  progressMode = 'empty';
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.getByText('No tasks', { exact: true }).waitFor();
  assert.equal(await page.getByText('0%', { exact: true }).count(), 0);
  progressMode = 'zero';
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.getByText('0%', { exact: true }).waitFor();
  assert.equal(await page.getByText('No tasks', { exact: true }).count(), 0);

  // Older/unavailable API never falls back to client-calculated progress; retry recovers.
  progressMode = 'error';
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.getByRole('alert').getByText(/Project progress is unavailable/).waitFor();
  assert.equal(await page.getByText('40%').count(), 0);
  progressMode = 'normal';
  await page.getByRole('button', { name: 'Retry' }).click();
  await page.getByText('40%').waitFor();

  // A delayed response from the previous project cannot replace the selected project's aggregate.
  delayProjectOneProgress = true;
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  for (let attempt = 0; attempt < 50 && !delayedProjectOneProgressStarted; attempt++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(delayedProjectOneProgressStarted, true, 'The delayed prior-project request started.');
  await page.getByRole('button', { name: /Smoke Member/ }).click();
  await page.getByLabel('Project', { exact: true }).selectOption('project-2');
  await page.getByText('On Hold', { exact: true }).waitFor();
  await page.getByText('60%').waitFor();
  releaseDelayedProjectOneProgress();
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(await page.getByText('On Hold', { exact: true }).count(), 1);
  assert.equal(await page.getByText('60%').count(), 1);
  delayProjectOneProgress = false;
  assert.ok(progressRequests > initialProgressRequests, 'The progress endpoint is refetched on project changes and retry.');

  // Approved task-board labels are presentation-only; stored values stay in the PATCH body.
  await page.locator('.sidebar').getByRole('button', { name: 'Board', exact: true }).click();
  await page.getByRole('heading', { name: 'To Do', exact: true }).waitFor();
  await page.getByRole('heading', { name: 'In Progress', exact: true }).waitFor();
  await page.getByRole('heading', { name: 'In Review', exact: true }).waitFor();
  await page.getByRole('heading', { name: 'Done', exact: true }).waitFor();
  await page.getByRole('button', { name: 'New task', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Task title').fill('Progress refresh task');
  const progressAfterCreate = page.waitForResponse(response => response.url().includes('/projects/project-2/progress'));
  await dialog.getByRole('button', { name: 'Create task', exact: true }).click();
  const createdTask = page.locator('.task-card').filter({ hasText: 'Progress refresh task' });
  await createdTask.waitFor();
  await progressAfterCreate;
  const progressAfterStatus = page.waitForResponse(response => response.url().includes('/projects/project-2/progress'));
  await createdTask.dragTo(page.locator('.column').filter({ has: page.getByRole('heading', { name: 'Done', exact: true }) }));
  await page.waitForResponse(response => response.request().method() === 'PATCH' && response.url().includes('/tasks/created-task'));
  await progressAfterStatus;
  await page.locator('.sidebar').getByRole('button', { name: 'Overview', exact: true }).click();
  await page.getByText('70%', { exact: true }).waitFor();
  assert.equal(await page.getByText('7 of 10 tasks complete').count(), 1);
  const afterMutationCount = progressRequests;
  const focusProgressResponse = page.waitForResponse(response => response.url().includes('/projects/project-2/progress'));
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await focusProgressResponse;
  assert.ok(progressRequests > afterMutationCount, 'Focus refresh refetches authoritative progress.');

  // Losing project access while a response is pending switches projects and discards the late result.
  delayProjectTwoProgress = true;
  delayedProjectTwoProgressStarted = false;
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  for (let attempt = 0; attempt < 50 && !delayedProjectTwoProgressStarted; attempt++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(delayedProjectTwoProgressStarted, true, 'A project-two progress request is pending.');
  accessibleProjectIds = ['project-1'];
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await page.getByText('Progress Alpha', { exact: true }).waitFor();
  await page.locator('.sidebar').getByRole('button', { name: 'Overview', exact: true }).click();
  await page.getByText('40%').waitFor();
  releaseDelayedProjectTwoProgress();
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(await page.getByText('40%', { exact: true }).count(), 1);
  assert.equal(await page.getByText('70%', { exact: true }).count(), 0);

  // Signing out while a response is pending cannot retain or restore workspace progress.
  delayProjectOneProgress = true;
  delayedProjectOneProgressStarted = false;
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  for (let attempt = 0; attempt < 50 && !delayedProjectOneProgressStarted; attempt++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(delayedProjectOneProgressStarted, true, 'A project-one progress request is pending.');
  await page.getByRole('button', { name: 'Log out' }).click();
  await page.locator('.tenant-workspace-shell').waitFor({ state: 'detached' });
  releaseDelayedProjectOneProgress();
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(await page.locator('.tenant-workspace-shell').count(), 0);
  assert.equal(await page.evaluate(() => localStorage.getItem('taskflow.accessToken')), null);
  await context.close();
  console.log('PASS: authoritative progress, personal metrics, empty vs 0%, retry, task refresh, project switching, access loss, sign-out, and status labels.');
} finally {
  await browser.close();
}
