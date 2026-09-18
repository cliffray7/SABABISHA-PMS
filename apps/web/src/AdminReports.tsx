import { useState } from "react";
import { Box, Typography, Button, CircularProgress, Alert } from "@mui/material";
import { api } from "./api";

const AdminReports = () => {
  const [isDownloading, setIsDownloading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const downloadReport = async () => {
    setIsDownloading(true);
    setError(null);
    setSuccess(null);
    try {
      const response = await api.get("/admin/reports", { params: { format: "csv" }, responseType: "blob" });
      const url = window.URL.createObjectURL(new Blob([response.data], { type: "text/csv;charset=utf-8" }));
      const link = document.createElement("a");
      link.href = url;
      link.setAttribute("download", `taskflow-report-${new Date().toISOString().split('T')[0]}.csv`);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
      setSuccess("Your system report download has started.");
    } catch (err) {
      setError("Failed to download report. Please try again.");
      console.error("Report download failed:", err);
    } finally {
      setIsDownloading(false);
    }
  };

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h4" component="h1" sx={{ mb: 1 }}>Reports</Typography>
      <Typography variant="body1" sx={{ mb: 3 }}>
        Generate and export system-wide TaskFlow reports.
      </Typography>
      <Box sx={{ display: "flex", alignItems: "center", gap: 2 }}><Typography variant="h6">System Report</Typography><Button variant="contained" onClick={downloadReport} disabled={isDownloading}>{isDownloading ? <CircularProgress size={24} color="inherit" /> : "Download CSV"}</Button></Box>
      {error && <Alert severity="error" sx={{ mt: 2 }}>{error}</Alert>}
      {success && <Alert severity="success" sx={{ mt: 2 }}>{success}</Alert>}
    </Box>
  );
};

export default AdminReports;
