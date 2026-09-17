import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts";
import { UserGrowthPoint } from "./types/admin";

interface UserGrowthChartProps {
  data: UserGrowthPoint[];
}

const UserGrowthChart = ({ data }: UserGrowthChartProps) => (
  <ResponsiveContainer width="100%" height={400}>
    <LineChart data={data}>
      <CartesianGrid strokeDasharray="3 3" />
      <XAxis dataKey="date" />
      <YAxis />
      <Tooltip />
      <Legend />
      <Line type="monotone" dataKey="users" stroke="#8884d8" />
    </LineChart>
  </ResponsiveContainer>
);

export default UserGrowthChart;