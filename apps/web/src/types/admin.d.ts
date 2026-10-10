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
export interface AdminProject { id:string; organizationId:string; name:string; organizationName:string | null; status:string; taskCount:number; createdAt:string; dueDate:string | null; archivedAt:string | null; deletedAt:string | null; }
export interface AdminProjectDetails { projectId:string; name:string; description:string | null; status:string; organizationId:string; organizationName:string; ownerName:string | null; startDate:string | null; dueDate:string | null; createdAt:string; archivedAt:string | null; deletedAt:string | null; memberCount:number; hasTasks:boolean; totalEligibleTasks:number; completedTasks:number; progressPercent:number | null; outstandingTaskCount:number; overdueTaskCount:number; timezoneIdUsed:string; }
export interface AdminProjectMember { displayName:string; projectRole:string; projectMembershipStatus:string; organizationMembershipStatus:string | null; accountStatus:string; joinedAt:string; }
export interface AdminProjectTask { id:string; title:string; status:string; priority:string; dueDate:string | null; createdAt:string; effectiveAssigneeCount:number; effectiveAssignees?:string[]; }
export interface AdminProjectPage<T> { items:T[]; page:number; pageSize:number; totalCount:number; }

export interface AdminCreateUserRequest {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
  timezone?: string;
}
