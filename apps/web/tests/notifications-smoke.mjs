import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';
import { account,request,cleanup,prefix,password } from './helpers.mjs';
const browser=await chromium.launch({channel:'msedge',headless:true});
try {
 const user=await account('recipient'),other=await account('other');const token=user.accessToken;
 const org=await request('/organizations',{token,body:{name:prefix,slug:prefix}});
 const project=await request('/projects',{token,body:{organizationId:org.id,name:'Notification checks',status:'ACTIVE'}});
 const page=await browser.newPage();page.setDefaultTimeout(30000);const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:5173/#login',{waitUntil:'domcontentloaded'});
 await page.getByLabel('Email address').fill(user.email);await page.getByLabel('Password',{exact:true}).fill(password);await page.getByRole('button',{name:'Log in',exact:true}).click();await page.getByRole('heading',{name:'Notification checks',exact:true}).waitFor();
 assert.equal(await page.locator('.unread-dot').count(),0);
 // Create from another client after the recipient page has finished loading.
 await request(`/projects/${project.id}/tasks`,{token,body:{title:'Arrived without reload',status:'TO DO',priority:'LOW',assigneeIds:[user.userId]}});
 await page.locator('.unread-dot').waitFor({timeout:20000});
 await page.locator('.notification-button').click();await page.locator('.notification-panel').getByText('You were assigned to Arrived without reload.',{exact:true}).waitFor();
 await page.locator('.notification-panel').getByRole('button',{name:'Mark all read',exact:true}).click();await page.locator('.unread-dot').waitFor({state:'hidden'});
 await page.waitForTimeout(11000);assert.equal(await page.locator('.unread-dot').count(),0,'Polling must not restore read notifications');
 await request(`/projects/${project.id}/tasks`,{token,body:{title:'Refresh on bell open',status:'TO DO',priority:'LOW',assigneeIds:[user.userId]}});
 await page.locator('.notification-button').click();await page.locator('.notification-button').click();await page.locator('.notification-panel').getByText('You were assigned to Refresh on bell open.',{exact:true}).waitFor();
 await page.locator('.sidebar').getByRole('button',{name:'Notifications',exact:true}).click();await page.locator('.notifications-page').getByText('You were assigned to Refresh on bell open.',{exact:true}).waitFor();
 await page.locator('.sidebar').getByRole('button',{name:'Log out',exact:true}).click();await page.getByRole('heading',{name:'Welcome back',exact:true}).waitFor();await page.getByLabel('Email address').fill(other.email);await page.getByLabel('Password',{exact:true}).fill(password);await page.getByRole('button',{name:'Log in',exact:true}).click();await page.getByRole('heading',{name:'Welcome to TaskFlow',exact:true}).waitFor();await page.locator('.notification-button').click();await page.getByText("You're all caught up.",{exact:true}).waitFor();assert.equal(await page.getByText('You were assigned to Arrived without reload.',{exact:true}).count(),0);
 assert.deepEqual(errors,[]);console.log('PASS: automatic notification polling, bell-open refresh, read-state persistence, notifications page, and account isolation.');
}finally{await browser.close();cleanup();}
