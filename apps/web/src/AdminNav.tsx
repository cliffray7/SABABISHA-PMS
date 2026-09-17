import { LayoutDashboard, BarChart, FileDown } from "lucide-react";

interface AdminNavProps {
    route: string;
    navigate: (route: string) => void;
}

const AdminNav = ({ route, navigate }: AdminNavProps) => {
    const navItems = [
        { id: 'admin', label: 'Overview', icon: LayoutDashboard },
        { id: 'admin/analytics', label: 'Analytics', icon: BarChart },
        { id: 'admin/reports', label: 'Reports', icon: FileDown }
    ];

    return (
        <>
            {navItems.map(item => (
                <button
                    key={item.id}
                    className={'nav-item ' + (route === item.id ? 'active' : '')}
                    aria-current={route === item.id ? 'page' : undefined}
                    onClick={() => navigate(item.id)}
                >
                    <item.icon size={18} />
                    {item.label}
                </button>
            ))}
        </>
    );
};

export default AdminNav;