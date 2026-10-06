import {
  ArrowRight,
  Bell,
  Check,
  FolderKanban,
  ListChecks,
  LockKeyhole,
  Moon,
  Sparkles,
  Sun,
  Users,
} from 'lucide-react';
import './landing.css';

type ColorMode = 'light' | 'dark';

type LandingPageProps = {
  navigate: (route: string) => void;
  mode: ColorMode;
  toggleTheme: () => void;
};

const steps = [
  ['01', 'Create your workspace', 'Set up your organization and invite your team.'],
  ['02', 'Plan your projects', 'Give each project a clear goal and timeline.'],
  ['03', 'Assign the work', 'Break projects into tasks and choose owners.'],
  ['04', 'See progress', 'Keep the whole team up to date as work moves forward.'],
];

const features = [
  {
    icon: <FolderKanban />,
    title: 'Projects that stay organized',
    text: 'Keep project goals, timelines and work together in one shared space.',
  },
  {
    icon: <ListChecks />,
    title: 'Tasks with clear ownership',
    text: 'Create tasks, set priorities and make it easy to see what happens next.',
  },
  {
    icon: <Users />,
    title: 'One team workspace',
    text: 'Bring people together around the projects and tasks they are working on.',
  },
  {
    icon: <Bell />,
    title: 'Updates that keep you moving',
    text: 'Stay informed about task changes and important project activity.',
  },
  {
    icon: <LockKeyhole />,
    title: 'Access that respects roles',
    text: 'Organization and project access keep the right work in the right hands.',
  },
  {
    icon: <Sparkles />,
    title: 'A head start from AI',
    text: 'Draft task titles, descriptions and subtasks, then review before saving.',
  },
];

export default function LandingPage({ navigate, mode, toggleTheme }: LandingPageProps) {
  const scrollTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <div className="landing">
      <header className="landing-nav">
        <a className="landing-brand" href="#top" aria-label="TaskFlow home">
          <span className="landing-brand-icon">
            <img src="/mobile-taskflow-mark.svg" alt="" />
          </span>
          <span className="landing-wordmark"><span>Task</span><strong>Flow</strong></span>
        </a>
        <nav className="landing-nav-links" aria-label="Public navigation">
          <button onClick={() => scrollTo('how-it-works')}>How it works</button>
          <button onClick={() => scrollTo('ai-drafting')}>AI drafting</button>
          <button onClick={() => scrollTo('faq')}>FAQ</button>
        </nav>
        <div className="landing-actions">
          <button
            className="landing-icon"
            onClick={toggleTheme}
            aria-label={`Switch to ${mode === 'dark' ? 'light' : 'dark'} mode`}
          >
            {mode === 'dark' ? <Sun size={18} /> : <Moon size={18} />}
          </button>
          <button className="landing-sign-in" onClick={() => navigate('login')}>Sign in</button>
          <button className="landing-primary landing-header-cta" onClick={() => navigate('register')}>
            Get started
          </button>
        </div>
      </header>

      <main id="top">
        <section className="landing-hero">
          <div className="landing-hero-copy">
            <p className="landing-eyebrow">A calmer way to work together</p>
            <h1>Turn scattered work into finished projects.</h1>
            <p className="landing-intro">
              Organize projects, assign tasks, and see progress in one workspace, so your whole
              team knows what is moving and what is next.
            </p>
            <div className="landing-cta">
              <button className="landing-primary" onClick={() => navigate('register')}>
                Create your workspace <ArrowRight size={18} />
              </button>
              <button className="landing-text-cta" onClick={() => scrollTo('how-it-works')}>
                See how it works <ArrowRight size={18} />
              </button>
            </div>
            <div className="landing-values" aria-label="TaskFlow benefits">
              <span><Check size={16} /> Projects in one place</span>
              <span><Check size={16} /> Clear task ownership</span>
              <span><Check size={16} /> Progress at a glance</span>
            </div>
          </div>
          <ProjectPreview />
        </section>

        <section id="how-it-works" className="landing-section landing-how">
          <p className="landing-eyebrow">How it works</p>
          <h2>From first idea to done, in four steps</h2>
          <p className="landing-section-intro">
            Give your team a shared place to plan the work and follow it through.
          </p>
          <div className="steps">
            {steps.map(([number, title, text]) => (
              <article className="step" key={number}>
                <span className="step-number">{number}</span>
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="features" className="landing-section landing-features">
          <p className="landing-eyebrow">One workspace, less busywork</p>
          <h2>Everything your team needs to keep work moving</h2>
          <p className="landing-section-intro">
            From project planning to the last task, TaskFlow keeps the details connected.
          </p>
          <div className="feature-grid">
            {features.map(({ icon, title, text }) => (
              <article className="feature-card" key={title}>
                <span className="feature-icon">{icon}</span>
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="ai-drafting" className="landing-ai">
          <div className="ai-mark"><Sparkles size={24} /></div>
          <div className="ai-copy">
            <p className="landing-eyebrow">AI-assisted task drafting</p>
            <h2>Start with a draft. Make it yours.</h2>
            <p>
              Describe the work and get a suggested title, description, priority and subtasks.
              Review the draft and decide what to save.
            </p>
          </div>
          <div className="ai-example" aria-label="Example task prompt">
            <span>What needs to get done?</span>
            <p>Prepare a launch plan for our new website</p>
            <span className="ai-example-action"><Sparkles size={16} /> Draft a task</span>
          </div>
        </section>

        <section id="faq" className="landing-section landing-faq">
          <p className="landing-eyebrow">FAQ</p>
          <h2>A few things you might be wondering</h2>
          <div className="faq-list">
            <details>
              <summary>How do I get started with TaskFlow?</summary>
              <p>Create your workspace, set up an organization, then invite your team and start a project.</p>
            </details>
            <details>
              <summary>Can I organize work into projects and tasks?</summary>
              <p>Yes. Projects bring related work together, and tasks can be assigned and tracked as they move forward.</p>
            </details>
            <details>
              <summary>Do AI suggestions get saved automatically?</summary>
              <p>No. AI helps draft task details, and you review the suggestion before choosing to save it.</p>
            </details>
          </div>
        </section>

        <section className="landing-final">
          <div>
            <p className="landing-eyebrow">Make room for the work that matters</p>
            <h2>Ready to bring your projects together?</h2>
          </div>
          <button className="landing-primary" onClick={() => navigate('register')}>
            Create your workspace <ArrowRight size={18} />
          </button>
        </section>
      </main>

      <footer className="landing-footer">
        <div className="footer-brand">
          <a className="landing-brand" href="#top" aria-label="TaskFlow home">
            <span className="landing-brand-icon">
              <img src="/mobile-taskflow-mark.svg" alt="" />
            </span>
            <span className="landing-wordmark"><span>Task</span><strong>Flow</strong></span>
          </a>
          <p>Projects, people and progress — together.</p>
        </div>
        <div className="footer-links">
          <strong>Explore</strong>
          <button onClick={() => scrollTo('how-it-works')}>How it works</button>
          <button onClick={() => scrollTo('features')}>Features</button>
          <button onClick={() => scrollTo('faq')}>FAQ</button>
        </div>
        <div className="footer-links">
          <strong>Your account</strong>
          <button onClick={() => navigate('login')}>Sign in</button>
          <button onClick={() => navigate('register')}>Create a workspace</button>
        </div>
        <small>© 2026 TaskFlow. All rights reserved.</small>
      </footer>
    </div>
  );
}

function ProjectPreview() {
  const columns = [
    { name: 'To do', color: 'muted', tasks: ['Write FAQ copy', 'Update pricing page'] },
    { name: 'In progress', color: 'orange', tasks: ['Build new homepage', 'Review checkout flow'] },
    { name: 'Done', color: 'blue', tasks: ['Approve brand colors', 'Set up analytics'] },
  ];

  return (
    <div className="project-preview" aria-label="TaskFlow project board preview">
      <div className="preview-topline">
        <img src="/Mobile%20launcher.svg" alt="" />
        <div>
          <p>Team workspace</p>
          <h2>Website relaunch</h2>
        </div>
        <span className="preview-switch">Website team <span aria-hidden="true">⌄</span></span>
      </div>
      <div className="preview-progress">
        <div><span>Due Nov 28 · 8 of 14 tasks done</span><strong>57%</strong></div>
        <span className="progress-track"><span /></span>
      </div>
      <div className="preview-columns">
        {columns.map(({ name, color, tasks }) => (
          <section className="preview-column" key={name}>
            <h3><span className={`column-dot ${color}`} />{name}</h3>
            {tasks.map(task => <article className="preview-task" key={task}>{task}</article>)}
          </section>
        ))}
      </div>
      <div className="preview-caption">
        <span><span className="caption-dot orange" /> Work in progress</span>
        <span><Check size={14} /> Shared with your team</span>
      </div>
    </div>
  );
}
