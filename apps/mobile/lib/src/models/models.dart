// ─── Auth ────────────────────────────────────────────────────────────────────

class LoginChallenge {
  const LoginChallenge({required this.email});
  final String email;
  factory LoginChallenge.fromJson(Map<String, dynamic> json) =>
      LoginChallenge(email: json['email'] as String);
}

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
  });
  final String userId;
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        userId: json['userId'] as String,
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessTokenExpiresAt:
            DateTime.parse(json['accessTokenExpiresAt'] as String),
      );
}

class Account {
  const Account({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.timezone = 'UTC',
  });
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String timezone;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String? ?? '',
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        email: json['email'] as String,
        timezone: json['timezone'] as String? ?? 'UTC',
      );
}

// ─── Organization ────────────────────────────────────────────────────────────

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.slug,
    required this.role,
  });
  final String id;
  final String name;
  final String slug;
  final String role;

  bool get isAdminOrOwner => role == 'OWNER' || role == 'ADMIN';

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String? ?? '',
        role: json['role'] as String? ?? 'MEMBER',
      );
}

// ─── Project ─────────────────────────────────────────────────────────────────

class Project {
  const Project({
    required this.id,
    required this.organizationId,
    required this.name,
    this.description,
    required this.status,
    this.startDate,
    this.dueDate,
    required this.role,
  });
  final String id;
  final String organizationId;
  final String name;
  final String? description;
  final String status;
  final String? startDate;
  final String? dueDate;
  final String role;

  bool get isManagerOrLead =>
      role == 'PROJECT_MANAGER' || role == 'TEAM_LEAD';
  bool get canWrite => role != 'VIEWER';

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        status: json['status'] as String? ?? 'ACTIVE',
        startDate: json['startDate'] as String?,
        dueDate: json['dueDate'] as String?,
        role: json['role'] as String? ?? 'CONTRIBUTOR',
      );
}

// ─── Task ────────────────────────────────────────────────────────────────────

class Task {
  const Task({
    required this.id,
    required this.projectId,
    this.parentTaskId,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    this.startDate,
    this.dueDate,
    this.completedAt,
    required this.assigneeIds,
    this.subtaskCount = 0,
    this.completedSubtaskCount = 0,
  });

  final String id;
  final String projectId;
  final String? parentTaskId;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? startDate;
  final String? dueDate;
  final String? completedAt;
  final List<String> assigneeIds;
  final int subtaskCount;
  final int completedSubtaskCount;

  bool get isOverdue {
    if (dueDate == null || status == 'DONE') return false;
    final due = DateTime.tryParse(dueDate!);
    return due != null && due.isBefore(DateTime.now());
  }

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        parentTaskId: json['parentTaskId'] as String?,
        title: json['title'] as String,
        description: json['description'] as String?,
        status: json['status'] as String? ?? 'TO DO',
        priority: json['priority'] as String? ?? 'MEDIUM',
        startDate: json['startDate'] as String?,
        dueDate: json['dueDate'] as String?,
        completedAt: json['completedAt'] as String?,
        assigneeIds: (json['assigneeIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        subtaskCount: json['subtaskCount'] as int? ?? 0,
        completedSubtaskCount: json['completedSubtaskCount'] as int? ?? 0,
      );
}

// ─── Subtask ─────────────────────────────────────────────────────────────────

class Subtask {
  const Subtask({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });
  final String id;
  final String title;
  final String status;
  final String createdAt;
  final String? completedAt;

  bool get isDone => status == 'DONE';

  factory Subtask.fromJson(Map<String, dynamic> json) => Subtask(
        id: json['id'] as String,
        title: json['title'] as String,
        status: json['status'] as String? ?? 'TO DO',
        createdAt: json['createdAt'] as String,
        completedAt: json['completedAt'] as String?,
      );
}

// ─── Member ──────────────────────────────────────────────────────────────────

class Member {
  const Member({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
  });
  final String id;
  final String userId;
  final String firstName;
  final String lastName;
  final String email;
  final String role;

  String get initials =>
      (firstName.isNotEmpty ? firstName[0] : '') +
      (lastName.isNotEmpty ? lastName[0] : '');
  String get fullName => '$firstName $lastName';

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String? ?? json['userId'] as String,
        userId: json['userId'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        email: json['email'] as String,
        role: json['role'] as String? ?? 'MEMBER',
      );
}

// ─── Invitation ──────────────────────────────────────────────────────────────

class Invitation {
  const Invitation({
    required this.id,
    required this.email,
    required this.role,
    required this.expiresAt,
  });
  final String id;
  final String email;
  final String role;
  final String expiresAt;

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        expiresAt: json['expiresAt'] as String,
      );
}

// ─── Notification ────────────────────────────────────────────────────────────

class Notice {
  const Notice({
    required this.id,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.relatedId,
    this.projectId,
  });
  final String id;
  final String message;
  final bool isRead;
  final String createdAt;
  final String? relatedId;
  final String? projectId;

  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
        id: json['id'] as String,
        message: json['message'] as String,
        isRead: json['isRead'] as bool? ?? false,
        createdAt: json['createdAt'] as String,
        relatedId: json['relatedId'] as String?,
        projectId: json['projectId'] as String?,
      );
}

// ─── Comment ─────────────────────────────────────────────────────────────────

class Comment {
  const Comment({
    required this.id,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.parentCommentId,
  });
  final String id;
  final String content;
  final String authorId;
  final String authorName;
  final String createdAt;
  final String? parentCommentId;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String,
        content: json['content'] as String,
        authorId: json['userId'] as String? ?? '',
        authorName: json['author'] as String? ?? '',
        createdAt: json['createdAt'] as String,
        parentCommentId: json['parentCommentId'] as String?,
      );
}

// ─── Attachment ──────────────────────────────────────────────────────────────

class Attachment {
  const Attachment({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.contentType,
    required this.createdAt,
  });
  final String id;
  final String fileName;
  final int fileSize;
  final String contentType;
  final String createdAt;

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int? ?? 0,
        contentType: json['contentType'] as String? ?? '',
        createdAt: json['createdAt'] as String,
      );
}

// ─── Dashboard Metrics ───────────────────────────────────────────────────────

class DashboardMetrics {
  const DashboardMetrics({
    required this.myTasks,
    required this.overdueTasks,
    required this.completedTasks,
    required this.inProgressTasks,
    required this.totalTasks,
  });
  final int myTasks;
  final int overdueTasks;
  final int completedTasks;
  final int inProgressTasks;
  final int totalTasks;

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) =>
      DashboardMetrics(
        myTasks: json['myTasks'] as int? ?? 0,
        overdueTasks: json['overdueTasks'] as int? ?? 0,
        completedTasks: json['completedTasks'] as int? ?? 0,
        inProgressTasks: json['inProgressTasks'] as int? ?? 0,
        totalTasks: json['totalTasks'] as int? ?? 0,
      );
}

// ─── Constants ───────────────────────────────────────────────────────────────

const taskStatuses = ['TO DO', 'IN PROGRESS', 'REVIEW', 'DONE'];
const taskPriorities = ['URGENT', 'HIGH', 'MEDIUM', 'LOW'];
const orgRoles = ['ADMIN', 'MEMBER', 'GUEST'];
const projectRoles = ['PROJECT_MANAGER', 'TEAM_LEAD', 'CONTRIBUTOR', 'VIEWER'];
const projectStatuses = ['PLANNING', 'ACTIVE', 'ON_HOLD', 'COMPLETED'];
