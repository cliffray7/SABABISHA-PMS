import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
export const base = process.env.TEST_API_URL || 'http://localhost:5141/api/v1';
export const prefix = 'smoke-' + randomUUID().replaceAll('-','');
export const password = randomUUID() + '!Aa9';
export async function request(path, { token, body, method = body ? 'POST' : 'GET', status = 200 } = {}) {
  const response = await fetch(base+path, { method, headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body && !(body instanceof FormData)?{'Content-Type':'application/json'}:{})}, body:body ? body instanceof FormData?body:JSON.stringify(body):undefined });
  assert.equal(response.status,status,`${method} ${path}: expected ${status}, got ${response.status}`);
  if (response.status===204 || status>=400) return null;
  return response.json();
}
export async function account(name) { const email=prefix+'-'+name+'@example.invalid'; const challenge=await request('/auth/register',{body:{firstName:name,lastName:'Smoke',email,password}}); assert.equal(challenge.requiresOtp,true); assert.equal(challenge.accessToken,undefined); assert.equal(challenge.refreshToken,undefined); const auth=await request('/auth/verify-otp',{body:{email,code:await mailOtp(email)}}); return {...auth,email}; }
export async function mailToken(email, subject) { const inbox=await request('/dev/inbox'); const message=inbox.find(m=>m.to===email&&m.subject.startsWith(subject)); assert.ok(message,'Expected local email'); return new URLSearchParams(new URL(message.link).hash.split('?')[1]).get('token'); }
export async function mailOtp(email) { const inbox=await request('/dev/inbox'); const message=inbox.find(m=>m.to===email&&m.subject.startsWith('Your TaskFlow verification code')); assert.ok(message,'Expected local verification email'); const code=message.body?.match(/\b\d{6}\b/)?.[0]; assert.ok(code,'Expected a six-digit verification code'); return code; }
export function cleanup() { const script=fileURLToPath(new URL('../../../scripts/cleanup-smoke.ps1',import.meta.url)); execFileSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',script,'-TestPrefix',prefix],{stdio:'inherit'}); }
