import { useState } from "react";
import { Box, Typography, Button, CircularProgress, Alert } from "@mui/material";
import { ArrowDownToLine, Building2, Clock3, FileBarChart2, FileSpreadsheet, FolderKanban, ListChecks, FileText, Users } from "lucide-react";
import { api } from "./api";
import "./admin-overview.css";

function reportFilename(contentDisposition?: string, fallback?: string): string {
  const encoded = contentDisposition?.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
  const plain = contentDisposition?.match(/filename\s*=\s*"?([^";]+)"?/i)?.[1];
  let candidate = plain;
  if (encoded) {
    try { candidate = decodeURIComponent(encoded); } catch { candidate = plain; }
  }
  const safeCandidate = candidate?.split(/[\\/]/).pop()?.replace(/[\r\n"]/g, "").trim();
  return safeCandidate || fallback || `taskflow-report-${new Date().toISOString().replace(/[:.]/g, "-")}.csv`;
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
  const [format, setFormat] = useState<"pdf" | "xlsx" | "csv">("pdf");

  const reportFormats = [
    { id: "pdf" as const, label: "PDF report", badge: "PDF", icon: FileText, description: "A presentation-ready overview with platform totals, task status chart, project progress, generated time, and report ID." },
    { id: "xlsx" as const, label: "Excel workbook", badge: "XLSX", icon: FileSpreadsheet, description: "A Summary sheet and filterable Data sheet with frozen headers, project and task details, and dates." },
    { id: "csv" as const, label: "Raw data", badge: "CSV", icon: FileBarChart2, description: "Clean rows for users, organizations, projects, and tasks for importing into other tools." },
  ];

  const downloadReport = async () => {
    setIsDownloading(true);
    setError(null);
    setSuccess(null);
    try {
      const response = await api.get("/admin/reports", { params: { format }, responseType: "blob" });
      const mime = format === "pdf" ? "application/pdf" : format === "xlsx" ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" : "text/csv;charset=utf-8";
      const blob = new Blob([response.data], { type: mime });
      if (blob.size === 0) throw new Error("The report response was empty. Please try again.");
      const fallback = `taskflow-platform-report-${new Date().toISOString().replace(/[:.]/g, "-")}.${format}`;
      const filename = reportFilename(response.headers["content-disposition"], fallback);
      const downloadUrl = window.URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = downloadUrl;
      link.setAttribute("download", filename);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.setTimeout(() => window.URL.revokeObjectURL(downloadUrl), 1000);
      setSuccess(`Download started: ${filename} (${fileSizeLabel(blob.size)}). It includes all available platform records; no date filters are applied.`);
    } catch (err) {
      setError(err instanceof Error && err.message.includes("response was empty") ? err.message : "Failed to download report. Please try again.");
      console.error("Report download failed:", err);
    } finally {
      setIsDownloading(false);
    }
  };

  return (
    <Box className="admin-platform-page admin-reports-page">
      <header className="admin-platform-page-header"><div><Typography component="h1">Reports</Typography><p>Choose a format for a current snapshot of platform users, organizations, projects, and tasks.</p></div></header>
      <section className="admin-report-format-grid" aria-label="Choose report format">
        {reportFormats.map(({ id, label, badge, icon: Icon, description }) => <button key={id} type="button"
          className={`admin-report-format-option${format === id ? " is-selected" : ""}`}
          aria-pressed={format === id} onClick={() => { setFormat(id); setError(null); setSuccess(null); }}>
          <span className="admin-report-format-icon"><Icon size={19}/></span>
          <span className="admin-report-format-copy"><strong>{label}</strong><small>{description}</small></span>
          <span className="admin-report-format-badge">{badge}</span>
        </button>)}
      </section>
      <section className="admin-report-card">
        <span className="admin-report-icon"><FileBarChart2 size={20}/></span>
        <div className="admin-report-copy"><span className="admin-report-eyebrow">FULL PLATFORM SNAPSHOT</span><h2>{reportFormats.find(item => item.id === format)?.label}</h2><p>Generated on request with a unique report ID. No date or section filters are currently applied.</p></div>
        <Button className="admin-report-download" variant="contained" onClick={downloadReport} disabled={isDownloading} startIcon={isDownloading ? <CircularProgress size={15} color="inherit"/> : <ArrowDownToLine size={16}/>}>{isDownloading ? "Preparing" : `Download ${format.toUpperCase()}`}</Button>
      </section>
      <section className="admin-report-scope" aria-labelledby="admin-report-scope-title">
        <div className="admin-report-scope-heading"><div><h2 id="admin-report-scope-title">Report contents</h2><p>All formats are generated from current platform data and include a UTC generation timestamp.</p></div><span className="admin-report-scope-note"><Clock3 size={14}/> Generated on request</span></div>
        <div className="admin-report-sections">
          {([[Users, "Users"], [Building2, "Organizations"], [FolderKanban, "Projects"], [ListChecks, "Tasks"]] as const).map(([Icon, label]) => <span key={label}><Icon size={15}/>{label}</span>)}
        </div>
        <p className="admin-report-privacy-note">Excel and CSV include user account names and email addresses. Handle those exports as sensitive account data. The PDF summarizes platform totals and project progress.</p>
      </section>
      {error && <Alert severity="error" className="admin-report-message" role="alert">{error}</Alert>}
      {success && <Alert severity="success" className="admin-report-message" role="status">{success}</Alert>}
    </Box>
  );
};

export default AdminReports;
