import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { account, cleanup, prefix, password, request, mailToken } from './helpers.mjs';
const web='http://127.0.0.1:5173/';
const browser=await chromium.launch({channel:'msedge',headless:true});
const errors=[]; let page;
try {
  const user=await account('owner');
  const context=await browser.newContext({viewport:{width:1440,height:1000}});
  page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.setDefaultTimeout(30000);page.setDefaultNavigationTimeout(60000);
  await page.goto(web+'#login',{waitUntil:'domcontentloaded'});
  await page.getByLabel('Email address').fill(user.email);await page.getByLabel('Password',{exact:true}).fill(password);await page.getByRole('button',{name:'Log in',exact:true}).click();
  await page.getByRole('heading',{name:'Welcome to TaskFlow',exact:true}).waitFor();
  await page.getByRole('button',{name:'Create organization',exact:true}).click();
  let dialog=page.getByRole('dialog');await dialog.getByLabel('Organization name').fill(prefix);await dialog.getByLabel('Workspace slug').fill(prefix);await dialog.getByRole('button',{name:'Create organization',exact:true}).click();
  await dialog.waitFor({state:'hidden'});await page.getByRole('button',{name:'New project',exact:true}).click();
  dialog=page.getByRole('dialog');await dialog.getByLabel('Project name').fill('Website Redesign');await dialog.getByLabel('Description').fill('Our functional project workspace');await dialog.getByLabel('Start date').fill('2026-09-01');await dialog.getByLabel('Due date').fill('2026-10-20');await dialog.getByLabel('Status',{exact:true}).selectOption('ACTIVE');
  await mkdir('test-results',{recursive:true});await page.screenshot({path:'test-results/create-project.png',fullPage:true});
  await dialog.getByRole('button',{name:'Create project',exact:true}).click();await dialog.waitFor({state:'hidden'});
  await page.getByRole('button',{name:'New task',exact:true}).click();dialog=page.getByRole('dialog');await dialog.getByLabel('Task title').fill('Build the remaining screens');await dialog.getByLabel('Description').fill('Reset password, project modal, and shared controls');await dialog.getByLabel('Due date').fill('2026-10-01');await dialog.getByLabel('owner Smoke').check();await dialog.getByRole('button',{name:'Create task',exact:true}).click();await dialog.waitFor({state:'hidden'});
  await page.locator('.task-title').filter({hasText:'Build the remaining screens'}).waitFor();
  await page.locator('.task-card').filter({hasText:'Build the remaining screens'}).dragTo(page.locator('.column').filter({has:page.getByRole('heading',{name:'DONE',exact:true})}));
  await page.locator('.column').filter({has:page.getByRole('heading',{name:'DONE',exact:true})}).getByText('Build the remaining screens',{exact:true}).waitFor();
  await page.reload();await page.locator('.column').filter({has:page.getByRole('heading',{name:'DONE',exact:true})}).getByText('Build the remaining screens',{exact:true}).waitFor();
  await page.locator('.task-card').filter({hasText:'Build the remaining screens'}).click();dialog=page.getByRole('dialog');await dialog.getByLabel('Add a comment').fill('This is a real saved comment.');await dialog.getByRole('button',{name:'Post comment',exact:true}).click();await dialog.getByText('This is a real saved comment.',{exact:true}).waitFor();
  await page.waitForFunction(() => !document.querySelector('input[type=file]')?.disabled);await dialog.locator('input[type=file]').setInputFiles({name:'design-notes.txt',mimeType:'text/plain',buffer:Buffer.from('Saved attachment from browser test.')});await dialog.getByRole('button',{name:/design-notes.txt/}).waitFor();
  await page.screenshot({path:'test-results/task-details.png',fullPage:true});await dialog.getByLabel('Task title').fill('Remaining screens completed');await dialog.getByRole('button',{name:'Save changes',exact:true}).click();await dialog.waitFor({state:'hidden'});
  await page.getByRole('button',{name:'List',exact:true}).click();await page.locator('.task-list-entry').getByText('Remaining screens completed',{exact:true}).waitFor();
  await page.getByRole('button',{name:'Timeline',exact:true}).click();await page.getByRole('heading',{name:'Project timeline',exact:true}).waitFor();
  await page.getByRole('button',{name:'Dashboard',exact:true}).click();await page.getByText('1 of 1 tasks completed',{exact:false}).waitFor();await page.screenshot({path:'test-results/dashboard.png',fullPage:true});
  await page.locator('.sidebar').getByRole('button',{name:'Settings',exact:true}).click();await page.getByLabel('First name').fill('Clifford');await page.getByRole('button',{name:'Save profile',exact:true}).click();await page.getByText('Profile saved.',{exact:true}).waitFor();
  await page.evaluate(()=>localStorage.setItem('taskflow.accessToken','expired-token'));await page.reload();await page.getByLabel('First name').waitFor();assert.equal(await page.getByLabel('First name').inputValue(),'Clifford');assert.notEqual(await page.evaluate(()=>localStorage.getItem('taskflow.accessToken')),'expired-token');
  await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:'Toggle navigation'}).click();await page.locator('.sidebar').getByRole('button',{name:'Board',exact:true}).click();await page.getByRole('button',{name:'Board',exact:true}).last().click();await page.screenshot({path:'test-results/mobile-board.png',fullPage:true});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Mobile layout must fit the viewport');
  await page.setViewportSize({width:1440,height:1000});await page.locator('.sidebar').getByRole('button',{name:'Log out',exact:true}).click();await page.getByRole('heading',{name:'Welcome back',exact:true}).waitFor();
  await page.getByRole('button',{name:'Forgot password?',exact:true}).click();await page.getByLabel('Email address').fill(user.email);await page.getByRole('button',{name:'Send reset link',exact:true}).click();await page.getByText('If an account exists for that email, a reset link has been sent.',{exact:true}).waitFor();
  const token=await mailToken(user.email,'Reset');await page.goto(web+'#reset?token='+encodeURIComponent(token));await page.getByLabel('New password',{exact:true}).fill(password+'new');await page.getByLabel('Confirm new password',{exact:true}).fill('mismatch1');await page.getByRole('button',{name:'Reset password',exact:true}).click();await page.getByText('Passwords do not match.',{exact:true}).waitFor();await page.getByLabel('Confirm new password',{exact:true}).fill(password+'new');await page.screenshot({path:'test-results/reset-password.png',fullPage:true});await page.getByRole('button',{name:'Reset password',exact:true}).click();await page.getByText('Password updated. Log in with your new password.',{exact:true}).waitFor();
  assert.deepEqual(errors,[],'No browser runtime errors');console.log('PASS: browser login, onboarding, create project, create/edit/drag tasks, reload persistence, comments, upload, dashboard, list/timeline, settings, token renewal, mobile layout, logout, and password reset.');
} catch (error) { if (page) { await mkdir("test-results",{recursive:true}); await page.screenshot({path:"test-results/failure.png",fullPage:true}); console.log((await page.locator("body").innerText()).slice(0,5000)); } throw error; } finally { await browser.close();cleanup(); }



