import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'board_screen.dart';
import 'dashboard_screen.dart';
import 'members_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'task_detail_screen.dart';

enum _WorkspacePage {
  overview,
  board,
  members,
  activity,
  notifications,
  settings
}

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    required this.onSignedOut,
    required this.onToggleTheme,
    required this.themeMode,
  });

  final VoidCallback onSignedOut;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  _WorkspacePage _page = _WorkspacePage.overview;
  String _dashboardFilter = '';

  String _displayRole(String? role) {
    if (role == null || role.isEmpty) return 'Workspace';
    final normalized = role.toLowerCase().replaceAll('_', ' ');
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  void _navigate(_WorkspacePage page) {
    Navigator.of(context).pop();
    setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final account = state.account;
    final initials =
        '${account?.firstName.isNotEmpty == true ? account!.firstName[0] : ''}'
        '${account?.lastName.isNotEmpty == true ? account!.lastName[0] : ''}';
    final drawerWidth = math.min(MediaQuery.sizeOf(context).width * .70, 280.0);

    final pages = <Widget>[
      DashboardScreen(
        onOpenBoard: () => setState(() => _page = _WorkspacePage.board),
        onOpenActivity: () => setState(() => _page = _WorkspacePage.activity),
        onFilterTasks: (filter) => setState(() {
          _dashboardFilter = filter;
          _page = _WorkspacePage.board;
        }),
      ),
      BoardScreen(
        initialDashboardFilter: _dashboardFilter,
        onOpenMembers: () => setState(() => _page = _WorkspacePage.members),
        onOpenSettings: () => setState(() => _page = _WorkspacePage.settings),
        onClearDashboardFilter: () => setState(() => _dashboardFilter = ''),
      ),
      const MembersScreen(),
      const _WorkspaceActivityScreen(),
      NotificationsScreen(
        onNavigateToTask: (projectId, taskId) =>
            _openTaskFromNotification(projectId, taskId),
      ),
      SettingsScreen(
        onSignedOut: widget.onSignedOut,
        onToggleTheme: widget.onToggleTheme,
        themeMode: widget.themeMode,
      ),
    ];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13151F) : kPage,
      drawerScrimColor: Colors.black38,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        toolbarHeight: 48,
        titleSpacing: 4,
        title: Row(children: [
          Builder(
              builder: (context) => IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Open navigation',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_rounded, size: 20),
                  )),
          const SizedBox(width: 3),
          Expanded(
              child: SearchAnchor(
            builder: (context, controller) => SearchBar(
              controller: controller,
              hintText: 'Search tasks, projects',
              leading: const Icon(Icons.search_rounded, size: 17),
              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 10)),
              hintStyle: const WidgetStatePropertyAll(
                  TextStyle(fontSize: 10, color: _kMuted)),
              backgroundColor: WidgetStatePropertyAll(
                  isDark ? const Color(0xFF252735) : const Color(0xFFF8F8FA)),
              elevation: const WidgetStatePropertyAll(0),
              constraints: const BoxConstraints(minHeight: 34, maxHeight: 34),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: _kLine))),
              onTap: controller.openView,
            ),
            suggestionsBuilder: (context, controller) {
              final query = controller.text.trim().toLowerCase();
              if (query.isEmpty) {
                return const [
                  ListTile(
                      title: Text('Search tasks, projects, and members',
                          style: TextStyle(fontSize: 12)))
                ];
              }
              final tasks = state.tasks
                  .where((task) => task.title.toLowerCase().contains(query))
                  .take(8);
              final projects = state.projects
                  .where(
                      (project) => project.name.toLowerCase().contains(query))
                  .take(8);
              final members = state.orgMembers
                  .where(
                      (member) => member.fullName.toLowerCase().contains(query))
                  .take(8);
              final results = <Widget>[];
              for (final task in tasks) {
                results.add(ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_box_outlined, size: 17),
                    title: Text(task.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Task'),
                    onTap: () {
                      controller.closeView(task.title);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: state,
                          child: TaskDetailScreen(taskId: task.id),
                        ),
                      ));
                    }));
              }
              for (final project in projects) {
                results.add(ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_outlined, size: 17),
                    title: Text(project.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Project'),
                    onTap: () {
                      controller.closeView(project.name);
                      state.selectProject(project);
                      setState(() => _page = _WorkspacePage.board);
                    }));
              }
              for (final member in members) {
                results.add(ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, size: 17),
                    title: Text(member.fullName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Member'),
                    onTap: () {
                      controller.closeView(member.fullName);
                      setState(() => _page = _WorkspacePage.members);
                    }));
              }
              if (results.isEmpty) {
                return const [
                  ListTile(
                      title: Text('No matching results',
                          style: TextStyle(fontSize: 12)))
                ];
              }
              return results.take(8).toList();
            },
          )),
        ]),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            tooltip: 'Notifications',
            onPressed: () =>
                setState(() => _page = _WorkspacePage.notifications),
            icon: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.notifications_none_rounded),
              if (state.unreadCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _kViolet,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ]),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: widget.onToggleTheme,
            icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            tooltip: 'Account and workspace',
            onPressed: _openWorkspaceMenu,
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: _kVioletLight,
              backgroundImage: account?.avatarUrl == null
                  ? null
                  : NetworkImage(account!.avatarUrl!),
              child: account?.avatarUrl == null
                  ? Text(initials.toLowerCase(),
                      style: const TextStyle(
                          fontSize: 9,
                          color: _kViolet,
                          fontWeight: FontWeight.w700))
                  : null,
            ),
          ),
        ],
      ),
      drawer: SizedBox(
        width: drawerWidth,
        child: Drawer(
          width: drawerWidth,
          backgroundColor: isDark ? const Color(0xFF1B1D2A) : Colors.white,
          shape: const RoundedRectangleBorder(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TaskFlowBrand(
                        iconSize: 26,
                        textSize: 15,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _displayRole(state.selectedOrg?.role),
                        style: const TextStyle(fontSize: 9, color: _kMuted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: [
                      const _DrawerGroupLabel('MAIN'),
                      _DrawerItem(
                          label: 'Overview',
                          icon: Icons.grid_view_outlined,
                          selected: _page == _WorkspacePage.overview,
                          onTap: () => _navigate(_WorkspacePage.overview)),
                      _DrawerItem(
                          label: 'Board',
                          icon: Icons.format_list_bulleted,
                          selected: _page == _WorkspacePage.board,
                          onTap: () => _navigate(_WorkspacePage.board)),
                      _DrawerItem(
                          label: 'Members',
                          icon: Icons.people_outline,
                          selected: _page == _WorkspacePage.members,
                          onTap: () => _navigate(_WorkspacePage.members)),
                      const _DrawerGroupLabel('TOOLS'),
                      _DrawerItem(
                          label: 'Activity',
                          icon: Icons.monitor_heart_outlined,
                          selected: _page == _WorkspacePage.activity,
                          onTap: () => _navigate(_WorkspacePage.activity)),
                      _DrawerItem(
                          label: 'Notifications',
                          icon: Icons.notifications_none,
                          selected: _page == _WorkspacePage.notifications,
                          onTap: () => _navigate(_WorkspacePage.notifications),
                          trailing: state.unreadCount > 0
                              ? '${state.unreadCount}'
                              : null),
                      const _DrawerGroupLabel('HELP'),
                      _DrawerItem(
                          label: 'Settings',
                          icon: Icons.settings_outlined,
                          selected: _page == _WorkspacePage.settings,
                          onTap: () => _navigate(_WorkspacePage.settings)),
                      const _DrawerGroupLabel('ORGANIZATION'),
                      _DrawerItem(
                          label: 'New organization',
                          icon: Icons.add_circle_outline,
                          onTap: _createOrganization),
                    ],
                  ),
                ),
                Divider(height: 1, color: isDark ? _kLineDark : _kLine),
                InkWell(
                  onTap: () => _navigate(_WorkspacePage.settings),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: isDark
                            ? const Color(0xFF35313E)
                            : const Color(0xFFEAE5DC),
                        backgroundImage: account?.avatarUrl == null
                            ? null
                            : NetworkImage(account!.avatarUrl!),
                        child: account?.avatarUrl == null
                            ? Text(initials.toLowerCase(),
                                style: const TextStyle(
                                    fontSize: 9, color: _kMuted))
                            : null,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${account?.firstName ?? ''} ${account?.lastName ?? ''}'
                                    .trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF20202B))),
                            Text(_displayRole(state.selectedOrg?.role),
                                style: const TextStyle(
                                    fontSize: 8, color: _kMuted)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        visualDensity: VisualDensity.compact,
                        onPressed: _signOut,
                        icon:
                            const Icon(Icons.logout, size: 16, color: _kMuted),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _page.index, children: pages),
    );
  }

  Future<void> _openTaskFromNotification(
      String projectId, String taskId) async {
    final state = context.read<AppState>();
    try {
      final project = await state.api.projectById(projectId);
      if (state.selectedOrg?.id != project.organizationId) {
        final organization = state.organizations
            .where((item) => item.id == project.organizationId)
            .firstOrNull;
        if (organization == null) {
          throw const ApiException('Workspace is unavailable.');
        }
        await state.selectOrg(organization);
      }
      final selected =
          state.projects.where((item) => item.id == projectId).firstOrNull;
      if (selected == null) throw const ApiException('Project is unavailable.');
      await state.selectProject(selected);
      if (!mounted) return;
      setState(() => _page = _WorkspacePage.board);
      if (state.tasks.any((task) => task.id == taskId)) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: state,
            child: TaskDetailScreen(taskId: taskId),
          ),
        ));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _openWorkspaceMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Consumer<AppState>(
            builder: (context, current, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${current.account?.firstName ?? ''} ${current.account?.lastName ?? ''}'
                                .trim(),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(current.account?.email ?? '',
                            style:
                                const TextStyle(fontSize: 12, color: _kMuted)),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: current.selectedOrg?.id,
                          decoration:
                              const InputDecoration(labelText: 'Organization'),
                          items: current.organizations
                              .map((org) => DropdownMenuItem(
                                  value: org.id,
                                  child: Text(org.name,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (id) {
                            final org = current.organizations
                                .where((item) => item.id == id)
                                .firstOrNull;
                            if (org != null) current.selectOrg(org);
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: current.selectedProject?.id,
                          decoration:
                              const InputDecoration(labelText: 'Project'),
                          items: current.projects
                              .map((project) => DropdownMenuItem(
                                  value: project.id,
                                  child: Text(project.name,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (id) {
                            final project = current.projects
                                .where((item) => item.id == id)
                                .firstOrNull;
                            if (project != null) current.selectProject(project);
                          },
                        ),
                        const SizedBox(height: 12),
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                setState(() => _page = _WorkspacePage.settings);
                              },
                              icon:
                                  const Icon(Icons.settings_outlined, size: 17),
                              label: const Text('Account settings'),
                            )),
                      ]),
                )),
      ),
    );
  }

  Future<void> _createOrganization() async {
    Navigator.of(context).pop();
    final controller = TextEditingController();
    final state = context.read<AppState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New organization'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Organization name'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await state.api.createOrganization(name: name);
      await state.loadOrganizations();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _signOut() async {
    Navigator.of(context).pop();
    final state = context.read<AppState>();
    try {
      await state.api.logout();
    } on ApiException {
      // Local sign-out must still work when the API is unavailable.
    }
    if (!mounted) return;
    state.signOut();
    widget.onSignedOut();
  }
}

class _DrawerGroupLabel extends StatelessWidget {
  const _DrawerGroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 8, 4),
        child: Text(label,
            style: const TextStyle(
                color: _kMuted,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      );
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: selected ? _kVioletLight : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Row(children: [
                  Icon(icon, size: 14, color: selected ? _kViolet : _kMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                            color:
                                selected ? _kViolet : const Color(0xFF3A3F5C))),
                  ),
                  if (trailing != null)
                    Text(trailing!,
                        style: const TextStyle(fontSize: 9, color: _kMuted)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _WorkspaceActivityScreen extends StatefulWidget {
  const _WorkspaceActivityScreen();

  @override
  State<_WorkspaceActivityScreen> createState() =>
      _WorkspaceActivityScreenState();
}

class _WorkspaceActivityScreenState extends State<_WorkspaceActivityScreen> {
  static const _categories = [
    'All',
    'Projects',
    'Tasks',
    'People',
    'Collaboration'
  ];
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _events = [];
  List<String?> _cursorStack = [null];
  String? _nextCursor;
  String _category = 'All';
  String _search = '';
  DateTimeRange? _range;
  bool _loading = true;
  String? _error;
  Timer? _poller;
  String? _organizationId;

  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted &&
          !_loading &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load(silent: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final organizationId = context.read<AppState>().selectedOrg?.id;
    if (organizationId == _organizationId) return;
    _organizationId = organizationId;
    _cursorStack = [null];
    _events = [];
    _nextCursor = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(cursor: null);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({String? cursor, bool silent = false}) async {
    final organizationId = context.read<AppState>().selectedOrg?.id;
    if (organizationId == null) {
      if (mounted) {
        setState(() {
          _events = [];
          _loading = false;
        });
      }
      return;
    }
    if (_loading && silent) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final range = _range;
      final page = await context.read<AppState>().api.workspaceActivityPage(
            organizationId: organizationId,
            category: _category == 'All' ? null : _category,
            search: _search,
            from: range == null
                ? null
                : DateTime.utc(
                        range.start.year, range.start.month, range.start.day)
                    .toIso8601String(),
            to: range == null
                ? null
                : DateTime.utc(range.end.year, range.end.month, range.end.day)
                    .toIso8601String(),
            cursor: cursor ?? _cursorStack.last,
            pageSize: 30,
          );
      if (mounted) {
        setState(() {
          _events = page.items;
          _nextCursor = page.nextCursor;
          _loading = false;
          _error = null;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _chooseRange() async {
    final today = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: _range,
    );
    if (range == null || !mounted) return;
    setState(() {
      _range = range;
      _cursorStack = [null];
    });
    await _load(cursor: null);
  }

  Future<void> _clearFilters() async {
    _searchController.clear();
    setState(() {
      _search = '';
      _category = 'All';
      _range = null;
      _cursorStack = [null];
    });
    await _load(cursor: null);
  }

  String _eventDate(Map<String, dynamic> event) {
    final value = DateTime.tryParse(event['createdAt'] as String? ?? '');
    return value == null
        ? ''
        : '${MaterialLocalizations.of(context).formatFullDate(value.toLocal())} at ${TimeOfDay.fromDateTime(value.toLocal()).format(context)}';
  }

  void _showEvent(Map<String, dynamic> event) {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event['description'] as String? ?? 'Activity event',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                          '${event['actorName'] ?? 'Someone'} - ${_eventDate(event)}',
                          style: const TextStyle(fontSize: 12, color: _kMuted)),
                      const Divider(height: 24),
                      _detailLine('Category', event['category']),
                      _detailLine('Organization', event['organizationName']),
                      _detailLine('Event',
                          '${event['action'] ?? ''} | ${event['status'] ?? ''}'),
                      _detailLine('Target',
                          '${event['entityType'] ?? ''} | ${event['entityName'] ?? ''}'),
                      _detailLine('Request ID', event['correlationId']),
                    ]))));
  }

  Widget _detailLine(String label, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 94,
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: _kMuted))),
        Expanded(
            child: SelectableText(value?.toString() ?? '?',
                style: const TextStyle(fontSize: 11)))
      ]));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
          children: [
            Row(children: [
              const Expanded(
                  child: Text('Activity',
                      style: TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w700))),
              IconButton(
                  onPressed: _loading ? null : () => _load(),
                  tooltip: 'Refresh',
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded))
            ]),
            const Text('Important actions and changes across your workspace.',
                style: TextStyle(fontSize: 11, color: _kMuted)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: SizedBox(
                      height: 40,
                      child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) {
                            setState(() {
                              _search = value.trim();
                              _cursorStack = [null];
                            });
                            _load(cursor: null);
                          },
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded, size: 18),
                              hintText: 'Search activity',
                              isDense: true)))),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                  onPressed: () {
                    setState(() {
                      _search = _searchController.text.trim();
                      _cursorStack = [null];
                    });
                    _load(cursor: null);
                  },
                  icon: const Icon(Icons.search_rounded, size: 18))
            ]),
            const SizedBox(height: 8),
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                    children: _categories
                        .map((category) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                                label: Text(category,
                                    style: const TextStyle(fontSize: 10)),
                                selected: _category == category,
                                onSelected: (_) {
                                  setState(() {
                                    _category = category;
                                    _cursorStack = [null];
                                  });
                                  _load(cursor: null);
                                })))
                        .toList())),
            const SizedBox(height: 4),
            Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                      onPressed: _chooseRange,
                      icon: const Icon(Icons.calendar_month_outlined, size: 15),
                      label: Text(
                          _range == null
                              ? 'Date range'
                              : '${MaterialLocalizations.of(context).formatShortDate(_range!.start)} - ${MaterialLocalizations.of(context).formatShortDate(_range!.end)}',
                          style: const TextStyle(fontSize: 10))),
                  if (_search.isNotEmpty ||
                      _category != 'All' ||
                      _range != null)
                    TextButton(
                        onPressed: _clearFilters,
                        child: const Text('Clear filters')),
                  const Text('Latest first | refreshes every 10s',
                      style: TextStyle(fontSize: 9, color: _kMuted)),
                ]),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ErrorBanner('Unable to load activity: $_error')),
            if (_loading && _events.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator())),
            if (!_loading && _error == null && _events.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(children: [
                    Icon(Icons.bolt_outlined,
                        size: 24, color: isDark ? Colors.white54 : _kMuted),
                    const SizedBox(height: 8),
                    const Text('No activity yet',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                        'Project, task, collaboration, and member changes will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: _kMuted))
                  ])),
            for (final event in _events)
              Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                      onTap: () => _showEvent(event),
                      leading: const CircleAvatar(
                          backgroundColor: _kVioletLight,
                          child: Icon(Icons.bolt_outlined,
                              color: _kViolet, size: 18)),
                      title: Text(event['description'] as String? ?? '',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              '${event['category'] ?? ''} - ${event['organizationName'] ?? ''}\n${event['actorName'] ?? 'Someone'} - ${_eventDate(event)}',
                              style: const TextStyle(fontSize: 10),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis)),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right, size: 18))),
            if (_events.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            'Page ${_cursorStack.length} - ${_events.length} events',
                            style:
                                const TextStyle(fontSize: 10, color: _kMuted)),
                        Row(children: [
                          TextButton(
                              onPressed: _cursorStack.length <= 1 || _loading
                                  ? null
                                  : () {
                                      setState(() => _cursorStack = _cursorStack
                                          .sublist(0, _cursorStack.length - 1));
                                      _load();
                                    },
                              child: const Text('Previous')),
                          const SizedBox(width: 4),
                          FilledButton.tonal(
                              onPressed: _nextCursor == null || _loading
                                  ? null
                                  : () {
                                      setState(() => _cursorStack = [
                                            ..._cursorStack,
                                            _nextCursor
                                          ]);
                                      _load(cursor: _nextCursor);
                                    },
                              child: const Text('Next'))
                        ])
                      ])),
          ]),
    );
  }
}

const _kViolet = Color(0xFF5141E8);
const _kVioletLight = Color(0xFFEFEDFF);
const _kMuted = Color(0xFF92929D);
const _kLine = Color(0xFFE5E5EB);
const _kLineDark = Color(0xFF343845);
