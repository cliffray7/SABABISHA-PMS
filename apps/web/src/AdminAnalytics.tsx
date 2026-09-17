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
      <Typography variant="h4" sx={{ mb: 2 }}>Detailed Analytics</Typography>
      <Box sx={{ mb: 3 }}>
        <Button onClick={() => setDate(7)}>Last 7 Days</Button>
        <Button onClick={() => setDate(30)}>Last 30 Days</Button>
        <Button onClick={() => setDate(90)}>Last 90 Days</Button>
      </Box>

      {isLoading && <CircularProgress />}
      {error && <Alert severity="error">Failed to load analytics data.</Alert>}
      {analytics && (
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