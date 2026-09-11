import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';
import { account,request,mailToken,cleanup,prefix,password,base } from './helpers.mjs';
assert.equal((await request('/auth/mail-mode')).local,true,'Run this test against a development-inbox API; never send test invitations through SMTP.');
const browser=await chromium.launch({channel:'msedge',headless:true});
try {
 const owner=await account('owner'),uploader=await account('uploader'),assignee=await account('assignee'),viewer=await account('viewer');const token=owner.accessToken;
 const org=await request('/organizations',{token,body:{name:prefix,slug:prefix}});
 const project=await request('/projects',{token,body:{organizationId:org.id,name:'Shared attachments',status:'ACTIVE'}});
 for(const user of [uploader,assignee,viewer]){
   await request(`/organizations/${org.id}/invitations`,{token,body:{email:user.email,role:'MEMBER'}});
   await request('/organizations/invitations/accept',{token:user.accessToken,body:{token:await mailToken(user.email,'Join')}});
   await request(`/projects/${project.id}/members`,{token,body:{userId:user.userId,role:user===viewer?'VIEWER':'CONTRIBUTOR'},status:204});
 }
 const task=await request(`/projects/${project.id}/tasks`,{token,body:{title:'Review attachment',status:'TO DO',priority:'LOW',assigneeIds:[owner.userId,uploader.userId,assignee.userId]}});
 const users=[owner,uploader,assignee,viewer];const baseline=new Map();
 for(const user of users)baseline.set(user.userId,(await request('/notifications',{token:user.accessToken})).map(n=>n.id));
 await request('/notifications/read-all',{token,method:'PATCH',status:204});
 const page=await browser.newPage();page.setDefaultTimeout(30000);
 await page.route('http://localhost:5141/api/v1/**',route=>route.continue({url:route.request().url().replace('http://localhost:5141/api/v1',base)}));
 await page.goto('http://127.0.0.1:5173/#login',{waitUntil:'domcontentloaded'});await page.getByLabel('Email address').fill(owner.email);await page.getByLabel('Password',{exact:true}).fill(password);await page.getByRole('button',{name:'Log in',exact:true}).click();await page.getByRole('heading',{name:'Shared attachments',exact:true}).waitFor();
 function file(contents='File shared with teammates'){const data=new FormData();data.append('file',new Blob([contents],{type:'text/plain'}),'shared-file.txt');return data;}
 await request(`/tasks/${task.id}/attachments`,{token:viewer.accessToken,body:file(),status:404});
 await request(`/tasks/${task.id}/attachments`,{token:uploader.accessToken,body:file(''),status:400});
 for(const user of users)assert.deepEqual((await request('/notifications',{token:user.accessToken})).map(n=>n.id),baseline.get(user.userId),'Rejected uploads must notify nobody');
 const attachment=await request(`/tasks/${task.id}/attachments`,{token:uploader.accessToken,body:file()});
 for(const user of users){const received=(await request('/notifications',{token:user.accessToken})).filter(n=>!baseline.get(user.userId).includes(n.id));assert.equal(received.length,user===owner||user===assignee?1:0,'Notify creator and assignees once, excluding uploader and unassigned members');if(received.length){assert.equal(received[0].relatedId,task.id);assert.equal(received[0].projectId,project.id);}}
 await page.locator('.unread-dot').waitFor({timeout:20000});await page.locator('.notification-button').click();await page.locator('.notification-panel').getByRole('button',{name:/A file was attached to Review attachment/}).click();await page.getByRole('dialog').getByRole('button',{name:/shared-file.txt/}).waitFor();
 const download=await fetch(`${base}/attachments/${attachment.id}/download`,{headers:{Authorization:'Bearer '+assignee.accessToken}});assert.equal(download.status,200);assert.equal(await download.text(),'File shared with teammates');
 console.log('PASS: attachment notifications reach creator and assignees once, exclude uploader/unassigned members, ignore rejected uploads, update the bell automatically, open the task, and allow authorized download.');
}finally{await browser.close();cleanup();}
