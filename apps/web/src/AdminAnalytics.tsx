import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { subDays, format } from "date-fns";
import { Box, Typography, Button, CircularProgress, Alert, Grid } from "@mui/material";
import { api } from "./api";
import { AdminAnalyticsResponse } from "./types/admin";
import UserGrowthChart from "./UserGrowthChart";
import ProjectGrowthChart from "./ProjectGrowthChart";
import TaskStatusChart from "./TaskStatusChart";
import TaskPriorityChart from "./TaskPriorityChart";

const AdminAnalytics = () => {
  const [dateRange, setDateRange] = useState({ from: format(subDays(new Date(), 30), "yyyy-MM-dd"), to: format(new Date(), "yyyy-MM-dd") });

  const { data: analytics, isLoading, error } = useQuery<AdminAnalyticsResponse>({
    queryKey: ["adminAnalytics", dateRange],
    queryFn: () => api.get(`/admin/analytics?from=${dateRange.from}&to=${dateRange.to}`).then((res) => res.data),
  });

  const setDate = (days: number) => {
    const from = format(subDays(new Date(), days), "yyyy-MM-dd");
    const to = format(new Date(), "yyyy-MM-dd");
    setDateRange({ from, to });
  };

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h4" component="h1" sx={{ mb: 1 }}>Analytics</Typography>
      <Typography variant="body1" color="text.secondary" sx={{ mb: 2 }}>Monitor platform growth and activity.</Typography>
      <Box sx={{ mb: 3 }}>
        <Button onClick={() => setDate(7)}>7 Days</Button>
        <Button onClick={() => setDate(30)}>30 Days</Button>
        <Button onClick={() => setDate(90)}>90 Days</Button>
      </Box>

      {isLoading && <CircularProgress />}
      {error && <Alert severity="error">Failed to load analytics data.</Alert>}
      {analytics && analytics.userGrowth.length === 0 && analytics.projectGrowth.length === 0 && analytics.tasksByStatus.length === 0 && analytics.tasksByPriority.length === 0 && <Alert severity="info">No platform activity was recorded for this date range.</Alert>}
      {analytics && (analytics.userGrowth.length > 0 || analytics.projectGrowth.length > 0 || analytics.tasksByStatus.length > 0 || analytics.tasksByPriority.length > 0) && (
        <Grid container spacing={4}>
          <Grid item xs={12}>
            <UserGrowthChart data={analytics.userGrowth} />
          </Grid>
          <Grid item xs={12}>
            <ProjectGrowthChart data={analytics.projectGrowth} />
          </Grid>
          <Grid item xs={12}>
            <TaskStatusChart data={analytics.tasksByStatus} />
          </Grid>
          <Grid item xs={12}>
            <TaskPriorityChart data={analytics.tasksByPriority} />
          </Grid>
        </Grid>
      )}
    </Box>
  );
};

export default AdminAnalytics;
