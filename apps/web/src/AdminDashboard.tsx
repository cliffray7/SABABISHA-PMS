import { useState, type ReactNode } from "react";
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
  Activity,
  Briefcase,
  CheckCircle,
  FolderKanban,
  ListChecks,
  Users,
} from "lucide-react";
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
import {
  AdminAnalyticsResponse,
  AdminDashboardMetrics,
} from "./types/admin";

/* =========================================================
   TYPES
========================================================= */

type MetricKey = keyof AdminDashboardMetrics;

interface MetricCardDefinition {
  key: MetricKey;
  label: string;
}

/* =========================================================
   METRIC CONFIGURATION
========================================================= */

const metricCards: MetricCardDefinition[] = [
  {
    key: "totalUsers",
    label: "Total Users",
  },
  {
    key: "totalOrganizations",
    label: "Total Organizations",
  },
  {
    key: "totalProjects",
    label: "Total Projects",
  },
  {
    key: "totalTasks",
    label: "Total Tasks",
  },
  {
    key: "completedTasks",
    label: "Completed Tasks",
  },
  {
    key: "activeProjects",
    label: "Active Projects",
  },
];

const iconMap: Record<MetricKey, ReactNode> = {
  totalUsers: <Users size={22} />,
  totalOrganizations: <Briefcase size={22} />,
  totalProjects: <FolderKanban size={22} />,
  totalTasks: <ListChecks size={22} />,
  completedTasks: <CheckCircle size={22} />,
  activeProjects: <Activity size={22} />,
};

/* =========================================================
   COMPONENT
========================================================= */

const AdminDashboard = () => {
  const [dateRange, setDateRange] = useState({
    from: format(subDays(new Date(), 30), "yyyy-MM-dd"),
    to: format(new Date(), "yyyy-MM-dd"),
  });

  const [isDownloading, setIsDownloading] = useState(false);

  /* =======================================================
     DASHBOARD METRICS
  ======================================================= */

  const {
    data: metrics,
    isLoading: metricsLoading,
    error: metricsError,
  } = useQuery<AdminDashboardMetrics>({
    queryKey: ["adminDashboardMetrics"],

    queryFn: async () => {
      const response =
        await api.get<AdminDashboardMetrics>("/admin/dashboard");

      return response.data;
    },
  });

  /* =======================================================
     ANALYTICS
  ======================================================= */

  const {
    data: analytics,
    isLoading: analyticsLoading,
    error: analyticsError,
  } = useQuery<AdminAnalyticsResponse>({
    queryKey: ["adminAnalytics", dateRange.from, dateRange.to],

    queryFn: async () => {
      const response = await api.get<AdminAnalyticsResponse>(
        "/admin/analytics",
        {
          params: {
            from: dateRange.from,
            to: dateRange.to,
          },
        },
      );

      return response.data;
    },
  });

  /* =======================================================
     DATE FILTER
  ======================================================= */

  const setDate = (days: number) => {
    setDateRange({
      from: format(subDays(new Date(), days), "yyyy-MM-dd"),
      to: format(new Date(), "yyyy-MM-dd"),
    });
  };

  /* =======================================================
     REPORT DOWNLOAD
  ======================================================= */

  const downloadReport = async () => {
    setIsDownloading(true);

    try {
      const response = await api.get("/admin/reports", {
        params: {
          format: "csv",
        },
        responseType: "blob",
      });

      const blob = new Blob([response.data], {
        type: "text/csv;charset=utf-8",
      });

      const url = window.URL.createObjectURL(blob);

      const link = document.createElement("a");

      link.href = url;

      link.download =
        `taskflow-report-${format(new Date(), "yyyy-MM-dd")}.csv`;

      document.body.appendChild(link);

      link.click();

      document.body.removeChild(link);

      window.URL.revokeObjectURL(url);
    } catch (error) {
      console.error("Report download failed:", error);
    } finally {
      setIsDownloading(false);
    }
  };

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
          flexDirection: {
            xs: "column",
            sm: "row",
          },
          justifyContent: "space-between",
          alignItems: {
            xs: "flex-start",
            sm: "center",
          },
          gap: 2,
          mb: 4,
        }}
      >
        <Box>
          <Typography
            variant="h4"
            component="h1"
            fontWeight={700}
          >
            Super Admin Dashboard
          </Typography>

          <Typography
            variant="body1"
            color="text.secondary"
            sx={{ mt: 0.5 }}
          >
            System-wide overview of TaskFlow.
          </Typography>
        </Box>

        <Button
          variant="contained"
          onClick={downloadReport}
          disabled={isDownloading}
        >
          {isDownloading ? (
            <>
              <CircularProgress
                size={18}
                color="inherit"
                sx={{ mr: 1 }}
              />
              Downloading...
            </>
          ) : (
            "Download Report"
          )}
        </Button>
      </Box>

      {/* ===================================================
          METRIC LOADING
      =================================================== */}

      {metricsLoading && (
        <Box
          sx={{
            display: "flex",
            justifyContent: "center",
            py: 4,
          }}
        >
          <CircularProgress />
        </Box>
      )}

      {/* ===================================================
          METRIC ERROR
      =================================================== */}

      {metricsError && (
        <Alert severity="error" sx={{ mb: 3 }}>
          Failed to load dashboard metrics.
        </Alert>
      )}

      {/* ===================================================
          METRIC CARDS
      =================================================== */}

      {metrics && (
        <Grid container spacing={3} sx={{ mb: 5 }}>
          {metricCards.map(({ key, label }) => (
            <Grid
              item
              xs={12}
              sm={6}
              md={4}
              lg={2}
              key={key}
            >
              <Card
                sx={{
                  height: "100%",
                  transition:
                    "transform 0.2s ease, box-shadow 0.2s ease",

                  "&:hover": {
                    transform: "translateY(-2px)",
                    boxShadow: 4,
                  },
                }}
              >
                <CardContent>
                  <Box
                    sx={{
                      display: "flex",
                      alignItems: "center",
                      gap: 1.5,
                      mb: 2,
                    }}
                  >
                    <Box
                      sx={{
                        width: 42,
                        height: 42,
                        borderRadius: 2,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        bgcolor: "action.hover",
                        color: "primary.main",
                      }}
                    >
                      {iconMap[key]}
                    </Box>

                    <Typography
                      variant="body2"
                      color="text.secondary"
                      fontWeight={500}
                    >
                      {label}
                    </Typography>
                  </Box>

                  <Typography
                    variant="h4"
                    component="div"
                    fontWeight={700}
                  >
                    {metrics[key]}
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      )}

      {/* ===================================================
          ANALYTICS HEADER
      =================================================== */}

      <Box
        sx={{
          display: "flex",
          flexDirection: {
            xs: "column",
            sm: "row",
          },
          justifyContent: "space-between",
          alignItems: {
            xs: "flex-start",
            sm: "center",
          },
          gap: 2,
          mb: 3,
        }}
      >
        <Box>
          <Typography
            variant="h5"
            component="h2"
            fontWeight={700}
          >
            Platform Analytics
          </Typography>

          <Typography
            variant="body2"
            color="text.secondary"
          >
            Monitor platform growth and task activity.
          </Typography>
        </Box>

        <Box
          sx={{
            display: "flex",
            flexWrap: "wrap",
            gap: 1,
          }}
        >
          <Button
            size="small"
            variant="outlined"
            onClick={() => setDate(7)}
          >
            7 Days
          </Button>

          <Button
            size="small"
            variant="outlined"
            onClick={() => setDate(30)}
          >
            30 Days
          </Button>

          <Button
            size="small"
            variant="outlined"
            onClick={() => setDate(90)}
          >
            90 Days
          </Button>
        </Box>
      </Box>

      {/* ===================================================
          ANALYTICS LOADING
      =================================================== */}

      {analyticsLoading && (
        <Box
          sx={{
            display: "flex",
            justifyContent: "center",
            py: 6,
          }}
        >
          <CircularProgress />
        </Box>
      )}

      {/* ===================================================
          ANALYTICS ERROR
      =================================================== */}

      {analyticsError && (
        <Alert severity="error" sx={{ mb: 3 }}>
          Failed to load analytics data.
        </Alert>
      )}

      {/* ===================================================
          CHARTS
      =================================================== */}

      {analytics && (
        <Grid container spacing={3}>
          {/* USER GROWTH */}

          <Grid item xs={12} lg={6}>
            <Card sx={{ height: "100%" }}>
              <CardContent>
                <Typography
                  variant="h6"
                  fontWeight={600}
                  sx={{ mb: 3 }}
                >
                  User Growth
                </Typography>

                <Box sx={{ width: "100%", height: 300 }}>
                  <ResponsiveContainer
                    width="100%"
                    height="100%"
                  >
                    <LineChart data={analytics.userGrowth}>
                      <CartesianGrid
                        strokeDasharray="3 3"
                        opacity={0.25}
                      />

                      <XAxis dataKey="date" />

                      <YAxis allowDecimals={false} />

                      <Tooltip />

                      <Legend />

                      <Line
                        type="monotone"
                        dataKey="users"
                        stroke="currentColor"
                        strokeWidth={2}
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
                <Typography
                  variant="h6"
                  fontWeight={600}
                  sx={{ mb: 3 }}
                >
                  Project Growth
                </Typography>

                <Box sx={{ width: "100%", height: 300 }}>
                  <ResponsiveContainer
                    width="100%"
                    height="100%"
                  >
                    <LineChart data={analytics.projectGrowth}>
                      <CartesianGrid
                        strokeDasharray="3 3"
                        opacity={0.25}
                      />

                      <XAxis dataKey="date" />

                      <YAxis allowDecimals={false} />

                      <Tooltip />

                      <Legend />

                      <Line
                        type="monotone"
                        dataKey="projects"
                        stroke="currentColor"
                        strokeWidth={2}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </Box>
              </CardContent>
            </Card>
          </Grid>

          {/* TASK STATUS */}

          <Grid item xs={12} lg={6}>
            <Card sx={{ height: "100%" }}>
              <CardContent>
                <Typography
                  variant="h6"
                  fontWeight={600}
                  sx={{ mb: 3 }}
                >
                  Tasks by Status
                </Typography>

                <Box sx={{ width: "100%", height: 300 }}>
                  <ResponsiveContainer
                    width="100%"
                    height="100%"
                  >
                    <BarChart data={analytics.tasksByStatus}>
                      <CartesianGrid
                        strokeDasharray="3 3"
                        opacity={0.25}
                      />

                      <XAxis dataKey="status" />

                      <YAxis allowDecimals={false} />

                      <Tooltip />

                      <Legend />

                      <Bar
                        dataKey="count"
                        fill="currentColor"
                      />
                    </BarChart>
                  </ResponsiveContainer>
                </Box>
              </CardContent>
            </Card>
          </Grid>

          {/* TASK PRIORITY */}

          <Grid item xs={12} lg={6}>
            <Card sx={{ height: "100%" }}>
              <CardContent>
                <Typography
                  variant="h6"
                  fontWeight={600}
                  sx={{ mb: 3 }}
                >
                  Tasks by Priority
                </Typography>

                <Box sx={{ width: "100%", height: 300 }}>
                  <ResponsiveContainer
                    width="100%"
                    height="100%"
                  >
                    <BarChart data={analytics.tasksByPriority}>
                      <CartesianGrid
                        strokeDasharray="3 3"
                        opacity={0.25}
                      />

                      <XAxis dataKey="priority" />

                      <YAxis allowDecimals={false} />

                      <Tooltip />

                      <Legend />

                      <Bar
                        dataKey="count"
                        fill="currentColor"
                      />
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

export default AdminDashboard;