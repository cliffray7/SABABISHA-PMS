import { Box, Button, Typography } from "@mui/material";
import { api } from "./api";

type ReportFormat = "csv" | "pdf";

const AdminReports = () => {
    const downloadReport = (format: ReportFormat) => {
        api.get(`/admin/reports?format=${format}`, { responseType: 'blob' })
            .then(response => {
                const url = window.URL.createObjectURL(new Blob([response.data]));
                const link = document.createElement('a');
                link.href = url;
                link.setAttribute('download', `report.${format}`);
                document.body.appendChild(link);
                link.click();
            });
    };

    return (
        <Box>
            <Typography variant="h4" gutterBottom>
                Reports
            </Typography>
            <Typography variant="body1" gutterBottom>
                Download a report of all data in the format of your choice.
            </Typography>
            <Box sx={{ mt: 2 }}>
                <Button variant="contained" onClick={() => downloadReport('csv')}>Download CSV</Button>
                <Button variant="contained" sx={{ ml: 2 }} onClick={() => downloadReport('pdf')}>Download PDF</Button>
            </Box>
        </Box>
    );
};

export default AdminReports;