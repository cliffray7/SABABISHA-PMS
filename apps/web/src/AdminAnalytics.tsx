import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { subDays, format } from "date-fns";
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  CircularProgress,
  Grid,
  Typography,
} from "@mui/material";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { api } from "./api";
import { AdminAnalyticsResponse } from "./types/admin";

/* =========================================================
   COMPONENT
========================================================= */

const AdminAnalytics = () => {
  const [dateRange, setDateRange] = useState({
    from: format(subDays(new Date(), 30), "yyyy-MM-dd"),
    to: format(new Date(), "yyyy-MM-dd"),
  });

  const { data: analytics, isLoading, error } = useQuery<AdminAnalyticsResponse>({
    queryKey: ["adminAnalytics", dateRange.from, dateRange.to],
    queryFn: () =>
      api
        .get<AdminAnalyticsResponse>("/admin/analytics", {
          params: { from: dateRange.from, to: dateRange.to },
        })
        .then(res => res.data),
    refetchInterval: 60_000, // refresh every 60 seconds
  });

  const setDate = (days: number) =>
    setDateRange({
      from: format(subDays(new Date(), days), "yyyy-MM-dd"),
      to: format(new Date(), "yyyy-MM-dd"),
    });

  const hasData =
    analytics &&
    (analytics.userGrowth.length > 0 ||
      analytics.projectGrowth.length > 0 ||
      analytics.tasksByStatus.length > 0 ||
      analytics.tasksByPriority.length > 0);

  /* =======================================================
     UI
  ======================================================= */

  return (
    <Box sx={{ p: { xs: 2, md: 3 } }}>
      {/* ===================================================
          HEADER
      =================================================== */}

      <Box
        sx={{
          display: "flex",
          flexDirection: { xs: "column", sm: "row" },
          justifyContent: "space-between",
          alignItems: { xs: "flex-start", sm: "center" },
          gap: 2,
          mb: 3,
        }}
      >
        <Box>
          <Typography variant="h4" component="h1" fontWeight={700}>
            Platform Analytics
          </Typography>
          <Typography variant="body1" color="text.secondary" sx={{ mt: 0.5 }}>
            Monitor platform growth and task activity.
          </Typography>
        </Box>

        <Box sx={{ display: "flex", flexWrap: "wrap", gap: 1 }}>
          {[7, 30, 90].map(days => (
            <Button
              key={days}
              size="small"
              variant={
                dateRange.from ===
                format(subDays(new Date(), days), "yyyy-MM-dd")
                  ? "contained"
                  : "outlined"
              }
              onClick={() => setDate(days)}
            >
              {days} Days
            </Button>
          ))}
        </Box>
      </Box>

      {/* ===================================================
          LOADING
      =================================================== */}

      {isLoading && (
        <Box sx={{ display: "flex", justifyContent: "center", py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {/* ===================================================
          ERROR
      =================================================== */}

      {error && (
        <Alert severity="error" sx={{ mb: 3 }}>
          Failed to load analytics data.
        </Alert>
      )}

      {/* ===================================================
          EMPTY STATE
      =================================================== */}

      {analytics && !hasData && (
        <Alert severity="info">
          No platform activity was recorded for this date range.
        </Alert>
      )}

      {/* ===================================================
          CHARTS
      =================================================== */}

      {hasData && (
        <Grid container spacing={3}>
          {/* USER GROWTH */}
          <Grid item xs={12} lg={6}>
            <Card sx={{ height: "100%" }}>
              <CardContent>
                <Typography variant="h6" fontWeight={600} sx={{ mb: 3 }}>
                  User Growth
                </Typography>
                <Box sx={{ width: "100%", height: 300 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={analytics.userGrowth}>
                      <CartesianGrid strokeDasharray="3 3" opacity={0.25} />
                      <XAxis dataKey="date" />
                      <YAxis allowDecimals={false} />
                      <Tooltip />
                      <Legend />
                      <Line
                        type="monotone"
                        dataKey="users"
                        stroke="currentColor"
                        strokeWidth={2}
                        dot={false}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </Box>
              </CardContent>
            </Card>
          </Grid>

          {/* PROJECT GROWTH */}
          <Grid item xs={12} lg={6}>
            <Card sx={{ height: "100%" }}>
              <CardContent>
                <Typography variant="h6" fontWeight={600} sx={{ mb: 3 }}>
                  Project Growth
                </Typography>
                <Box sx={{ width: "100%", height: 300 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={analytics.projectGrowth}>
                      <CartesianGrid strokeDasharray="3 3" opacity={0.25} />
                      <XAxis dataKey="date" />
                      <YAxis allowDecimals={false} />
                      <Tooltip />
                      <Legend />
                      <Line
                        type="monotone"
                        dataKey="projects"
                        stroke="currentColor"
                        strokeWidth={2}
                        dot={false}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </Box>
              </CardContent>
            </Card>
          </Grid>

          {/* TASKS BY STATUS */}
          <Grid item xs={12} lg={6}>
            <Card sx={{ height: "100%" }}>
              <CardContent>
                <Typography variant="h6" fontWeight={600} sx={{ mb: 3 }}>
                  Tasks by Status
                </Typography>
                <Box sx={{ width: "100%", height: 300 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={analytics.tasksByStatus}>
                      <CartesianGrid strokeDasharray="3 3" opacity={0.25} />
                      <XAxis dataKey="status" />
                      <YAxis allowDecimals={false} />
                      <Tooltip />
                      <Legend />
                      <Bar dataKey="count" fill="currentColor" />
                    </BarChart>
                  </ResponsiveContainer>
                </Box>
              </CardContent>
            </Card>
          </Grid>

          {/* TASKS BY PRIORITY */}
          <Grid item xs={12} lg={6}>
            <Card sx={{ height: "100%" }}>
              <CardContent>
                <Typography variant="h6" fontWeight={600} sx={{ mb: 3 }}>
                  Tasks by Priority
                </Typography>
                <Box sx={{ width: "100%", height: 300 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={analytics.tasksByPriority}>
                      <CartesianGrid strokeDasharray="3 3" opacity={0.25} />
                      <XAxis dataKey="priority" />
                      <YAxis allowDecimals={false} />
                      <Tooltip />
                      <Legend />
                      <Bar dataKey="count" fill="currentColor" />
                    </BarChart>
                  </ResponsiveContainer>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      )}
    </Box>
  );
};

export default AdminAnalytics;
