import { Activity, BarChart, Building2, FileDown, HeartPulse, LayoutDashboard, Settings, Users, FolderKanban, ClipboardList } from "lucide-react";
import { SidebarGroup, SidebarGroupLabel, SidebarMenu, SidebarMenuButton } from "./components/ui/sidebar";

interface AdminNavProps {
    route: string;
    navigate: (route: string) => void;
    filter?: string;
    inspiration?: boolean;
    collapsed?: boolean;
}

const AdminNav = ({ route, navigate, filter = '', inspiration = false, collapsed = false }: AdminNavProps) => {
    const adminSections = [
        { label: 'Platform', items: [{ id: 'admin', label: 'Overview', icon: LayoutDashboard }, { id: 'admin/analytics', label: 'Analytics', icon: BarChart }] },
        { label: 'Management', items: [{ id: 'admin/users', label: 'Users', icon: Users }, { id: 'admin/organizations', label: 'Organizations', icon: Building2 }, { id: 'admin/projects', label: 'Projects', icon: FolderKanban }] },
        { label: 'Monitoring', items: [{ id: 'admin/activity', label: 'Activity', icon: Activity }, { id: 'admin/audit', label: 'Audit Trail', icon: ClipboardList }, { id: 'admin/health', label: 'System health', icon: HeartPulse }] },
        { label: 'Reporting', items: [{ id: 'admin/reports', label: 'Reports', icon: FileDown }] },
        { label: 'Administration', items: [{ id: 'admin/settings', label: 'Platform settings', icon: Settings }] }
    ];
    const overviewSections = [
        { label: 'Main', items: [
            { id: 'admin', label: 'Overview', icon: LayoutDashboard },
            { id: 'admin/analytics', label: 'Analytics', icon: BarChart },
            { id: 'admin/users', label: 'Users', icon: Users },
            { id: 'admin/organizations', label: 'Organizations', icon: Building2 },
            { id: 'admin/projects', label: 'Projects', icon: FolderKanban },
        ] },
        { label: 'Tools', items: [
            { id: 'admin/activity', label: 'Activity', icon: Activity },
            { id: 'admin/audit', label: 'Audit Trail', icon: ClipboardList },
            { id: 'admin/health', label: 'System health', icon: HeartPulse },
            { id: 'admin/reports', label: 'Reports', icon: FileDown },
        ] },
        { label: 'Help', items: [
            { id: 'admin/settings', label: 'Settings', icon: Settings },
        ] },
    ];
    const sections = inspiration ? overviewSections : adminSections;
    const hasMatches = sections.some(section => section.items.some(item => item.label.toLowerCase().includes(filter.toLowerCase())));

    return (
        <>
            {sections.map(section => {
                const items = section.items.filter(item => item.label.toLowerCase().includes(filter.toLowerCase()));
                return items.length > 0 && <SidebarGroup key={section.label} aria-label={section.label}><SidebarGroupLabel>{section.label}</SidebarGroupLabel><SidebarMenu>{items.map(item => (
                <SidebarMenuButton
                    key={item.id}
                    isActive={route === item.id}
                    tooltip={item.label}
                    aria-current={route === item.id ? 'page' : undefined}
                    onClick={() => navigate(item.id)}
                >
                    <item.icon size={18} strokeWidth={1.7} />
                    <span className="admin-nav-label">{item.label}</span>
                </SidebarMenuButton>
            ))}</SidebarMenu></SidebarGroup>;
            })}
            {filter && !hasMatches && <p className="admin-nav-empty">No matching pages</p>}
        </>
    );
};

export default AdminNav;
