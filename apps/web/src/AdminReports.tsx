import { useState } from "react";
import { Box, Typography, Button, CircularProgress, Alert } from "@mui/material";
import { api } from "./api";

const AdminReports = () => {
  const [isDownloading, setIsDownloading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const downloadReport = async () => {
    setIsDownloading(true);
    setError(null);
    try {
      const response = await api.get("/admin/reports?format=csv", { responseType: "blob" });
      const url = window.URL.createObjectURL(new Blob([response.data]));
      const link = document.createElement("a");
      link.href = url;
      link.setAttribute("download", `taskflow-report-${new Date().toISOString().split('T')[0]}.csv`);
      document.body.appendChild(link);
      link.click();
      link.remove();
    } catch (err) {
      setError("Failed to download report. Please try again.");
      console.error("Report download failed:", err);
    } finally {
      setIsDownloading(false);
    }
  };

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h4" sx={{ mb: 2 }}>System Reports</Typography>
      <Typography variant="body1" sx={{ mb: 3 }}>
        Generate a system-wide report containing all users, organizations, projects, and tasks.
      </Typography>
      <Button variant="contained" onClick={downloadReport} disabled={isDownloading}>
        {isDownloading ? <CircularProgress size={24} /> : "Download CSV Report"}
      </Button>
      {error && <Alert severity="error" sx={{ mt: 2 }}>{error}</Alert>}
    </Box>
  );
};

export default AdminReports;