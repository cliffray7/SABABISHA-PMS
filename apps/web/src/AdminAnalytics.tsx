import { useQuery } from "@tanstack/react-query";
import { api } from "./api";
import { Box, Card, CardContent, Grid, Typography, Button, ButtonGroup } from "@mui/material";
import { Bar, BarChart, CartesianGrid, Legend, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { useState } from "react";
import { subDays } from "date-fns";

const AdminAnalytics = () => {
    const [dateRange, setDateRange] = useState({ from: subDays(new Date(), 30), to: new Date() });

    const { data, error, isLoading } = useQuery({
        queryKey: ["adminAnalytics", dateRange],
        queryFn: () => api.get(`/admin/analytics?from=${dateRange.from.toISOString()}&to=${dateRange.to.toISOString()}`).then((res) => res.data),
    });

    const setDate = (days: number) => {
        setDateRange({ from: subDays(new Date(), days), to: new Date() });
    };

    if (isLoading) {
        return <Typography>Loading...</Typography>;
    }

    if (error) {
        return <Typography>Error loading analytics data.</Typography>;
    }

    return (
        <Box sx={{ flexGrow: 1 }}>
            <Typography variant="h4" gutterBottom>
                Analytics
            </Typography>
            <ButtonGroup variant="outlined" aria-label="outlined button group">
                <Button onClick={() => setDate(7)}>Last 7 days</Button>
                <Button onClick={() => setDate(30)}>Last 30 days</Button>
                <Button onClick={() => setDate(90)}>Last 90 days</Button>
            </ButtonGroup>
            <Grid container spacing={3} sx={{ mt: 2 }}>
                <Grid item xs={12} md={6}>
                    <Card>
                        <CardContent>
                            <Typography variant="h6">User Growth</Typography>
                            <ResponsiveContainer width="100%" height={300}>
                                <LineChart data={data.userGrowth}>
                                    <CartesianGrid strokeDasharray="3 3" />
                                    <XAxis dataKey="date" />
                                    <YAxis />
                                    <Tooltip />
                                    <Legend />
                                    <Line type="monotone" dataKey="users" stroke="#8884d8" />
                                </LineChart>
                            </ResponsiveContainer>
                        </CardContent>
                    </Card>
                </Grid>
                <Grid item xs={12} md={6}>
                    <Card>
                        <CardContent>
                            <Typography variant="h6">Projects Created</Typography>
                            <ResponsiveContainer width="100%" height={300}>
                                <LineChart data={data.projectGrowth}>
                                    <CartesianGrid strokeDasharray="3 3" />
                                    <XAxis dataKey="date" />
                                    <YAxis />
                                    <Tooltip />
                                    <Legend />
                                    <Line type="monotone" dataKey="projects" stroke="#82ca9d" />
                                </LineChart>
                            </ResponsiveContainer>
                        </CardContent>
                    </Card>
                </Grid>
                <Grid item xs={12} md={6}>
                    <Card>
                        <CardContent>
                            <Typography variant="h6">Tasks by Status</Typography>
                            <ResponsiveContainer width="100%" height={300}>
                                <BarChart data={data.tasksByStatus}>
                                    <CartesianGrid strokeDasharray="3 3" />
                                    <XAxis dataKey="status" />
                                    <YAxis />
                                    <Tooltip />
                                    <Legend />
                                    <Bar dataKey="count" fill="#8884d8" />
                                </BarChart>
                            </ResponsiveContainer>
                        </CardContent>
                    </Card>
                </Grid>
                <Grid item xs={12} md={6}>
                    <Card>
                        <CardContent>
                            <Typography variant="h6">Tasks by Priority</Typography>
                            <ResponsiveContainer width="100%" height={300}>
                                <BarChart data={data.tasksByPriority}>
                                    <CartesianGrid strokeDasharray="3 3" />
                                    <XAxis dataKey="priority" />
                                    <YAxis />
                                    <Tooltip />
                                    <Legend />
                                    <Bar dataKey="count" fill="#82ca9d" />
                                </BarChart>
                            </ResponsiveContainer>
                        </CardContent>
                    </Card>
                </Grid>
            </Grid>
        </Box>
    );
};

export default AdminAnalytics;