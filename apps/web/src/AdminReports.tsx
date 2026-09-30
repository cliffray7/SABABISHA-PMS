import { useState } from "react";
import { Box, Typography, Button, CircularProgress, Alert } from "@mui/material";
import { ArrowDownToLine, Building2, Clock3, FileBarChart2, FolderKanban, ListChecks, Users } from "lucide-react";
import { api } from "./api";

function reportFilename(contentDisposition?: string): string {
  const encoded = contentDisposition?.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
  const plain = contentDisposition?.match(/filename\s*=\s*"?([^";]+)"?/i)?.[1];
  let candidate = plain;
  if (encoded) {
    try { candidate = decodeURIComponent(encoded); } catch { candidate = plain; }
  }
  const safeCandidate = candidate?.split(/[\\/]/).pop()?.replace(/[\r\n"]/g, "").trim();
  return safeCandidate || `taskflow-report-${new Date().toISOString().replace(/[:.]/g, "-")}.csv`;
}

function fileSizeLabel(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

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
      const blob = new Blob([response.data], { type: "text/csv;charset=utf-8" });
      if (blob.size === 0) throw new Error("The report response was empty. Please try again.");
      const filename = reportFilename(response.headers["content-disposition"]);
      const downloadUrl = window.URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = downloadUrl;
      link.setAttribute("download", filename);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.setTimeout(() => window.URL.revokeObjectURL(downloadUrl), 1000);
      setSuccess(`Download started: ${filename} (${fileSizeLabel(blob.size)}). It includes all four data sections with no date or section filters applied.`);
    } catch (err) {
      setError(err instanceof Error && err.message.includes("response was empty") ? err.message : "Failed to download report. Please try again.");
      console.error("Report download failed:", err);
    } finally {
      setIsDownloading(false);
    }
  };

  return (
    <Box className="admin-platform-page admin-reports-page">
      <header className="admin-platform-page-header"><div><Typography component="h1">Reports</Typography><p>Export platform records as a CSV report.</p></div></header>
      <section className="admin-report-card">
        <span className="admin-report-icon"><FileBarChart2 size={20}/></span>
        <div className="admin-report-copy"><span className="admin-report-eyebrow">CURRENT DATA EXPORT</span><h2>Full platform report</h2><p>Includes all available users, organizations, projects, and tasks. Date and section filters are not available.</p></div>
        <span className="admin-report-format">CSV</span>
        <Button className="admin-report-download" variant="contained" onClick={downloadReport} disabled={isDownloading} startIcon={isDownloading ? <CircularProgress size={15} color="inherit"/> : <ArrowDownToLine size={16}/>}>{isDownloading ? "Preparing" : "Download report"}</Button>
      </section>
      <section className="admin-report-scope" aria-labelledby="admin-report-scope-title">
        <div className="admin-report-scope-heading"><div><h2 id="admin-report-scope-title">Report contents</h2><p>The CSV is generated when requested and includes a UTC generation timestamp.</p></div><span className="admin-report-scope-note"><Clock3 size={14}/> Generated on request</span></div>
        <div className="admin-report-sections">
          {([[Users, "Users"], [Building2, "Organizations"], [FolderKanban, "Projects"], [ListChecks, "Tasks"]] as const).map(([Icon, label]) => <span key={label}><Icon size={15}/>{label}</span>)}
        </div>
        <p className="admin-report-privacy-note">The user section contains account names and email addresses. Handle the downloaded CSV as sensitive account data.</p>
      </section>
      {error && <Alert severity="error" className="admin-report-message" role="alert">{error}</Alert>}
      {success && <Alert severity="success" className="admin-report-message" role="status">{success}</Alert>}
    </Box>
  );
};

export default AdminReports;
