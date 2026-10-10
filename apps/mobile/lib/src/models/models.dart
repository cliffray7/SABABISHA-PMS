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
    this.avatarUrl,
  });
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String timezone;
  final String? avatarUrl;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String? ?? '',
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        email: json['email'] as String,
        timezone: json['timezone'] as String? ?? 'UTC',
        avatarUrl: json['avatarUrl'] as String?,
      );
}

// ─── Organization ────────────────────────────────────────────────────────────

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.slug,
    required this.role,
    this.avatarUrl,
  });
  final String id;
  final String name;
  final String slug;
  final String role;
  final String? avatarUrl;

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

  bool get isManagerOrLead => role == 'PROJECT_MANAGER' || role == 'TEAM_LEAD';
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
    this.createdAt,
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
  final String? createdAt;
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
        createdAt: json['createdAt'] as String?,
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
    this.avatarUrl,
  });
  final String id;
  final String userId;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String? avatarUrl;

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
        avatarUrl: json['avatarUrl'] as String?,
      );
}

class MemberTaskResolution {
  const MemberTaskResolution({
    required this.taskId,
    required this.action,
    required this.replacementUserId,
  });

  final String taskId;
  final String action;
  final String? replacementUserId;

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'action': action,
        'replacementUserId': replacementUserId,
      };
}

class RemovalReplacementMember {
  const RemovalReplacementMember(
      {required this.userId, required this.displayName});
  final String userId;
  final String displayName;

  factory RemovalReplacementMember.fromJson(Map<String, dynamic> json) =>
      RemovalReplacementMember(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
      );
}

class RemovalTaskPreview {
  const RemovalTaskPreview({
    required this.taskId,
    required this.parentTaskId,
    required this.title,
    required this.status,
    required this.currentAssigneeIds,
    required this.requiredResolution,
  });
  final String taskId;
  final String? parentTaskId;
  final String title;
  final String status;
  final List<String> currentAssigneeIds;
  final String requiredResolution;

  factory RemovalTaskPreview.fromJson(Map<String, dynamic> json) =>
      RemovalTaskPreview(
        taskId: json['taskId'] as String,
        parentTaskId: json['parentTaskId'] as String?,
        title: json['title'] as String,
        status: json['status'] as String,
        currentAssigneeIds: (json['currentAssigneeIds'] as List<dynamic>)
            .map((id) => id as String)
            .toList(),
        requiredResolution: json['requiredResolution'] as String,
      );
}

class RemovalHistoricalAttribution {
  const RemovalHistoricalAttribution({
    required this.taskId,
    required this.status,
    required this.taskInTrash,
    required this.currentAssigneeIds,
    required this.actionOnConfirm,
  });
  final String taskId;
  final String status;
  final bool taskInTrash;
  final List<String> currentAssigneeIds;
  final String actionOnConfirm;

  factory RemovalHistoricalAttribution.fromJson(Map<String, dynamic> json) =>
      RemovalHistoricalAttribution(
        taskId: json['taskId'] as String,
        status: json['status'] as String,
        taskInTrash: json['taskInTrash'] as bool,
        currentAssigneeIds: (json['currentAssigneeIds'] as List<dynamic>)
            .map((id) => id as String)
            .toList(),
        actionOnConfirm: json['actionOnConfirm'] as String,
      );
}

class RemovalProjectPreview {
  const RemovalProjectPreview({
    required this.projectId,
    required this.lifecycle,
    required this.ownerTransferRequired,
    required this.managerInvariantBlocked,
    required this.eligibleReplacementMembers,
    required this.tasks,
    required this.historicalAttributionsToInactivate,
  });
  final String projectId;
  final String lifecycle;
  final bool ownerTransferRequired;
  final bool managerInvariantBlocked;
  final List<RemovalReplacementMember> eligibleReplacementMembers;
  final List<RemovalTaskPreview> tasks;
  final List<RemovalHistoricalAttribution> historicalAttributionsToInactivate;

  factory RemovalProjectPreview.fromJson(Map<String, dynamic> json) =>
      RemovalProjectPreview(
        projectId: json['projectId'] as String,
        lifecycle: json['lifecycle'] as String,
        ownerTransferRequired: json['ownerTransferRequired'] as bool,
        managerInvariantBlocked: json['managerInvariantBlocked'] as bool,
        eligibleReplacementMembers: (json['eligibleReplacementMembers']
                as List<dynamic>)
            .map((item) =>
                RemovalReplacementMember.fromJson(item as Map<String, dynamic>))
            .toList(),
        tasks: (json['tasks'] as List<dynamic>)
            .map((item) =>
                RemovalTaskPreview.fromJson(item as Map<String, dynamic>))
            .toList(),
        historicalAttributionsToInactivate:
            (json['historicalAttributionsToInactivate'] as List<dynamic>)
                .map((item) => RemovalHistoricalAttribution.fromJson(
                    item as Map<String, dynamic>))
                .toList(),
      );
}

class ExpiredTrashTaskPreview {
  const ExpiredTrashTaskPreview({
    required this.taskId,
    required this.status,
    required this.currentAssigneeIds,
    required this.actionOnConfirm,
  });
  final String taskId;
  final String status;
  final List<String> currentAssigneeIds;
  final String actionOnConfirm;

  factory ExpiredTrashTaskPreview.fromJson(Map<String, dynamic> json) =>
      ExpiredTrashTaskPreview(
        taskId: json['taskId'] as String,
        status: json['status'] as String,
        currentAssigneeIds: (json['currentAssigneeIds'] as List<dynamic>)
            .map((id) => id as String)
            .toList(),
        actionOnConfirm: json['actionOnConfirm'] as String,
      );
}

class ExpiredTrashProjectPreview {
  const ExpiredTrashProjectPreview({
    required this.projectId,
    required this.deletedAt,
    required this.lifecycle,
    required this.ownerManagerChecks,
    required this.tasks,
  });
  final String projectId;
  final String deletedAt;
  final String lifecycle;
  final String ownerManagerChecks;
  final List<ExpiredTrashTaskPreview> tasks;

  factory ExpiredTrashProjectPreview.fromJson(Map<String, dynamic> json) =>
      ExpiredTrashProjectPreview(
        projectId: json['projectId'] as String,
        deletedAt: json['deletedAt'] as String,
        lifecycle: json['lifecycle'] as String,
        ownerManagerChecks: json['ownerManagerChecks'] as String,
        tasks: (json['tasks'] as List<dynamic>)
            .map((item) =>
                ExpiredTrashTaskPreview.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class MemberRemovalPreview {
  const MemberRemovalPreview({
    required this.projectId,
    required this.organizationId,
    required this.memberId,
    required this.snapshotHash,
    required this.affectedTaskCount,
    required this.affectedProjects,
    required this.expiredTrashCleanup,
  });
  final String? projectId;
  final String organizationId;
  final String memberId;
  final String snapshotHash;
  final int affectedTaskCount;
  final List<RemovalProjectPreview> affectedProjects;
  final List<ExpiredTrashProjectPreview> expiredTrashCleanup;

  factory MemberRemovalPreview.fromJson(Map<String, dynamic> json) =>
      MemberRemovalPreview(
        projectId: json['projectId'] as String?,
        organizationId: json['organizationId'] as String,
        memberId: json['memberId'] as String,
        snapshotHash: json['snapshotHash'] as String,
        affectedTaskCount: json['affectedTaskCount'] as int,
        affectedProjects: (json['affectedProjects'] as List<dynamic>)
            .map((item) =>
                RemovalProjectPreview.fromJson(item as Map<String, dynamic>))
            .toList(),
        expiredTrashCleanup: (json['expiredTrashCleanup'] as List<dynamic>)
            .map((item) => ExpiredTrashProjectPreview.fromJson(
                item as Map<String, dynamic>))
            .toList(),
      );
}

class TrashItem {
  const TrashItem({
    required this.kind,
    required this.id,
    required this.projectId,
    required this.name,
    required this.deletedAt,
    this.parentId,
  });
  final String kind;
  final String id;
  final String? parentId;
  final String projectId;
  final String name;
  final DateTime deletedAt;

  factory TrashItem.fromJson(Map<String, dynamic> json) => TrashItem(
        kind: json['kind'] as String,
        id: json['id'] as String,
        parentId: json['parentId'] as String?,
        projectId: json['projectId'] as String,
        name: json['name'] as String,
        deletedAt: DateTime.parse(json['deletedAt'] as String),
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
    required this.uploadedBy,
    required this.fileName,
    required this.fileSize,
    required this.contentType,
    required this.createdAt,
  });
  final String id;
  final String uploadedBy;
  final String fileName;
  final int fileSize;
  final String contentType;
  final String createdAt;

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
    uploadedBy: json['uploadedBy'] as String? ?? '',
    fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int? ?? 0,
        contentType: json['contentType'] as String? ?? '',
        createdAt: json['createdAt'] as String,
      );
}

// ─── Dashboard Metrics ───────────────────────────────────────────────────────

class WorkspaceActivityPage {
  const WorkspaceActivityPage({required this.items, this.nextCursor});
  final List<Map<String, dynamic>> items;
  final String? nextCursor;

  factory WorkspaceActivityPage.fromJson(Map<String, dynamic> json) =>
      WorkspaceActivityPage(
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

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

class ProjectProgress {
  const ProjectProgress({
    required this.projectId,
    required this.projectStatus,
    required this.hasTasks,
    required this.totalEligibleTasks,
    required this.completedTasks,
    required this.progressPercent,
    required this.outstandingTaskCount,
    required this.overdueTaskCount,
    required this.timezoneIdUsed,
  });

  final String projectId;
  final String projectStatus;
  final bool hasTasks;
  final int totalEligibleTasks;
  final int completedTasks;
  final int? progressPercent;
  final int outstandingTaskCount;
  final int overdueTaskCount;
  final String timezoneIdUsed;

  factory ProjectProgress.fromJson(Map<String, dynamic> json) =>
      ProjectProgress(
        projectId: json['projectId'] as String,
        projectStatus: json['projectStatus'] as String,
        hasTasks: json['hasTasks'] as bool,
        totalEligibleTasks: json['totalEligibleTasks'] as int,
        completedTasks: json['completedTasks'] as int,
        progressPercent: json['progressPercent'] as int?,
        outstandingTaskCount: json['outstandingTaskCount'] as int,
        overdueTaskCount: json['overdueTaskCount'] as int,
        timezoneIdUsed: json['timezoneIdUsed'] as String,
      );
}

String projectStatusLabel(String status) => switch (status) {
      'PLANNING' => 'Planned',
      'ACTIVE' => 'In Progress',
      'ON_HOLD' => 'On Hold',
      'COMPLETED' => 'Completed',
      _ => _readableStatusFallback(status),
    };

String taskStatusLabel(String status) => switch (status) {
      'TO DO' => 'To Do',
      'IN PROGRESS' => 'In Progress',
      'REVIEW' => 'In Review',
      'DONE' => 'Done',
      _ => _readableStatusFallback(status),
    };

String _readableStatusFallback(String status) {
  final words =
      status.replaceAll('_', ' ').trim().toLowerCase().split(RegExp(r'\s+'));
  if (words.isEmpty || (words.length == 1 && words.single.isEmpty)) {
    return 'Unknown';
  }
  return words
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

// ─── Constants ───────────────────────────────────────────────────────────────

const taskStatuses = ['TO DO', 'IN PROGRESS', 'REVIEW', 'DONE'];
const taskPriorities = ['URGENT', 'HIGH', 'MEDIUM', 'LOW'];

class AiTaskSuggestion {
  const AiTaskSuggestion({
    required this.title,
    required this.description,
    required this.priority,
    required this.subtasks,
  });

  final String title;
  final String description;
  final String priority;
  final List<String> subtasks;

  factory AiTaskSuggestion.fromJson(Map<String, dynamic> json) =>
      AiTaskSuggestion(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        priority: json['priority'] as String? ?? 'MEDIUM',
        subtasks: (json['subtasks'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(),
      );
}

const orgRoles = ['ADMIN', 'MEMBER', 'GUEST'];
const projectRoles = ['PROJECT_MANAGER', 'TEAM_LEAD', 'CONTRIBUTOR', 'VIEWER'];
const projectStatuses = ['PLANNING', 'ACTIVE', 'ON_HOLD', 'COMPLETED'];

// ─── Admin Models ─────────────────────────────────────────────────────────────

class AdminDashboardMetrics {
  const AdminDashboardMetrics({
    required this.totalUsers,
    required this.totalOrganizations,
    required this.totalProjects,
    required this.totalTasks,
    required this.completedTasks,
    required this.activeProjects,
  });
  final int totalUsers;
  final int totalOrganizations;
  final int totalProjects;
  final int totalTasks;
  final int completedTasks;
  final int activeProjects;

  factory AdminDashboardMetrics.fromJson(Map<String, dynamic> json) =>
      AdminDashboardMetrics(
        totalUsers: json['totalUsers'] as int? ?? 0,
        totalOrganizations: json['totalOrganizations'] as int? ?? 0,
        totalProjects: json['totalProjects'] as int? ?? 0,
        totalTasks: json['totalTasks'] as int? ?? 0,
        completedTasks: json['completedTasks'] as int? ?? 0,
        activeProjects: json['activeProjects'] as int? ?? 0,
      );
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.status,
    required this.createdAt,
    required this.organizationCount,
  });
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String status;
  final String createdAt;
  final int organizationCount;

  String get fullName => '$firstName $lastName';
  bool get isActive => status == 'active';

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        email: json['email'] as String,
        status: json['status'] as String? ?? 'active',
        createdAt: json['createdAt'] as String,
        organizationCount: json['organizationCount'] as int? ?? 0,
      );
}

class AdminOrganization {
  const AdminOrganization({
    required this.id,
    required this.name,
    required this.slug,
    this.owner,
    required this.memberCount,
    required this.projectCount,
    required this.createdAt,
  });
  final String id;
  final String name;
  final String slug;
  final String? owner;
  final int memberCount;
  final int projectCount;
  final String createdAt;

  factory AdminOrganization.fromJson(Map<String, dynamic> json) =>
      AdminOrganization(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String? ?? '',
        owner: json['owner'] as String?,
        memberCount: json['memberCount'] as int? ?? 0,
        projectCount: json['projectCount'] as int? ?? 0,
        createdAt: json['createdAt'] as String,
      );
}

class AdminProject {
  const AdminProject({
    required this.id,
    required this.name,
    this.organizationId,
    this.organizationName,
    required this.status,
    required this.taskCount,
    required this.createdAt,
    this.dueDate,
    this.archivedAt,
    this.deletedAt,
  });
  final String id;
  final String name;
  final String? organizationId;
  final String? organizationName;
  final String status;
  final int taskCount;
  final String createdAt;
  final String? dueDate;
  final String? archivedAt;
  final String? deletedAt;

  bool get isArchived => archivedAt != null;
  bool get isTrashed => deletedAt != null;
  String get displayStatus =>
      isTrashed ? 'IN TRASH' : isArchived ? 'ARCHIVED' : status;

  factory AdminProject.fromJson(Map<String, dynamic> json) => AdminProject(
        id: json['id'] as String,
        name: json['name'] as String,
        organizationId: json['organizationId'] as String?,
        organizationName: json['organizationName'] as String?,
        status: json['status'] as String? ?? 'ACTIVE',
        taskCount: json['taskCount'] as int? ?? 0,
        createdAt: json['createdAt'] as String,
        dueDate: json['dueDate'] as String?,
        archivedAt: json['archivedAt'] as String?,
        deletedAt: json['deletedAt'] as String?,
      );
}

class AdminProjectDetails {
  const AdminProjectDetails({required this.projectId, required this.name,
    required this.organizationId, required this.organizationName, required this.status,
    required this.memberCount, required this.hasTasks, required this.totalEligibleTasks,
    required this.completedTasks, required this.progressPercent, required this.outstandingTaskCount,
    required this.overdueTaskCount, required this.createdAt, this.description, this.ownerName,
    this.startDate, this.dueDate, this.archivedAt, this.deletedAt});
  final String projectId, name, organizationId, organizationName, status, createdAt;
  final String? description, ownerName, startDate, dueDate, archivedAt, deletedAt;
  final int memberCount, totalEligibleTasks, completedTasks, outstandingTaskCount, overdueTaskCount;
  final bool hasTasks;
  final int? progressPercent;
  factory AdminProjectDetails.fromJson(Map<String, dynamic> json) => AdminProjectDetails(
    projectId: json['projectId'] as String, name: json['name'] as String,
    organizationId: json['organizationId'] as String, organizationName: json['organizationName'] as String,
    status: json['status'] as String, createdAt: json['createdAt'] as String,
    description: json['description'] as String?, ownerName: json['ownerName'] as String?,
    startDate: json['startDate'] as String?, dueDate: json['dueDate'] as String?,
    archivedAt: json['archivedAt'] as String?, deletedAt: json['deletedAt'] as String?,
    memberCount: json['memberCount'] as int? ?? 0, hasTasks: json['hasTasks'] as bool? ?? false,
    totalEligibleTasks: json['totalEligibleTasks'] as int? ?? 0,
    completedTasks: json['completedTasks'] as int? ?? 0, progressPercent: json['progressPercent'] as int?,
    outstandingTaskCount: json['outstandingTaskCount'] as int? ?? 0,
    overdueTaskCount: json['overdueTaskCount'] as int? ?? 0);
}

class AdminProjectMember {
  const AdminProjectMember({required this.displayName, required this.projectRole,
    required this.projectMembershipStatus, required this.accountStatus, required this.joinedAt,
    this.organizationMembershipStatus});
  final String displayName, projectRole, projectMembershipStatus, accountStatus, joinedAt;
  final String? organizationMembershipStatus;
  factory AdminProjectMember.fromJson(Map<String, dynamic> json) => AdminProjectMember(
    displayName: json['displayName'] as String? ?? 'Unknown member',
    projectRole: json['projectRole'] as String? ?? 'UNKNOWN',
    projectMembershipStatus: json['projectMembershipStatus'] as String? ?? 'unknown',
    organizationMembershipStatus: json['organizationMembershipStatus'] as String?,
    accountStatus: json['accountStatus'] as String? ?? 'unknown', joinedAt: json['joinedAt'] as String? ?? '');
}

class AdminProjectTask {
  const AdminProjectTask({required this.id, required this.title, required this.status,
    required this.priority, required this.effectiveAssigneeCount, required this.createdAt,
    this.dueDate, this.effectiveAssignees});
  final String id, title, status, priority, createdAt;
  final String? dueDate;
  final int effectiveAssigneeCount;
  final List<String>? effectiveAssignees;
  factory AdminProjectTask.fromJson(Map<String, dynamic> json) => AdminProjectTask(
    id: json['id'] as String, title: json['title'] as String? ?? '',
    status: json['status'] as String? ?? 'TO DO', priority: json['priority'] as String? ?? 'MEDIUM',
    dueDate: json['dueDate'] as String?, createdAt: json['createdAt'] as String? ?? '',
    effectiveAssigneeCount: json['effectiveAssigneeCount'] as int? ?? 0,
    effectiveAssignees: (json['effectiveAssignees'] as List<dynamic>?)?.whereType<String>().toList());
}

class AdminProjectPage<T> {
  const AdminProjectPage({required this.items, required this.page, required this.pageSize, required this.totalCount});
  final List<T> items;
  final int page, pageSize, totalCount;
}

class AdminGrowthPoint {
  const AdminGrowthPoint({required this.date, required this.count});
  final String date;
  final int count;
}

class AdminStatusPoint {
  const AdminStatusPoint({required this.label, required this.count});
  final String label;
  final int count;
}

class AdminAnalytics {
  const AdminAnalytics({
    required this.userGrowth,
    required this.projectGrowth,
    required this.tasksByStatus,
    required this.tasksByPriority,
  });
  final List<AdminGrowthPoint> userGrowth;
  final List<AdminGrowthPoint> projectGrowth;
  final List<AdminStatusPoint> tasksByStatus;
  final List<AdminStatusPoint> tasksByPriority;

  factory AdminAnalytics.fromJson(Map<String, dynamic> json) {
    List<AdminGrowthPoint> parseGrowth(List<dynamic> list, String key) => list
        .cast<Map<String, dynamic>>()
        .map((e) => AdminGrowthPoint(
              date: e['date'] as String? ?? '',
              count: e[key] as int? ?? 0,
            ))
        .toList();

    List<AdminStatusPoint> parseStatus(List<dynamic> list, String key) => list
        .cast<Map<String, dynamic>>()
        .map((e) => AdminStatusPoint(
              label: e[key] as String? ?? '',
              count: e['count'] as int? ?? 0,
            ))
        .toList();

    return AdminAnalytics(
      userGrowth:
          parseGrowth((json['userGrowth'] as List<dynamic>?) ?? [], 'users'),
      projectGrowth: parseGrowth(
          (json['projectGrowth'] as List<dynamic>?) ?? [], 'projects'),
      tasksByStatus: parseStatus(
          (json['tasksByStatus'] as List<dynamic>?) ?? [], 'status'),
      tasksByPriority: parseStatus(
          (json['tasksByPriority'] as List<dynamic>?) ?? [], 'priority'),
    );
  }
}

class PlatformActivityItem {
  const PlatformActivityItem({
    required this.eventId,
    required this.organizationId,
    required this.organizationName,
    this.projectId,
    required this.actorUserId,
    required this.actorName,
    required this.category,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    required this.description,
    required this.status,
    required this.correlationId,
    required this.createdAt,
    this.projectName,
  });
  final String eventId;
  final String organizationId;
  final String organizationName;
  final String? projectId;
  final String actorUserId;
  final String actorName;
  final String category;
  final String action;
  final String entityType;
  final String entityId;
  final String entityName;
  final String description;
  final String status;
  final String correlationId;
  final String createdAt;
  final String? projectName;

  factory PlatformActivityItem.fromJson(Map<String, dynamic> json) =>
      PlatformActivityItem(
        eventId: json['eventId'] as String? ?? '',
        organizationId: json['organizationId']?.toString() ?? '',
        organizationName: json['organizationName'] as String? ?? 'Platform',
        projectId: json['projectId']?.toString(),
        actorUserId: json['actorUserId'] as String? ?? '',
        actorName: json['actorName'] as String? ?? 'Unknown user',
        category: json['category'] as String? ?? 'System',
        action: json['action'] as String? ?? '',
        entityType: json['entityType'] as String? ?? '',
        entityId: json['entityId'] as String? ?? '',
        entityName: json['entityName'] as String? ?? '',
        description: json['description'] as String? ?? '',
        status: json['status'] as String? ?? '',
        correlationId: json['correlationId'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        projectName: json['projectName'] as String?,
      );
}

class PlatformActivityPage {
  const PlatformActivityPage({required this.items, this.nextCursor});
  final List<PlatformActivityItem> items;
  final String? nextCursor;
  factory PlatformActivityPage.fromJson(Map<String, dynamic> json) =>
      PlatformActivityPage(
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlatformActivityItem.fromJson)
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

class AdminAuditEvent {
  const AdminAuditEvent(
      {required this.eventId,
      required this.occurredAt,
      required this.actorName,
      required this.actorId,
      required this.action,
      required this.targetName,
      required this.targetType,
      required this.targetId,
      required this.outcome,
      this.reason,
      required this.correlationId});
  final String eventId;
  final String occurredAt;
  final String actorName;
  final String actorId;
  final String action;
  final String targetName;
  final String targetType;
  final String targetId;
  final String outcome;
  final String? reason;
  final String correlationId;
  factory AdminAuditEvent.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>? ?? const {};
    final target = json['target'] as Map<String, dynamic>? ?? const {};
    return AdminAuditEvent(
      eventId: json['eventId'] as String? ?? '',
      occurredAt: json['occurredAt'] as String? ?? '',
      actorName: actor['displayName'] as String? ?? 'Unknown administrator',
      actorId: actor['id'] as String? ?? '',
      action: json['action'] as String? ?? '',
      targetName: target['displayName'] as String? ?? '',
      targetType: target['type'] as String? ?? '',
      targetId: target['id'] as String? ?? '',
      outcome: json['outcome'] as String? ?? '',
      reason: json['reason'] as String?,
      correlationId: json['correlationId'] as String? ?? '',
    );
  }
}

class AdminAuditPage {
  const AdminAuditPage({required this.items, this.nextCursor});
  final List<AdminAuditEvent> items;
  final String? nextCursor;
  factory AdminAuditPage.fromJson(Map<String, dynamic> json) => AdminAuditPage(
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdminAuditEvent.fromJson)
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

class AdminHealthStatus {
  const AdminHealthStatus({required this.api, required this.database});
  final String api;
  final String database;
}
