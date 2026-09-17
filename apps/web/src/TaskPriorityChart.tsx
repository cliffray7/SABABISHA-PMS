import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts";
import { TaskPriorityPoint } from "./types/admin";

interface TaskPriorityChartProps {
  data: TaskPriorityPoint[];
}

const TaskPriorityChart = ({ data }: TaskPriorityChartProps) => (
  <ResponsiveContainer width="100%" height={400}>
    <BarChart data={data}>
      <CartesianGrid strokeDasharray="3 3" />
      <XAxis dataKey="priority" />
      <YAxis />
      <Tooltip />
      <Legend />
      <Bar dataKey="count" fill="#82ca9d" />
    </BarChart>
  </ResponsiveContainer>
);

export default TaskPriorityChart;