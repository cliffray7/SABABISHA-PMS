import { useEffect, useState } from 'react';
import { api, AuthResponse, clearAuth, Mail, saveAuth } from './api';
import { Brand, Feedback, Form, useAction, value } from './ui';
export function Auth({ route, navigate, onLogin, localMail }: { route: string; navigate: (route: string) => void; onLogin: () => void; localMail: boolean }) {
  const mode = route.split('?')[0]; const register = mode === 'register', reset = mode === 'reset', forgot = mode === 'forgot', otp = mode === 'otp';
  const otpEmail = new URLSearchParams(route.split('?')[1]).get('email') ?? '';
  const action = useAction(); const [message, setMessage] = useState('');
  return <main className="auth-page"><div className="auth-card"><Brand/><h1>{register ? 'Create your account' : reset ? 'Set a new password' : forgot ? 'Forgot your password?' : otp ? 'Verify your sign-in' : 'Welcome back'}</h1><p className="auth-lede">{reset ? "Choose a strong password you haven't used before." : forgot ? "Enter your email and we'll send you a reset link." : register ? 'Start managing projects with your team.' : otp ? `Enter the six-digit code sent to ${otpEmail}.` : 'Log in to your workspace to continue.'}</p>
    {message ? <><p className="success-message" role="status">{message}</p><button className="primary wide" onClick={() => navigate('login')}>Back to log in</button></> : <Form onSubmit={data => void action.run(async () => {
      const password = value(data, 'password');
      if (reset) { if (password !== value(data, 'confirm')) throw new Error('Passwords do not match.'); const token = new URLSearchParams(route.split('?')[1]).get('token'); if (!token) throw new Error('This reset link is missing its token. Request a new link.'); await api.post('/auth/reset-password', { token, password }); clearAuth(); setMessage('Password updated. Log in with your new password.'); }
      else if (forgot) { const response = await api.post('/auth/forgot-password', { email: value(data, 'email') }); setMessage(response.data.message); }
      else if (otp) { const response = await api.post<AuthResponse>('/auth/verify-otp', { email: otpEmail, code: value(data, 'code') }); saveAuth(response.data); onLogin(); }
      else { const body = { email: value(data, 'email'), password, firstName: value(data, 'firstName'), lastName: value(data, 'lastName') }; const response = await api.post<AuthResponse | { requiresOtp: boolean; email: string }>('/auth/' + (register ? 'register' : 'login'), body); if (!register && 'requiresOtp' in response.data) navigate(`otp?email=${encodeURIComponent(response.data.email)}`); else { saveAuth(response.data as AuthResponse); onLogin(); } }
    })}>
      {register && <div className="two-col"><label>First name<input name="firstName" autoComplete="given-name" required maxLength={100}/></label><label>Last name<input name="lastName" autoComplete="family-name" required maxLength={100}/></label></div>}
      {!reset && !otp && <label>Email address<input name="email" type="email" autoComplete="email" placeholder="you@company.com" required/></label>}
      {!forgot && !otp && <label>{reset ? 'New password' : 'Password'}<input aria-label={reset ? 'New password' : 'Password'} name="password" type="password" autoComplete={register || reset ? 'new-password' : 'current-password'} required minLength={register || reset ? 8 : undefined} maxLength={128}/>{(register || reset) && <small>Minimum 8 characters</small>}</label>}
      {otp && <label>Verification code<input name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" minLength={6} maxLength={6} required placeholder="123456"/><small>The code expires in 10 minutes. You have five attempts.</small></label>}
      {reset && <label>Confirm new password<input name="confirm" type="password" autoComplete="new-password" minLength={8} required/></label>}
      <Feedback error={action.error}/><button className="primary wide" disabled={action.busy}>{action.busy ? 'Please wait…' : register ? 'Create account' : reset ? 'Reset password' : forgot ? 'Send reset link' : otp ? 'Verify code' : 'Log in'}</button>
    </Form>}
    {!message && <div className="auth-links">{!forgot && !reset && !otp && <p>{register ? 'Already have an account?' : "Don't have an account?"} <button className="link-button" onClick={() => navigate(register ? 'login' : 'register')}>{register ? 'Log in' : 'Sign up'}</button></p>}{!register && !forgot && !reset && !otp && <button className="link-button" onClick={() => navigate('forgot')}>Forgot password?</button>}{(reset || forgot || otp) && <button className="link-button" onClick={() => navigate('login')}>Back to log in</button>}</div>}
    {localMail && <button className="dev-inbox-link" onClick={() => navigate('inbox')}>Open development inbox</button>}
  </div></main>;
}
export function Inbox({ navigate }: { navigate: (route: string) => void }) {
  const [messages, setMessages] = useState<Mail[]>([]); const action = useAction();
  const refresh = () => void action.run(async () => { setMessages((await api.get<Mail[]>('/dev/inbox')).data); });
  useEffect(refresh, []);
  return <main className="inbox-page"><Brand/><div className="page-heading"><div><h1>Development inbox</h1><p className="muted">Local preview of password-reset, invitation, and verification emails. These messages are not sent externally.</p></div><button className="secondary" onClick={refresh} disabled={action.busy}>Refresh</button></div><Feedback error={action.error}/>{messages.length === 0 && <p>No messages yet. Request a password reset, invitation, or verification code.</p>}{messages.map(m => <article className="list-panel" key={m.id}><small>To: {m.to} · {new Date(m.createdAt).toLocaleString()}</small><h2>{m.subject}</h2>{m.body && <p>{m.body}</p>}<button className="primary" onClick={() => { const hash = new URL(m.link).hash.slice(1); navigate(hash); }}>Open {m.subject.startsWith('Reset') ? 'reset' : m.subject.startsWith('verification') ? 'verification' : 'invitation'} link</button></article>)}<button className="text-button" onClick={() => navigate('dashboard')}>Back to TaskFlow</button></main>;
}



