import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { format, subDays } from "date-fns";
import { Alert, Box, Card, CardContent, CircularProgress, Grid, Typography } from "@mui/material";
import { Bar, BarChart, CartesianGrid, Cell, Legend, Line, LineChart, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { api } from "./api";
import type { AdminAnalyticsResponse } from "./types/admin";
import { AnalyticsPageLoading } from "./components/AdminLoading";

const periods = [7, 30, 90] as const;
const chartColors = { primary: "#5b5bd6", teal: "#399779", amber: "#d49335", red: "#d65b63", muted: "#9696a3" };
const statusColor = (status: string) => ({
  "TO DO": chartColors.muted,
  "IN PROGRESS": chartColors.primary,
  REVIEW: chartColors.amber,
  DONE: chartColors.teal,
}[status.toUpperCase()] ?? chartColors.muted);
const priorityColor = (priority: string) => ({ HIGH: chartColors.red, MEDIUM: chartColors.amber, LOW: chartColors.muted }[priority.toUpperCase()] ?? chartColors.primary);
const formatChartDate = (value: unknown, pattern: string) => {
  const raw = String(value ?? "");
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? raw : format(date, pattern);
};

const AdminAnalytics = () => {
  const [days, setDays] = useState<(typeof periods)[number]>(30);
  const dateRange = useMemo(() => ({ from: format(subDays(new Date(), days), "yyyy-MM-dd"), to: format(new Date(), "yyyy-MM-dd") }), [days]);
  const { data, isLoading, error } = useQuery<AdminAnalyticsResponse>({
    queryKey: ["adminAnalytics", dateRange.from, dateRange.to],
    queryFn: () => api.get<AdminAnalyticsResponse>("/admin/analytics", { params: dateRange }).then((response) => response.data),
    refetchInterval: 30_000,
  });

  const userGrowth = data?.userGrowth ?? [];
  const projectGrowth = data?.projectGrowth ?? [];
  const statusData = (data?.tasksByStatus ?? []).filter((item) => item.count > 0).map((item) => ({ ...item, fill: statusColor(item.status) }));
  const priorityData = (data?.tasksByPriority ?? []).filter((item) => item.count > 0).map((item) => ({ ...item, fill: priorityColor(item.priority) }));
  const tasksInRange = priorityData.reduce((total, item) => total + item.count, 0);
  const summaries = [
    { label: "New users", value: userGrowth.reduce((total, point) => total + point.users, 0), note: `in ${days} days` },
    { label: "New projects", value: projectGrowth.reduce((total, point) => total + point.projects, 0), note: `in ${days} days` },
    { label: "Tasks created", value: tasksInRange, note: `in ${days} days` },
    { label: "High priority", value: priorityData.find((item) => item.priority.toUpperCase() === "HIGH")?.count ?? 0, note: "tasks in range" },
  ];
  const hasData = userGrowth.length + projectGrowth.length + statusData.length + priorityData.length > 0;
  const chartProps = {
    margin: { top: 8, right: 10, bottom: 0, left: -18 },
  };
  const axisTick = { fill: "var(--analytics-muted)", fontSize: 11 };

  return (
    <Box className="admin-analytics-page">
      <header className="admin-analytics-header">
        <div><Typography component="h1" className="admin-analytics-title">Analytics</Typography><Typography className="admin-analytics-subtitle">Growth and task patterns across the platform.</Typography></div>
        <div className="admin-analytics-periods" role="group" aria-label="Analytics date range">
          {periods.map((period) => <button type="button" key={period} aria-pressed={days === period} className={days === period ? "selected" : ""} onClick={() => setDays(period)}>{period} days</button>)}
        </div>
      </header>

      {error && <Alert severity="error" className="admin-analytics-alert">Analytics could not be loaded. Try again shortly.</Alert>}
      {isLoading && <AnalyticsPageLoading />}
      {data && !hasData && <div className="admin-analytics-empty"><span className="admin-analytics-empty-mark">—</span><strong>No analytics for this period</strong><p>There are no recorded users, projects, or tasks in the selected date range.</p></div>}

      {data && hasData && <>
        <section className="admin-analytics-summary" aria-label="Analytics summary">
          {summaries.map((item) => <Card className="admin-analytics-stat" key={item.label}><CardContent><span>{item.label}</span><strong>{item.value.toLocaleString()}</strong><small>{item.note}</small></CardContent></Card>)}
        </section>

        <Grid container spacing={2} className="admin-analytics-grid">
          <Grid item xs={12} lg={6}><Card className="admin-analytics-card"><CardContent>
            <div className="admin-analytics-card-heading"><div><h2>User growth</h2><p>New accounts created each day</p></div></div>
            <div className="admin-analytics-chart"><ResponsiveContainer width="100%" height="100%"><LineChart data={userGrowth} {...chartProps}>
              <CartesianGrid vertical={false} stroke="var(--analytics-border)" strokeDasharray="3 5"/><XAxis dataKey="date" tickFormatter={(value: string) => formatChartDate(value, "MMM d")} tickLine={false} axisLine={false} tick={axisTick} minTickGap={24}/><YAxis domain={[0, "auto"]} allowDecimals={false} tickLine={false} axisLine={false} tick={axisTick}/>
              <Tooltip cursor={{ stroke: "var(--analytics-muted)", strokeDasharray: "3 4" }} labelFormatter={(value) => formatChartDate(value, "MMM d, yyyy")} formatter={(value) => [Number(value).toLocaleString(), "New users"]}/>
              <Line type="monotone" dataKey="users" stroke={chartColors.primary} strokeWidth={2.5} dot={false} activeDot={{ r: 4, fill: chartColors.primary, stroke: "var(--analytics-card)", strokeWidth: 2 }}/>
            </LineChart></ResponsiveContainer></div>
          </CardContent></Card></Grid>

          <Grid item xs={12} lg={6}><Card className="admin-analytics-card"><CardContent>
            <div className="admin-analytics-card-heading"><div><h2>Project growth</h2><p>New projects created each day</p></div></div>
            <div className="admin-analytics-chart"><ResponsiveContainer width="100%" height="100%"><LineChart data={projectGrowth} {...chartProps}>
              <CartesianGrid vertical={false} stroke="var(--analytics-border)" strokeDasharray="3 5"/><XAxis dataKey="date" tickFormatter={(value: string) => formatChartDate(value, "MMM d")} tickLine={false} axisLine={false} tick={axisTick} minTickGap={24}/><YAxis domain={[0, "auto"]} allowDecimals={false} tickLine={false} axisLine={false} tick={axisTick}/>
              <Tooltip cursor={{ stroke: "var(--analytics-muted)", strokeDasharray: "3 4" }} labelFormatter={(value) => formatChartDate(value, "MMM d, yyyy")} formatter={(value) => [Number(value).toLocaleString(), "New projects"]}/>
              <Line type="monotone" dataKey="projects" stroke={chartColors.teal} strokeWidth={2.5} dot={false} activeDot={{ r: 4, fill: chartColors.teal, stroke: "var(--analytics-card)", strokeWidth: 2 }}/>
            </LineChart></ResponsiveContainer></div>
          </CardContent></Card></Grid>

          <Grid item xs={12} lg={6}><Card className="admin-analytics-card"><CardContent>
            <div className="admin-analytics-card-heading"><div><h2>Tasks by status</h2><p>Current status of tasks created in this period</p></div></div>
            <div className="admin-analytics-chart"><ResponsiveContainer width="100%" height="100%"><BarChart data={statusData} {...chartProps}>
              <CartesianGrid vertical={false} stroke="var(--analytics-border)" strokeDasharray="3 5"/><XAxis dataKey="status" tickFormatter={(value: string) => value.toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase())} tickLine={false} axisLine={false} tick={axisTick}/><YAxis allowDecimals={false} tickLine={false} axisLine={false} tick={axisTick}/><Tooltip formatter={(value) => [Number(value).toLocaleString(), "Tasks"]}/>
              <Bar dataKey="count" name="Tasks" radius={[5, 5, 0, 0]}>{statusData.map((item) => <Cell key={item.status} fill={item.fill}/>)}</Bar>
            </BarChart></ResponsiveContainer></div>
          </CardContent></Card></Grid>

          <Grid item xs={12} lg={6}><Card className="admin-analytics-card"><CardContent>
            <div className="admin-analytics-card-heading"><div><h2>Tasks by priority</h2><p>Priority of tasks created in this period</p></div></div>
            <div className="admin-analytics-chart"><ResponsiveContainer width="100%" height="100%"><PieChart>
              <Pie data={priorityData} dataKey="count" nameKey="priority" innerRadius="58%" outerRadius="78%" paddingAngle={3} cornerRadius={4} stroke="var(--analytics-card)" strokeWidth={2}>{priorityData.map((item) => <Cell key={item.priority} fill={item.fill}/>)}</Pie>
              <Tooltip formatter={(value) => [Number(value).toLocaleString(), "Tasks"]}/><Legend iconType="circle" iconSize={8} formatter={(value) => String(value).toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase())}/>
            </PieChart></ResponsiveContainer><div className="admin-analytics-donut-center"><strong>{tasksInRange.toLocaleString()}</strong><span>tasks</span></div></div>
          </CardContent></Card></Grid>
        </Grid>
      </>}
    </Box>
  );
};

export default AdminAnalytics;
