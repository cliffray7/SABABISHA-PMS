import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { format, subDays } from "date-fns";
import {
  Activity,
  ArrowDownToLine,
  BriefcaseBusiness,
  CheckCircle2,
  FolderKanban,
  ListChecks,
  Users,
} from "lucide-react";
import {
  CartesianGrid,
  Cell,
  Area,
  AreaChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChevronDown } from "lucide-react";
import { api } from "./api";
import type { Person } from "./api";
import type { AdminAnalyticsResponse, AdminDashboardMetrics, AdminProject } from "./types/admin";
import { Badge } from "./components/ui/badge";
import { Button } from "./components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "./components/ui/card";
import { MetricGridLoading } from "./components/AdminLoading";
import "./admin-overview.css";

type MetricKey = keyof AdminDashboardMetrics;

const metricCards: { key: MetricKey; label: string; icon: typeof Users; tone: string }[] = [
  { key: "totalUsers", label: "Total users", icon: Users, tone: "purple" },
  { key: "totalOrganizations", label: "Organizations", icon: BriefcaseBusiness, tone: "purple" },
  { key: "totalProjects", label: "Projects", icon: FolderKanban, tone: "purple" },
  { key: "totalTasks", label: "Tasks", icon: ListChecks, tone: "purple" },
  { key: "completedTasks", label: "Completed tasks", icon: CheckCircle2, tone: "green" },
  { key: "activeProjects", label: "Active projects", icon: Activity, tone: "purple" },
];

const statusColors: Record<string, string> = {
  "TO DO": "#a1a1aa",
  "IN PROGRESS": "#6c5ce7",
  REVIEW: "#d39b36",
  DONE: "#369875",
};

const AdminDashboard = ({ person }: { person?: Person }) => {
  const [isDownloading, setIsDownloading] = useState(false);
  const [periodDays, setPeriodDays] = useState(30);
  const analyticsTo = format(new Date(), "yyyy-MM-dd");
  const analyticsFrom = format(subDays(new Date(), periodDays), "yyyy-MM-dd");
  const metricsQuery = useQuery<AdminDashboardMetrics>({
    queryKey: ["adminDashboardMetrics"],
    queryFn: async () => (await api.get<AdminDashboardMetrics>("/admin/dashboard")).data,
    refetchInterval: 15_000,
  });
  const analyticsQuery = useQuery<AdminAnalyticsResponse>({
    queryKey: ["adminAnalytics", analyticsFrom, analyticsTo],
    queryFn: async () => (await api.get<AdminAnalyticsResponse>("/admin/analytics", { params: { from: analyticsFrom, to: analyticsTo } })).data,
    refetchInterval: 30_000,
  });
  const projectsQuery = useQuery<AdminProject[]>({
    queryKey: ["adminProjects", "recent"],
    queryFn: async () => (await api.get<AdminProject[]>("/admin/projects")).data,
    refetchInterval: 30_000,
  });
  const metrics = metricsQuery.data;

  const downloadReport = async () => {
    setIsDownloading(true);
    try {
      const response = await api.get("/admin/reports", { params: { format: "pdf" }, responseType: "blob" });
      const url = URL.createObjectURL(new Blob([response.data], { type: "application/pdf" }));
      const link = document.createElement("a");
      link.href = url;
      link.download = `taskflow-platform-report-${format(new Date(), "yyyy-MM-dd")}.pdf`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
    } catch (downloadError) {
      console.error("Report download failed:", downloadError);
    } finally {
      setIsDownloading(false);
    }
  };

  const taskStatus = (analyticsQuery.data?.tasksByStatus ?? [])
    .filter((item) => item.count > 0)
    .map((item) => ({ ...item, color: statusColors[item.status.toUpperCase()] ?? "#71717a" }));
  const projectGrowth = (analyticsQuery.data?.projectGrowth ?? []).map((point) => ({
    ...point,
    label: Number.isNaN(new Date(point.date).getTime()) ? point.date : format(new Date(point.date), "MMM d"),
  }));
  const projectsCreatedInPeriod = projectGrowth.reduce((total, point) => total + point.projects, 0);
  const recentProjects = (projectsQuery.data ?? []).slice(0, 5);
  const statusTotal = taskStatus.reduce((total, item) => total + item.count, 0);
  const userGrowth = analyticsQuery.data?.userGrowth ?? [];
  const trendCount = (points: { date: string; users?: number; projects?: number }[], key: "users" | "projects") => {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const start = subDays(today, 6);
    const end = subDays(today, -1);
    return points.filter((point) => { const date = new Date(`${point.date}T00:00:00`); return date >= start && date < end; })
      .reduce((total, point) => total + (point[key] ?? 0), 0);
  };
  const weeklyUsers = trendCount(userGrowth, "users");
  const weeklyProjects = trendCount(analyticsQuery.data?.projectGrowth ?? [], "projects");
  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";

  return (
    <section className="admin-overview" aria-label="Platform overview dashboard">
      <header className="admin-overview-header">
        <div>
          <div className="admin-overview-heading-copy"><div className="admin-overview-greeting-row"><h1 className="admin-overview-greeting">{greeting}{person?.firstName ? `, ${person.firstName}` : ""}</h1><span className="admin-overview-live"><i aria-hidden="true"/>Live</span></div><p className="admin-overview-subtitle">Usage and delivery across your platform.</p></div>
        </div>
        <Button variant="outline" className="admin-overview-export" onClick={downloadReport} disabled={isDownloading}>
          <ArrowDownToLine size={16} />
          {isDownloading ? "Preparing report…" : "Download report"}
        </Button>
      </header>

      {(metricsQuery.error || analyticsQuery.error || projectsQuery.error) && (
        <div className="admin-overview-error" role="alert">Some platform information could not be loaded. Retry or check the corresponding admin page.</div>
      )}

      {metricsQuery.isLoading && <MetricGridLoading />}

      {metrics && <>
        <div className="admin-overview-metrics">
          {metricCards.map(({ key, label, icon: Icon, tone }) => (
            <Card className="admin-overview-metric" key={key}>
              <div className="admin-overview-metric-top">
                <span>{label}</span>
                <span className={`admin-overview-icon ${tone}`}><Icon size={16} strokeWidth={1.8} aria-hidden="true" /></span>
              </div>
              <strong>{metrics[key].toLocaleString()}</strong>
              {(key === "totalUsers" || key === "totalProjects") && <>
                <span className="admin-overview-trend">+{key === "totalUsers" ? weeklyUsers : weeklyProjects} created · 7d</span>
                <svg className="admin-overview-sparkline" viewBox="0 0 72 24" role="img" aria-label={key === "totalUsers" ? "Daily new users" : "Daily new projects"}>
                  <polyline points={(key === "totalUsers" ? userGrowth : projectGrowth).slice(-7).map((point, index, points) => {
                    const value = key === "totalUsers" ? (point as { users: number }).users : (point as { projects: number }).projects;
                    const max = Math.max(1, ...points.map((item) => key === "totalUsers" ? (item as { users: number }).users : (item as { projects: number }).projects));
                    return `${points.length < 2 ? 36 : index * 72 / (points.length - 1)},${22 - value / max * 18}`;
                  }).join(" ")} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </>}
            </Card>
          ))}
        </div>

        <div className="admin-overview-panels">
          <Card className="admin-overview-panel admin-overview-growth">
            <CardHeader className="admin-overview-panel-heading">
              <div><CardTitle>Project growth</CardTitle><CardDescription>Projects created in the last {periodDays} days</CardDescription></div>
              <div className="admin-overview-growth-tools"><div className="admin-overview-growth-summary"><strong>{projectsCreatedInPeriod.toLocaleString()}</strong><span>created</span></div><label className="admin-overview-period-select"><span className="sr-only">Analytics period</span><select value={periodDays} onChange={(event) => setPeriodDays(Number(event.target.value))}><option value={7}>Last 7 days</option><option value={30}>Last 30 days</option><option value={90}>Last 90 days</option></select><ChevronDown size={14}/></label></div>
            </CardHeader>
            <CardContent className="admin-overview-chart-content">
              {analyticsQuery.isLoading ? <p className="admin-overview-chart-state" role="status">Loading project analytics…</p>
                : projectGrowth.length ? <ResponsiveContainer width="100%" height={220}>
                  <AreaChart data={projectGrowth} margin={{ top: 8, right: 12, bottom: 0, left: -16 }}>
                    <defs><linearGradient id="projectGrowthFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#5b5bd6" stopOpacity={0.2}/><stop offset="95%" stopColor="#5b5bd6" stopOpacity={0.015}/></linearGradient></defs>
                    <CartesianGrid vertical={false} stroke="var(--overview-border)" strokeDasharray="3 4" />
                    <XAxis dataKey="label" tickLine={false} axisLine={false} tick={{ fill: "var(--overview-muted)", fontSize: 11 }} minTickGap={22} />
                    <YAxis domain={[0, "auto"]} allowDecimals={false} tickLine={false} axisLine={false} tick={{ fill: "var(--overview-muted)", fontSize: 11 }} />
                    <Tooltip cursor={{ stroke: "var(--overview-muted)", strokeDasharray: "3 4" }} content={({ active, payload, label }) => active && payload?.length ? <div className="admin-overview-tooltip"><span>{String(label)}</span><strong>{Number(payload[0].value).toLocaleString()} projects</strong></div> : null} />
                    <Area type="monotone" dataKey="projects" name="Projects" stroke="#5b5bd6" strokeWidth={2} fill="url(#projectGrowthFill)" dot={false} activeDot={{ r: 4, fill: "#5b5bd6", stroke: "var(--overview-card)", strokeWidth: 2 }} />
                  </AreaChart>
                </ResponsiveContainer>
                  : <p className="admin-overview-chart-state">No project growth data is available yet.</p>}
            </CardContent>
          </Card>

          <Card className="admin-overview-panel admin-overview-status">
            <CardHeader className="admin-overview-panel-heading">
              <div><CardTitle>Task status</CardTitle><CardDescription>Tasks created in the last {periodDays} days · current status</CardDescription></div>
            </CardHeader>
            <CardContent className="admin-overview-status-content">
              {analyticsQuery.isLoading ? <p className="admin-overview-chart-state" role="status">Loading task statuses…</p> : taskStatus.length ? <>
                <div className="admin-overview-status-chart" role="img" aria-label="Task distribution by status">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={taskStatus} dataKey="count" nameKey="status" innerRadius="67%" outerRadius="88%" paddingAngle={3} cornerRadius={4} stroke="var(--overview-card)" strokeWidth={2}>
                        {taskStatus.map((item) => <Cell key={item.status} fill={item.color} />)}
                      </Pie>
                      <Tooltip content={({ active, payload }) => active && payload?.length ? <div className="admin-overview-tooltip"><span>{String(payload[0].name)}</span><strong>{Number(payload[0].value).toLocaleString()} tasks</strong></div> : null} />
                    </PieChart>
                  </ResponsiveContainer>
                  <div className="admin-overview-chart-center"><strong>{statusTotal.toLocaleString()}</strong><span>tasks</span></div>
                </div>
                <div className="admin-overview-status-legend">
                  {taskStatus.map((item) => <div key={item.status}><span className="admin-overview-dot" style={{ background: item.color }} /><span>{item.status.toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase())}</span><strong>{statusTotal ? Math.round(item.count / statusTotal * 100) : 0}%</strong></div>)}
                </div>
              </> : <p className="admin-overview-chart-state">No task status data is available yet.</p>}
            </CardContent>
          </Card>
        </div>

        <Card className="admin-overview-panel admin-overview-projects">
          <CardHeader className="admin-overview-panel-heading">
            <div><CardTitle>Recent projects</CardTitle><CardDescription>Latest platform projects</CardDescription></div>
          </CardHeader>
          <CardContent className="admin-overview-table-wrap">
            {projectsQuery.isLoading ? <p className="admin-overview-chart-state" role="status">Loading projects…</p> : recentProjects.length ? <table className="admin-overview-table">
              <thead><tr><th scope="col">Project</th><th scope="col">Organization</th><th scope="col">Tasks</th><th scope="col">Status</th><th scope="col">Created</th></tr></thead>
              <tbody>{recentProjects.map((project) => <tr key={project.id}>
                <td><span className="admin-overview-project-name"><span className="admin-overview-project-mark"><FolderKanban size={15} aria-hidden="true" /></span><strong>{project.name}</strong></span></td>
                <td className="admin-overview-project-org">{project.organizationName ?? "—"}</td>
                <td><span className="admin-overview-task-count"><strong>{project.taskCount.toLocaleString()}</strong><small>{project.taskCount === 1 ? "task" : "tasks"}</small></span></td>
                <td><Badge className={`admin-overview-project-status ${project.archivedAt ? "archived" : project.status.toLowerCase().replace(/_/g, "-")}`}>{project.archivedAt ? "Archived" : project.status.toLowerCase().replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase())}</Badge></td>
                <td>{format(new Date(project.createdAt), "MMM d, yyyy")}</td>
              </tr>)}</tbody>
            </table> : <p className="admin-overview-chart-state">No projects have been created yet.</p>}
          </CardContent>
        </Card>
      </>}
    </section>
  );
};

export default AdminDashboard;
