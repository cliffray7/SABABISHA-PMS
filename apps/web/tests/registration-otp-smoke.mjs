import assert from 'node:assert/strict';
import { request, mailOtp, cleanup, prefix, password } from './helpers.mjs';

try {
  const email = `${prefix}-registration@example.invalid`;
  const challenge = await request('/auth/register', { body: { firstName: 'OTP', lastName: 'Smoke', email, password } });
  assert.equal(challenge.requiresOtp, true, 'Registration must require OTP');
  assert.equal(challenge.email, email);
  assert.equal('accessToken' in challenge, false, 'Registration must not issue an access token');
  assert.equal('refreshToken' in challenge, false, 'Registration must not issue a refresh token');
  await request('/account', { status: 401 });
  const code = await mailOtp(email);
  const wrong = code === '000000' ? '111111' : '000000';
  for (let attempt = 0; attempt < 5; attempt++) {
    await request('/auth/verify-otp', { body: { email, code: wrong }, status: 400 });
  }
  await request('/auth/verify-otp', { body: { email, code }, status: 400 });
  assert.equal((await request('/auth/login', { body: { email, password } })).requiresOtp, true);
  const freshCode = await mailOtp(email);
  const auth = await request('/auth/verify-otp', { body: { email, code: freshCode } });
  assert.ok(auth.accessToken);
  assert.ok(auth.refreshToken);
  assert.equal((await request('/account', { token: auth.accessToken })).email, email);
  await request('/auth/verify-otp', { body: { email, code: freshCode }, status: 400 });
  console.log('PASS: registration requires OTP, five failed attempts lock the code, login recovers verification, and codes are single-use.');
} finally { cleanup(); }
