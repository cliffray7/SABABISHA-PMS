import { Activity, BarChart, Building2, FileDown, HeartPulse, LayoutDashboard, Settings, Users, FolderKanban } from "lucide-react";

interface AdminNavProps {
    route: string;
    navigate: (route: string) => void;
}

const AdminNav = ({ route, navigate }: AdminNavProps) => {
    const sections = [
        { label: 'Platform', items: [{ id: 'admin', label: 'Overview', icon: LayoutDashboard }, { id: 'admin/analytics', label: 'Analytics', icon: BarChart }] },
        { label: 'Management', items: [{ id: 'admin/users', label: 'Users', icon: Users }, { id: 'admin/organizations', label: 'Organizations', icon: Building2 }, { id: 'admin/projects', label: 'Projects', icon: FolderKanban }] },
        { label: 'Monitoring', items: [{ id: 'admin/activity', label: 'Activity', icon: Activity }, { id: 'admin/health', label: 'System health', icon: HeartPulse }] },
        { label: 'Reporting', items: [{ id: 'admin/reports', label: 'Reports', icon: FileDown }] },
        { label: 'Administration', items: [{ id: 'admin/settings', label: 'Platform settings', icon: Settings }] }
    ];

    return (
        <>
            {sections.map(section => <section key={section.label} aria-label={section.label}><div className="admin-nav-heading">{section.label}</div>{section.items.map(item => (
                <button
                    key={item.id}
                    className={'nav-item ' + (route === item.id ? 'active' : '')}
                    aria-current={route === item.id ? 'page' : undefined}
                    onClick={() => navigate(item.id)}
                >
                    <item.icon size={18} />
                    {item.label}
                </button>
            ))}</section>)}
        </>
    );
};

export default AdminNav;
