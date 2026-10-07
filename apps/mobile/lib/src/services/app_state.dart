import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'dart:async';

import '../models/models.dart';
import 'api_client.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;
  HubConnection? _realtime;
  Timer? _reconnectTimer;
  Timer? _realtimeFallback;
  String? _joinedOrganizationId;
  String? _joinedProjectId;
  bool _refreshingRealtime = false;

  Future<void> connectRealtime() async {
    final session = await api.currentSession();
    if (session == null) return;
    final url = apiBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '/hubs/workspace');
    final connection = HubConnectionBuilder()
        .withUrl(url, options: HttpConnectionOptions(
          accessTokenFactory: () async => (await api.currentSession())?.accessToken ?? '',
          transport: HttpTransportType.WebSockets,
        ))
        .withAutomaticReconnect()
        .build();
    connection.on('workspaceChanged', (_) => _refreshFromRealtime());
    connection.onclose(({error}) {
      _startRealtimeFallback();
      _scheduleRealtimeReconnect();
    });
    connection.onreconnected(({connectionId}) {
      _stopRealtimeFallback();
      _joinedOrganizationId = null;
      _joinedProjectId = null;
      _joinRealtimeGroups();
    });
    _realtime = connection;
    try {
      await connection.start();
      _stopRealtimeFallback();
      await _joinRealtimeGroups();
    } catch (_) {
      _startRealtimeFallback();
      _scheduleRealtimeReconnect();
    }
  }

  Future<void> _joinRealtimeGroups() async {
    final connection = _realtime;
    if (connection?.state != HubConnectionState.Connected) return;
    final orgId = selectedOrg?.id;
    final projectId = selectedProject?.id;
    try {
      if (orgId != null && orgId != _joinedOrganizationId) {
        await connection!.invoke('JoinOrganization', args: [orgId]);
        _joinedOrganizationId = orgId;
      }
      if (projectId != null && projectId != _joinedProjectId) {
        if (_joinedProjectId != null) {
          await connection!.invoke('LeaveProject', args: [_joinedProjectId!]);
        }
        await connection!.invoke('JoinProject', args: [projectId]);
        _joinedProjectId = projectId;
      } else if (projectId == null && _joinedProjectId != null) {
        await connection!.invoke('LeaveProject', args: [_joinedProjectId!]);
        _joinedProjectId = null;
      }
    } catch (_) { _startRealtimeFallback(); }
  }

  void _startRealtimeFallback() {
    _realtimeFallback ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (_refreshingRealtime) return;
      _refreshingRealtime = true;
      refreshAll().whenComplete(() => _refreshingRealtime = false);
    });
  }

  void _scheduleRealtimeReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 30), () {
      if (_realtime?.state != HubConnectionState.Connected) {
        _joinedOrganizationId = null;
        _joinedProjectId = null;
        connectRealtime();
      }
    });
  }

  void _stopRealtimeFallback() { _realtimeFallback?.cancel(); _realtimeFallback = null; }

  Future<void> _refreshFromRealtime() async {
    if (_refreshingRealtime) return;
    _refreshingRealtime = true;
    try {
      await Future.wait<void>([
        loadNotifications(),
        if (selectedOrg != null) _loadOrgData(selectedOrg!.id),
        if (selectedProject != null) _loadProjectData(selectedProject!.id),
      ]);
      await _joinRealtimeGroups();
    } finally { _refreshingRealtime = false; }
  }

  // ─── Auth ─────────────────────────────────────────────────────────────────
  Account? account;

  // ─── Super admin ──────────────────────────────────────────────────────────
  bool isSuperAdmin = false;
  AdminDashboardMetrics? adminMetrics;
  AdminAnalytics? adminAnalytics;
  List<AdminUser> adminUsers = [];
  List<AdminOrganization> adminOrgs = [];
  List<AdminProject> adminProjects = [];
  AdminHealthStatus? adminHealth;
  bool loadingAdminMetrics = false;
  bool loadingAdminUsers = false;
  bool loadingAdminOrgs = false;
  bool loadingAdminProjects = false;
  bool loadingAdminAnalytics = false;
  bool loadingAdminHealth = false;

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

  /// Probes the admin dashboard endpoint. A 200 means the current user is a
  /// super admin; a 403 means they are not. A network error (e.g. cold-start
  /// spin-up on Render) is retried once after 4 seconds before giving up so
  /// a slow API wake-up does not permanently hide the Admin tab.
  Future<void> checkSuperAdmin({bool retry = true}) async {
    try {
      await api.adminDashboard();
      isSuperAdmin = true;
    } on ApiException catch (e) {
      // 403 = definitely not an admin. Any other API error keeps current state.
      if (e.statusCode == 403) {
        isSuperAdmin = false;
      }
      // else: keep existing value — don't downgrade a confirmed admin on a
      // transient error.
    } catch (_) {
      // Network / timeout error. If we haven't retried yet, wait and try once
      // more to handle cold-start spin-up delays (e.g. Render free tier).
      if (retry) {
        await Future.delayed(const Duration(seconds: 4));
        await checkSuperAdmin(retry: false);
        return;
      }
      // Second failure: keep existing state unchanged.
    }
    notifyListeners();
  }

  void signOut() {
    account = null;
    isSuperAdmin = false;
    adminMetrics = null;
    adminAnalytics = null;
    adminUsers = [];
    adminOrgs = [];
    adminProjects = [];
    adminHealth = null;
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

  // ─── Admin data loading ───────────────────────────────────────────────────

  Future<void> loadAdminDashboard() async {
    loadingAdminMetrics = true;
    notifyListeners();
    try {
      adminMetrics = await api.adminDashboard();
    } catch (e) {
      _setError(e);
    } finally {
      loadingAdminMetrics = false;
      notifyListeners();
    }
  }

  Future<void> loadAdminOverview() async {
    await Future.wait([
      loadAdminDashboard(),
      loadAdminAnalytics(
        from: _adminDate(
            DateTime.now().toUtc().add(const Duration(hours: 3)).subtract(
                  const Duration(days: 30),
                )),
        to: _adminDate(DateTime.now().toUtc().add(const Duration(hours: 3))),
      ),
      loadAdminProjects(),
    ]);
  }

  String _adminDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> loadAdminAnalytics(
      {required String from, required String to}) async {
    loadingAdminAnalytics = true;
    notifyListeners();
    try {
      adminAnalytics = await api.adminAnalytics(from: from, to: to);
    } catch (e) {
      _setError(e);
    } finally {
      loadingAdminAnalytics = false;
      notifyListeners();
    }
  }

  Future<void> loadAdminUsers() async {
    loadingAdminUsers = true;
    notifyListeners();
    try {
      adminUsers = await api.adminUsers();
    } catch (e) {
      _setError(e);
    } finally {
      loadingAdminUsers = false;
      notifyListeners();
    }
  }

  Future<void> loadAdminOrgs() async {
    loadingAdminOrgs = true;
    notifyListeners();
    try {
      adminOrgs = await api.adminOrganizations();
    } catch (e) {
      _setError(e);
    } finally {
      loadingAdminOrgs = false;
      notifyListeners();
    }
  }

  Future<void> loadAdminProjects() async {
    loadingAdminProjects = true;
    notifyListeners();
    try {
      adminProjects = await api.adminProjects();
    } catch (e) {
      _setError(e);
    } finally {
      loadingAdminProjects = false;
      notifyListeners();
    }
  }

  Future<void> loadAdminHealth() async {
    loadingAdminHealth = true;
    notifyListeners();
    try {
      adminHealth = await api.adminHealth();
    } catch (e) {
      _setError(e);
    } finally {
      loadingAdminHealth = false;
      notifyListeners();
    }
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
    await _joinRealtimeGroups();
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
    await _joinRealtimeGroups();
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

  Future<Task> getTask(String taskId) async {
    final cachedTask = tasks.where((task) => task.id == taskId).firstOrNull;
    if (cachedTask != null) return cachedTask;

    final projectIds = <String>{
      if (selectedProject != null) selectedProject!.id,
      ...projects.map((project) => project.id),
    };
    for (final projectId in projectIds) {
      final projectTasks = await api.tasks(projectId);
      if (selectedProject?.id == projectId) {
        tasks = projectTasks;
        notifyListeners();
      }
      final task = projectTasks.where((item) => item.id == taskId).firstOrNull;
      if (task != null) return task;
    }

    throw const ApiException('Task not found.', statusCode: 404);
  }

  Future<void> updateTask(Task task) async {
    await api.updateTask(
      taskId: task.id,
      title: task.title,
      description: task.description,
      status: task.status,
      priority: task.priority,
      startDate: task.startDate,
      dueDate: task.dueDate,
      assigneeIds: task.assigneeIds,
      clearStartDate: task.startDate == null,
      clearDueDate: task.dueDate == null,
    );
    tasks = [
      for (final current in tasks)
        if (current.id == task.id) task else current,
    ];
    notifyListeners();
    if (selectedProject?.id == task.projectId) await refreshTasks();
  }

  Future<void> deleteTask(String taskId) async {
    await api.deleteTask(taskId);
    tasks = tasks.where((task) => task.id != taskId).toList();
    notifyListeners();
    await refreshTasks();
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
            createdAt: t.createdAt,
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

  @override
  void dispose() {
    _stopRealtimeFallback();
    _reconnectTimer?.cancel();
    _realtime?.stop();
    super.dispose();
  }
}
