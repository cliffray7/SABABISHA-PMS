import { useEffect, useRef, useState } from 'react';
import { api, AuthResponse, clearAuth, Mail, saveAuth } from './api';
import { Brand, Feedback, Form, useAction, value } from './ui';

const OTP_SECONDS = 600; // 10 minutes

function OtpInput({ onComplete, busy }: { onComplete: (code: string) => void; busy: boolean }) {
  const [digits, setDigits] = useState(['', '', '', '', '', '']);
  const refs = [useRef<HTMLInputElement>(null), useRef<HTMLInputElement>(null), useRef<HTMLInputElement>(null), useRef<HTMLInputElement>(null), useRef<HTMLInputElement>(null), useRef<HTMLInputElement>(null)];

  const update = (i: number, val: string) => {
    const d = val.replace(/\D/g, '').slice(-1);
    const next = [...digits];
    next[i] = d;
    setDigits(next);
    if (d && i < 5) refs[i + 1].current?.focus();
    const code = next.join('');
    if (code.length === 6 && next.every(c => c !== '')) onComplete(code);
  };

  const onKey = (i: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !digits[i] && i > 0) refs[i - 1].current?.focus();
  };

  const onPaste = (e: React.ClipboardEvent) => {
    const pasted = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6);
    if (!pasted) return;
    e.preventDefault();
    const next = pasted.split('').concat(Array(6).fill('')).slice(0, 6);
    setDigits(next);
    refs[Math.min(pasted.length, 5)].current?.focus();
    if (pasted.length === 6) onComplete(pasted);
  };

  useEffect(() => { refs[0].current?.focus(); }, []);

  return (
    <div style={{ display: 'flex', gap: 8, justifyContent: 'center', margin: '16px 0' }}>
      {digits.map((d, i) => (
        <input
          key={i}
          ref={refs[i]}
          value={d}
          disabled={busy}
          inputMode="numeric"
          autoComplete={i === 0 ? 'one-time-code' : 'off'}
          maxLength={1}
          onChange={e => update(i, e.target.value)}
          onKeyDown={e => onKey(i, e)}
          onPaste={onPaste}
          style={{
            width: 44, height: 52, textAlign: 'center', fontSize: 22,
            fontWeight: 700, borderRadius: 8, border: '1px solid var(--line)',
            background: 'var(--panel)', color: 'var(--ink)',
            outline: 'none', transition: 'border-color .15s',
          }}
          onFocus={e => (e.target.style.borderColor = 'var(--violet)')}
          onBlur={e => (e.target.style.borderColor = 'var(--line)')}
        />
      ))}
    </div>
  );
}

function OtpCountdown({ seconds, onResend, busy, email }: { seconds: number; onResend: () => void; busy: boolean; email: string }) {
  const mins = String(Math.floor(seconds / 60)).padStart(2, '0');
  const secs = String(seconds % 60).padStart(2, '0');
  const expired = seconds === 0;
  return (
    <div style={{ textAlign: 'center', margin: '8px 0 4px' }}>
      {expired
        ? <p className="muted" style={{ margin: '0 0 8px', fontSize: 13 }}>Code expired.</p>
        : <p className="muted" style={{ margin: '0 0 8px', fontSize: 13 }}>
            Code expires in <strong style={{ color: seconds < 60 ? '#da3038' : 'var(--ink)' }}>{mins}:{secs}</strong>
          </p>
      }
      <button
        type="button"
        className="link-button"
        disabled={!expired && seconds > 0 || busy}
        onClick={onResend}
        style={{ fontSize: 13 }}
      >
        {busy ? 'Sending…' : expired ? 'Send new code' : `Resend code`}
      </button>
    </div>
  );
}

export function Auth({ route, navigate, onLogin, localMail }: { route: string; navigate: (route: string) => void; onLogin: () => void; localMail: boolean }) {
  const mode = route.split('?')[0]; const register = mode === 'register', reset = mode === 'reset', forgot = mode === 'forgot', otp = mode === 'otp';
  const otpEmail = new URLSearchParams(route.split('?')[1]).get('email') ?? '';
  const action = useAction(); const [message, setMessage] = useState('');
  const [otpSeconds, setOtpSeconds] = useState(OTP_SECONDS);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Start countdown when OTP screen mounts
  useEffect(() => {
    if (!otp) return;
    setOtpSeconds(OTP_SECONDS);
    timerRef.current = setInterval(() => {
      setOtpSeconds(s => (s > 0 ? s - 1 : 0));
    }, 1000);
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [otp]);

  const submitOtp = async (code: string) => {
    await action.run(async () => {
      const response = await api.post<AuthResponse>('/auth/verify-otp', { email: otpEmail, code });
      saveAuth(response.data);
      if (timerRef.current) clearInterval(timerRef.current);
      onLogin();
    });
  };

  const resendOtp = () => void action.run(async () => {
    // Re-trigger OTP by hitting the stored credentials is not available here,
    // so we navigate back to login with the email pre-noted via a page reload.
    // The simplest safe approach: call forgot-password is wrong; instead we
    // navigate to login so user re-submits — but we can do better by keeping
    // a resend endpoint. The backend re-sends on POST /auth/login with valid creds.
    // Since we don't store the password here, navigate to login with email hint.
    navigate(`login?email=${encodeURIComponent(otpEmail)}`);
  });

  return <main className="auth-page"><div className="auth-card"><Brand/><h1>{register ? 'Create your account' : reset ? 'Set a new password' : forgot ? 'Forgot your password?' : otp ? 'Verify your email' : 'Welcome back'}</h1><p className="auth-lede">{reset ? "Choose a strong password you haven't used before." : forgot ? "Enter your email and we'll send you a reset link." : register ? 'Start managing projects with your team.' : otp ? `Enter the six-digit code sent to ${otpEmail}.` : 'Log in to your workspace to continue.'}</p>
    {message ? <><p className="success-message" role="status">{message}</p><button className="primary wide" onClick={() => navigate('login')}>Back to log in</button></> : otp ? <>
      <OtpInput busy={action.busy} onComplete={submitOtp} />
      <OtpCountdown seconds={otpSeconds} busy={action.busy} email={otpEmail} onResend={resendOtp} />
      <Feedback error={action.error}/>
      {action.busy && <p className="muted" style={{ textAlign: 'center', fontSize: 13 }}>Verifying…</p>}
      <div className="auth-links"><button className="link-button" onClick={() => navigate('login')}>Back to log in</button></div>
    </> : <Form onSubmit={data => void action.run(async () => {
      const password = value(data, 'password');
      if (reset) { if (password !== value(data, 'confirm')) throw new Error('Passwords do not match.'); const token = new URLSearchParams(route.split('?')[1]).get('token'); if (!token) throw new Error('This reset link is missing its token. Request a new link.'); await api.post('/auth/reset-password', { token, password }); clearAuth(); setMessage('Password updated. Log in with your new password.'); }
      else if (forgot) { const response = await api.post('/auth/forgot-password', { email: value(data, 'email') }); setMessage(response.data.message); }
      else { const body = { email: value(data, 'email'), password, firstName: value(data, 'firstName'), lastName: value(data, 'lastName') }; const response = await api.post<AuthResponse | { requiresOtp: boolean; email: string }>('/auth/' + (register ? 'register' : 'login'), body); if ('requiresOtp' in response.data) navigate(`otp?email=${encodeURIComponent(response.data.email)}`); else { saveAuth(response.data as AuthResponse); onLogin(); } }
    })}>
      {register && <div className="two-col"><label>First name<input name="firstName" autoComplete="given-name" required maxLength={100}/></label><label>Last name<input name="lastName" autoComplete="family-name" required maxLength={100}/></label></div>}
      {!reset && <label>Email address<input name="email" type="email" autoComplete="email" placeholder="you@company.com" required defaultValue={new URLSearchParams(route.split('?')[1]).get('email') ?? ''}/></label>}
      {!forgot && <label>{reset ? 'New password' : 'Password'}<input aria-label={reset ? 'New password' : 'Password'} name="password" type="password" autoComplete={register || reset ? 'new-password' : 'current-password'} required minLength={register || reset ? 8 : undefined} maxLength={128}/>{(register || reset) && <small>Minimum 8 characters</small>}</label>}
      {reset && <label>Confirm new password<input name="confirm" type="password" autoComplete="new-password" minLength={8} required/></label>}
      <Feedback error={action.error}/><button className="primary wide" disabled={action.busy}>{action.busy ? 'Please wait…' : register ? 'Create account' : reset ? 'Reset password' : forgot ? 'Send reset link' : 'Log in'}</button>
    </Form>}
    {!message && !otp && <div className="auth-links">{!forgot && !reset && <p>{register ? 'Already have an account?' : "Don't have an account?"} <button className="link-button" onClick={() => navigate(register ? 'login' : 'register')}>{register ? 'Log in' : 'Sign up'}</button></p>}{!register && !forgot && !reset && <button className="link-button" onClick={() => navigate('forgot')}>Forgot password?</button>}{(reset || forgot) && <button className="link-button" onClick={() => navigate('login')}>Back to log in</button>}</div>}
    {localMail && <button className="dev-inbox-link" onClick={() => navigate('inbox')}>Open development inbox</button>}
  </div></main>;
}
export function Inbox({ navigate }: { navigate: (route: string) => void }) {
  const [messages, setMessages] = useState<Mail[]>([]); const action = useAction();
  const refresh = () => void action.run(async () => { setMessages((await api.get<Mail[]>('/dev/inbox')).data); });
  useEffect(refresh, []);
  return <main className="inbox-page"><Brand/><div className="page-heading"><div><h1>Development inbox</h1><p className="muted">Local preview of password-reset, invitation, and verification emails. These messages are not sent externally.</p></div><button className="secondary" onClick={refresh} disabled={action.busy}>Refresh</button></div><Feedback error={action.error}/>{messages.length === 0 && <p>No messages yet. Request a password reset, invitation, or verification code.</p>}{messages.map(m => <article className="list-panel" key={m.id}><small>To: {m.to} · {new Date(m.createdAt).toLocaleString()}</small><h2>{m.subject}</h2>{m.body && <p>{m.body}</p>}<button className="primary" onClick={() => { const hash = new URL(m.link).hash.slice(1); navigate(hash); }}>Open {m.subject.startsWith('Reset') ? 'reset' : m.subject.includes('verification code') ? 'verification' : 'invitation'} link</button></article>)}<button className="text-button" onClick={() => navigate('dashboard')}>Back to TaskFlow</button></main>;
}



