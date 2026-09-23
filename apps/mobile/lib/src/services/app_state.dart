import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;

  // ─── Auth ─────────────────────────────────────────────────────────────────
  Account? account;

  // ─── Organizations ────────────────────────────────────────────────────────
  List<Organization> organizations = [];
  Organization? selectedOrg;

  // ─── Projects ────────────────────────────────────────────────────────────
  List<Project> projects = [];
  Project? selectedProject;

  // ─── Tasks ────────────────────────────────────────────────────────────────
  List<Task> tasks = [];
  DashboardMetrics? metrics;

  // ─── Members ──────────────────────────────────────────────────────────────
  List<Member> orgMembers = [];
  List<Member> projectMembers = [];
  List<Invitation> invitations = [];

  // ─── Notifications ────────────────────────────────────────────────────────
  List<Notice> notifications = [];

  // ─── Loading flags ────────────────────────────────────────────────────────
  bool loadingOrgs = false;
  bool loadingProjects = false;
  bool loadingTasks = false;
  bool loadingNotifications = false;

  String? error;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  void _setError(Object e) {
    error = e is ApiException ? e.message : e.toString();
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  // ─── Auth operations ──────────────────────────────────────────────────────

  Future<void> loadAccount() async {
    try {
      account = await api.account();
      notifyListeners();
    } catch (e) {
      _setError(e);
    }
  }

  void signOut() {
    account = null;
    organizations = [];
    selectedOrg = null;
    projects = [];
    selectedProject = null;
    tasks = [];
    metrics = null;
    orgMembers = [];
    projectMembers = [];
    invitations = [];
    notifications = [];
    error = null;
    notifyListeners();
  }

  // ─── Organizations ────────────────────────────────────────────────────────

  Future<void> loadOrganizations() async {
    loadingOrgs = true;
    notifyListeners();
    try {
      organizations = await api.organizations();
      if (selectedOrg != null) {
        selectedOrg =
            organizations.where((o) => o.id == selectedOrg!.id).firstOrNull;
      }
      selectedOrg ??= organizations.firstOrNull;
      if (selectedOrg != null) await _loadOrgData(selectedOrg!.id);
    } catch (e) {
      _setError(e);
    } finally {
      loadingOrgs = false;
      notifyListeners();
    }
  }

  Future<void> selectOrg(Organization org) async {
    selectedOrg = org;
    projects = [];
    selectedProject = null;
    tasks = [];
    metrics = null;
    notifyListeners();
    await _loadOrgData(org.id);
  }

  Future<void> _loadOrgData(String orgId) async {
    loadingProjects = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.projects(orgId),
        api.orgMembers(orgId),
        if (selectedOrg?.isAdminOrOwner ?? false)
          api.orgInvitations(orgId)
        else
          Future.value(<Invitation>[]),
      ]);
      projects = results[0] as List<Project>;
      orgMembers = results[1] as List<Member>;
      invitations = results[2] as List<Invitation>;
      if (selectedProject != null) {
        selectedProject =
            projects.where((p) => p.id == selectedProject!.id).firstOrNull;
      }
      selectedProject ??= projects.firstOrNull;
      if (selectedProject != null) await _loadProjectData(selectedProject!.id);
    } catch (e) {
      _setError(e);
    } finally {
      loadingProjects = false;
      notifyListeners();
    }
  }

  Future<void> selectProject(Project project) async {
    selectedProject = project;
    tasks = [];
    metrics = null;
    projectMembers = [];
    notifyListeners();
    await _loadProjectData(project.id);
  }

  Future<void> _loadProjectData(String projectId) async {
    loadingTasks = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.tasks(projectId),
        api.projectMembers(projectId),
        api.dashboardMetrics(projectId),
      ]);
      tasks = results[0] as List<Task>;
      projectMembers = results[1] as List<Member>;
      metrics = results[2] as DashboardMetrics;
    } catch (e) {
      _setError(e);
    } finally {
      loadingTasks = false;
      notifyListeners();
    }
  }

  Future<void> refreshTasks() async {
    if (selectedProject == null) return;
    await _loadProjectData(selectedProject!.id);
  }

  Future<void> moveTask(String taskId, String status) async {
    // Optimistic update
    tasks = [
      for (final t in tasks)
        if (t.id == taskId)
          Task(
            id: t.id,
            projectId: t.projectId,
            parentTaskId: t.parentTaskId,
            title: t.title,
            description: t.description,
            status: status,
            priority: t.priority,
            startDate: t.startDate,
            dueDate: t.dueDate,
            completedAt: t.completedAt,
            assigneeIds: t.assigneeIds,
            subtaskCount: t.subtaskCount,
            completedSubtaskCount: t.completedSubtaskCount,
          )
        else
          t
    ];
    notifyListeners();
    try {
      await api.updateTask(taskId: taskId, status: status);
    } catch (e) {
      _setError(e);
      await refreshTasks(); // revert
    }
  }

  // ─── Notifications ────────────────────────────────────────────────────────

  Future<void> loadNotifications() async {
    loadingNotifications = true;
    notifyListeners();
    try {
      notifications = await api.notifications();
    } catch (e) {
      _setError(e);
    } finally {
      loadingNotifications = false;
      notifyListeners();
    }
  }

  Future<void> markRead(String id) async {
    notifications = [
      for (final n in notifications)
        if (n.id == id)
          Notice(
              id: n.id,
              message: n.message,
              isRead: true,
              createdAt: n.createdAt,
              relatedId: n.relatedId,
              projectId: n.projectId)
        else
          n
    ];
    notifyListeners();
    try {
      await api.markNotificationRead(id);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    notifications = [
      for (final n in notifications)
        Notice(
            id: n.id,
            message: n.message,
            isRead: true,
            createdAt: n.createdAt,
            relatedId: n.relatedId,
            projectId: n.projectId)
    ];
    notifyListeners();
    try {
      await api.markAllNotificationsRead();
    } catch (_) {}
  }

  Future<void> refreshAll() async {
    await loadOrganizations();
    await loadNotifications();
  }
}
