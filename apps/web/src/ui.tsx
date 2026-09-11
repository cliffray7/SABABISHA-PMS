import { FormEvent, ReactNode, useEffect, useRef, useState } from 'react';
import { X } from 'lucide-react';
import { errorMessage } from './api';
export function Brand() { return <div className="brand"><span className="brand-mark">&#9670;</span>TaskFlow</div>; }
export function Empty({ title, children }: { title: string; children?: ReactNode }) { return <div className="empty-state"><h2>{title}</h2>{children}</div>; }
export function useAction() {
  const [busy, setBusy] = useState(false); const [error, setError] = useState('');
  const run = async (work: () => Promise<void>) => { if (busy) return; setBusy(true); setError(''); try { await work(); } catch (e) { setError(errorMessage(e)); } finally { setBusy(false); } };
  return { busy, error, setError, run };
}
export function Feedback({ error }: { error: string }) { return error ? <p className="form-error" role="alert" aria-live="assertive">{error}</p> : null; }
export function Modal({ title, close, children }: { title: string; close: () => void; children: ReactNode }) {
  const panel = useRef<HTMLElement>(null); const closeRef = useRef(close); closeRef.current = close;
  useEffect(() => {
    const before = document.activeElement as HTMLElement; const old = document.body.style.overflow; document.body.style.overflow = 'hidden';
    const focusable = () => Array.from(panel.current?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href]') ?? []);
    focusable()[0]?.focus();
    const key = (event: KeyboardEvent) => { if (event.key === 'Escape') closeRef.current(); if (event.key === 'Tab') { const nodes = focusable(); const first = nodes[0], last = nodes[nodes.length - 1]; if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); } else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); } } };
    document.addEventListener('keydown', key); return () => { document.removeEventListener('keydown', key); document.body.style.overflow = old; before?.focus(); };
  }, []);
  return <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) close(); }}><section ref={panel} className="app-modal" role="dialog" aria-modal="true" aria-label={title}><div className="modal-head"><h2>{title}</h2><button type="button" className="icon-button" onClick={close} aria-label="Close dialog"><X size={20}/></button></div>{children}</section></div>;
}
export function Form({ onSubmit, children, className = '' }: { onSubmit: (data: FormData) => void; children: ReactNode; className?: string }) { return <form className={className} onSubmit={(event: FormEvent<HTMLFormElement>) => { event.preventDefault(); onSubmit(new FormData(event.currentTarget)); }}>{children}</form>; }
export const value = (data: FormData, name: string) => String(data.get(name) ?? '').trim();

