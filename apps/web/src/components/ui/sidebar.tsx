import { createContext, forwardRef, useContext, type ButtonHTMLAttributes, type HTMLAttributes, type ReactNode } from "react";
import { Menu, PanelLeftClose, PanelLeftOpen, X } from "lucide-react";
import { cn } from "../../lib/utils";

interface SidebarContextValue {
  collapsed: boolean;
  mobileOpen: boolean;
  toggleCollapsed: () => void;
  toggleMobile: () => void;
}

const SidebarContext = createContext<SidebarContextValue | null>(null);

function useSidebar() {
  const context = useContext(SidebarContext);
  if (!context) throw new Error("Sidebar components must be rendered inside SidebarProvider.");
  return context;
}

export function SidebarProvider({ children, collapsed, mobileOpen, toggleCollapsed, toggleMobile }: SidebarContextValue & { children: ReactNode }) {
  return <SidebarContext.Provider value={{ collapsed, mobileOpen, toggleCollapsed, toggleMobile }}>{children}</SidebarContext.Provider>;
}

export const Sidebar = forwardRef<HTMLElement, HTMLAttributes<HTMLElement>>(function Sidebar({ className, children, ...props }, ref) {
  const { collapsed, mobileOpen } = useSidebar();
  return <aside ref={ref} data-slot="sidebar" data-state={collapsed ? "collapsed" : "expanded"} data-collapsible={collapsed ? "icon" : "none"} className={cn("sidebar", collapsed && "is-collapsed", mobileOpen && "is-open", className)} {...props}>{children}</aside>;
});

export function SidebarHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div data-slot="sidebar-header" className={cn("admin-sidebar-brand-row", className)} {...props}/>;
}

export function SidebarContent({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div data-slot="sidebar-content" className={cn("admin-sidebar-content", className)} {...props}/>;
}

export function SidebarGroup({ className, children, ...props }: HTMLAttributes<HTMLElement>) {
  return <section data-slot="sidebar-group" className={cn("admin-sidebar-group", className)} {...props}>{children}</section>;
}

export function SidebarGroupLabel({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div data-slot="sidebar-group-label" className={cn("admin-nav-heading", className)} {...props}/>;
}

export function SidebarMenu({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div data-slot="sidebar-menu" className={cn("admin-sidebar-menu", className)} {...props}/>;
}

interface SidebarMenuButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  isActive?: boolean;
  tooltip?: string;
}

export const SidebarMenuButton = forwardRef<HTMLButtonElement, SidebarMenuButtonProps>(function SidebarMenuButton({ className, isActive = false, tooltip, children, ...props }, ref) {
  const { collapsed } = useSidebar();
  return <button ref={ref} data-slot="sidebar-menu-button" data-active={isActive || undefined} title={collapsed ? tooltip : undefined} className={cn("nav-item", isActive && "active", className)} {...props}>{children}</button>;
});

export function SidebarFooter({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div data-slot="sidebar-footer" className={cn("admin-sidebar-footer", className)} {...props}/>;
}

export function SidebarTrigger({ mobile = false, className, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { mobile?: boolean }) {
  const { collapsed, mobileOpen, toggleCollapsed, toggleMobile } = useSidebar();
  if (mobile) return <button type="button" data-slot="sidebar-trigger" aria-label={mobileOpen ? "Close navigation" : "Open navigation"} aria-expanded={mobileOpen} className={cn("admin-overview-mobile-menu", className)} onClick={toggleMobile} {...props}>{mobileOpen ? <X size={19}/> : <Menu size={19}/>}</button>;
  return <button type="button" data-slot="sidebar-trigger" aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"} aria-expanded={!collapsed} title={collapsed ? "Expand sidebar" : "Collapse sidebar"} className={cn("admin-sidebar-toggle", className)} onClick={toggleCollapsed} {...props}>{collapsed ? <PanelLeftOpen size={17}/> : <PanelLeftClose size={17}/>}</button>;
}

export function SidebarOverlay({ className, ...props }: ButtonHTMLAttributes<HTMLButtonElement>) {
  const { mobileOpen, toggleMobile } = useSidebar();
  if (!mobileOpen) return null;
  return <button type="button" data-slot="sidebar-overlay" aria-label="Close navigation" className={cn("admin-overview-nav-scrim", className)} onClick={toggleMobile} {...props}/>;
}
