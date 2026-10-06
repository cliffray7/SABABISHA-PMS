import { useEffect } from 'react';
import { ArrowRight, Play, Sun, Moon } from 'lucide-react';
import './landing.css';
import './landing-v3.css';

type ColorMode = 'light' | 'dark';

type LandingPageProps = {
  navigate: (route: string) => void;
  mode: ColorMode;
  toggleTheme: () => void;
};

const steps = [
  ['1', 'Create a project', 'Name it, set a due date, and add your team.'],
  ['2', 'Assign tasks', 'Break work into tasks and give each one an owner.'],
  ['3', 'Track progress', 'See each task move from To do to In progress to Done.'],
  ['4', 'Review the work', 'Check what is complete and what still needs attention.'],
];

const audiences = [
  ['For contributors', 'Team members', 'Open assigned tasks, update status, and share progress.'],
  ['For delivery', 'Project leads', 'Set up projects, assign tasks, and review progress.'],
  ['For the workspace', 'Organization admins', 'Manage members, projects, and roles.'],
];

const promises = [
  ['Access by role', 'Workspace and project roles determine who can view and manage work.'],
  ['Organization workspaces', 'Keep projects and members within your organization.'],
  ['AI stays assistive', 'Suggestions remain drafts until you choose to use them.'],
];

const questions = [
  ['How do I get started?', 'Create an account, set up a workspace, then add a project and its tasks.'],
  ['How do I add my team?', 'Invite members to your organization and assign their workspace roles.'],
  ['What does AI help with?', 'It drafts task titles and subtasks from your description. Review the draft before using it.'],
  ['Who can access a project?', 'Project access is limited to members of its organization and follows their assigned roles.'],
];

export default function LandingPage({ navigate, mode, toggleTheme }: LandingPageProps) {
  useEffect(() => {
    const targets = Array.from(document.querySelectorAll<HTMLElement>('[data-scroll-reveal]'));
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (reducedMotion || !('IntersectionObserver' in window)) {
      targets.forEach(target => target.classList.add('is-visible'));
      return;
    }

    const observer = new IntersectionObserver((entries, activeObserver) => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        activeObserver.unobserve(entry.target);
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });

    targets.forEach(target => observer.observe(target));
    return () => observer.disconnect();
  }, []);

  const scrollTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <div className="landing">
      <header className="landing-nav">
        <a className="landing-brand" href="#top" aria-label="TaskFlow home">
          <span className="landing-brand-icon"><img src="/mobile-taskflow-mark.svg" alt="" /></span>
          <span className="landing-wordmark"><span>Task</span><strong>Flow</strong></span>
        </a>
        <nav className="landing-nav-links" aria-label="Public navigation">
          <button onClick={() => scrollTo('how-it-works')}>How it works</button>
          <button onClick={() => scrollTo('ai-drafting')}>AI drafting</button>
          <button onClick={() => scrollTo('faq')}>FAQ</button>
        </nav>
        <div className="landing-actions">
          <button className="landing-icon" onClick={toggleTheme} aria-label={`Switch to ${mode === 'dark' ? 'light' : 'dark'} mode`}>
            {mode === 'dark' ? <Sun size={18} /> : <Moon size={18} />}
          </button>
          <button className="landing-sign-in" onClick={() => navigate('login')}>Log in</button>
        </div>
      </header>

      <main id="top">
        <section className="landing-hero" data-scroll-reveal>
          <div className="landing-hero-copy">
            <h1 className="landing-headline-wipe">Turn scattered work into finished projects.</h1>
            <p className="landing-intro">Plan projects, assign tasks, and follow progress from one shared workspace.</p>
            <div className="landing-cta">
              <button className="landing-primary" onClick={() => navigate('register')}>Create your workspace</button>
              <button className="landing-video-link" onClick={() => (document.getElementById('workflow-video') as HTMLVideoElement | null)?.play()}>
                <span className="video-play-small"><Play size={12} fill="currentColor" /></span> Watch the 30-second demo
              </button>
            </div>
          </div>
          <div className="hero-video-frame">
            <video id="workflow-video" controls playsInline preload="metadata" poster="/TaskFlow%20%E2%80%94%20Logo%20System%20v2/Landing%20page%20v3%20%E2%80%94%20with%20video%20(draft)@2x.png" aria-label="30-second TaskFlow workflow demonstration">
              <source src="/taskflow-workflow-demo.mp4" type="video/mp4" />
              Your browser does not support embedded video.
            </video>
            <div className="video-hint"><span>TaskFlow workflow demo</span><span>0:27</span></div>
          </div>
        </section>

        <section id="how-it-works" className="landing-section landing-how" data-scroll-reveal>
          <p className="landing-eyebrow">How it works</p>
          <h2>From first idea to done, in four steps</h2>
          <p className="landing-section-intro">A simple project workflow, from setup through delivery.</p>
          <div className="steps">
            {steps.map(([number, title, text]) => <article className="step" key={number}><span className="step-number">{number}</span><h3>{title}</h3><p>{text}</p></article>)}
          </div>
        </section>

        <section className="landing-audience" data-scroll-reveal>
          <div className="landing-section">
            <p className="landing-eyebrow">For your team</p>
            <h2>Clear responsibilities at every level</h2>
            <div className="audience-grid">
              {audiences.map(([label, title, text]) => <article className="audience-card" key={title}><span>{label}</span><h3>{title}</h3><p>{text}</p></article>)}
            </div>
          </div>
        </section>

        <section id="ai-drafting" className="landing-ai" data-scroll-reveal>
          <div className="ai-copy">
            <p className="landing-eyebrow">AI-assisted drafting</p>
            <h2>Describe the task. Review the draft. You decide.</h2>
            <p>Describe the work to get a suggested title and subtasks. Review and edit the draft before adding it to your project.</p>
          </div>
          <div className="ai-draft-card">
            <div className="ai-idea"><small>Task description</small><span>Prepare the website for launch</span></div>
            <div className="ai-suggestion">
              <small>Suggested title</small><strong>Prepare website launch checklist</strong>
              <small>Subtasks</small>
              <span className="draft-check">Review final copy and visuals</span><span className="draft-check">Test forms and links</span><span className="draft-check">Confirm launch date</span>
              <div className="draft-actions"><span>Review suggestion in TaskFlow</span></div>
            </div>
          </div>
        </section>

        <section className="landing-promises" data-scroll-reveal>
          <div className="landing-section">
            <p className="landing-eyebrow">Designed for shared work</p>
            <h2>Work stays organized and accountable</h2>
            <div className="promise-grid">{promises.map(([title, text]) => <article className="promise-card" key={title}><h3>{title}</h3><p>{text}</p></article>)}</div>
          </div>
        </section>

        <section id="faq" className="landing-section landing-faq" data-scroll-reveal>
          <p className="landing-eyebrow">FAQ</p><h2>Common questions</h2>
          <div className="faq-list">{questions.map(([question, answer]) => <details key={question}><summary>{question}</summary><p>{answer}</p></details>)}</div>
        </section>

        <section className="landing-final" data-scroll-reveal>
          <div><h2>Bring your projects and tasks into one workspace.</h2><p>Set up your team and start with your next project.</p></div>
          <button className="landing-primary" onClick={() => navigate('register')}>Create your workspace <ArrowRight size={16} /></button>
        </section>
      </main>

      <footer className="landing-footer">
        <a className="landing-brand" href="#top" aria-label="TaskFlow home"><span className="landing-brand-icon"><img src="/mobile-taskflow-mark.svg" alt="" /></span><span className="landing-wordmark"><span>Task</span><strong>Flow</strong></span></a>
        <small>© 2026 TaskFlow <span>·</span> Privacy <span>·</span> Terms <span>·</span> Support</small>
      </footer>
    </div>
  );
}
