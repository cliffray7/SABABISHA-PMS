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

export interface AdminUser { id:string; firstName:string; lastName:string; email:string; status:string; createdAt:string; organizationCount:number; }
export interface AdminOrganization { id:string; name:string; slug:string; owner:string | null; memberCount:number; projectCount:number; createdAt:string; }
export interface AdminProject { id:string; name:string; organizationName:string | null; status:string; taskCount:number; createdAt:string; dueDate:string | null; archivedAt:string | null; }
