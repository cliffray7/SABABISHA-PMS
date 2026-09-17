import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts";
import { ProjectGrowthPoint } from "./types/admin";

interface ProjectGrowthChartProps {
  data: ProjectGrowthPoint[];
}

const ProjectGrowthChart = ({ data }: ProjectGrowthChartProps) => (
  <ResponsiveContainer width="100%" height={400}>
    <LineChart data={data}>
      <CartesianGrid strokeDasharray="3 3" />
      <XAxis dataKey="date" />
      <YAxis />
      <Tooltip />
      <Legend />
      <Line type="monotone" dataKey="projects" stroke="#82ca9d" />
    </LineChart>
  </ResponsiveContainer>
);

export default ProjectGrowthChart;