export interface AdminDashboardMetrics {
  totalUsers: number;
  totalOrganizations: number;
  totalProjects: number;
  totalTasks: number;
  completedTasks: number;
  activeProjects: number;
}

export interface UserGrowthPoint {
  date: string;
  users: number;
}

export interface ProjectGrowthPoint {
  date:string;
  projects: number;
}

export interface TaskStatusPoint {
  status: string;
  count: number;
}

export interface TaskPriorityPoint {
  priority: string;
  count: number;
}

export interface AdminAnalyticsResponse {
  userGrowth: UserGrowthPoint[];
  projectGrowth: ProjectGrowthPoint[];
  tasksByStatus: TaskStatusPoint[];
  tasksByPriority: TaskPriorityPoint[];
}