import { useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { format } from "date-fns";
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

import { api } from "./api";
import { AdminDashboardMetrics } from "./types/admin";

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
  { key: "totalUsers",         label: "Total Users" },
  { key: "totalOrganizations", label: "Total Organizations" },
  { key: "totalProjects",      label: "Total Projects" },
  { key: "totalTasks",         label: "Total Tasks" },
  { key: "completedTasks",     label: "Completed Tasks" },
  { key: "activeProjects",     label: "Active Projects" },
];

const iconMap: Record<MetricKey, ReactNode> = {
  totalUsers:         <Users size={22} />,
  totalOrganizations: <Briefcase size={22} />,
  totalProjects:      <FolderKanban size={22} />,
  totalTasks:         <ListChecks size={22} />,
  completedTasks:     <CheckCircle size={22} />,
  activeProjects:     <Activity size={22} />,
};

/* =========================================================
   COMPONENT
========================================================= */

const AdminDashboard = () => {
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
      const response = await api.get<AdminDashboardMetrics>("/admin/dashboard");
      return response.data;
    },
    refetchInterval: 30_000, // refresh every 30 seconds
  });

  /* =======================================================
     REPORT DOWNLOAD
  ======================================================= */

  const downloadReport = async () => {
    setIsDownloading(true);
    try {
      const response = await api.get("/admin/reports", {
        params: { format: "csv" },
        responseType: "blob",
      });
      const url = window.URL.createObjectURL(
        new Blob([response.data], { type: "text/csv;charset=utf-8" }),
      );
      const link = document.createElement("a");
      link.href = url;
      link.download = `taskflow-report-${format(new Date(), "yyyy-MM-dd")}.csv`;
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
          flexDirection: { xs: "column", sm: "row" },
          justifyContent: "space-between",
          alignItems: { xs: "flex-start", sm: "center" },
          gap: 2,
          mb: 4,
        }}
      >
        <Box>
          <Typography variant="h4" component="h1" fontWeight={700}>
            Super Admin Dashboard
          </Typography>
          <Typography variant="body1" color="text.secondary" sx={{ mt: 0.5 }}>
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
              <CircularProgress size={18} color="inherit" sx={{ mr: 1 }} />
              Downloading…
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
        <Box sx={{ display: "flex", justifyContent: "center", py: 4 }}>
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
        <Grid container spacing={3}>
          {metricCards.map(({ key, label }) => (
            <Grid item xs={12} sm={6} md={4} lg={2} key={key}>
              <Card
                sx={{
                  height: "100%",
                  transition: "transform 0.2s ease, box-shadow 0.2s ease",
                  "&:hover": { transform: "translateY(-2px)", boxShadow: 4 },
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

                  <Typography variant="h4" component="div" fontWeight={700}>
                    {metrics[key]}
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      )}

      {/* ===================================================
          HINT — direct user to the Analytics nav item
      =================================================== */}

      {metrics && (
        <Typography
          variant="body2"
          color="text.secondary"
          sx={{ mt: 4 }}
        >
          For charts and growth trends, open <strong>Analytics</strong> in the
          sidebar. Metrics refresh every 30 seconds.
        </Typography>
      )}
    </Box>
  );
};

export default AdminDashboard;
