import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/board_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/members_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/task_detail_screen.dart';
import 'services/api_client.dart';
import 'services/app_state.dart';
import 'services/session_store.dart';
import 'widgets/common.dart';

class PmsApp extends StatefulWidget {
  const PmsApp({super.key});

  @override
  State<PmsApp> createState() => _PmsAppState();
}

class _PmsAppState extends State<PmsApp> {
  late final SessionStore _sessions;
  late final ApiClient _api;
  late final AppState _appState;
  ThemeMode _themeMode = ThemeMode.system;
  Future<bool>? _init;

  @override
  void initState() {
    super.initState();
    _sessions = const SessionStore(FlutterSecureStorage());
    _api = ApiClient(sessionStore: _sessions);
    _appState = AppState(_api);
    _init = _tryRestore();
  }

  Future<bool> _tryRestore() async {
    if (await _sessions.read() == null) return false;
    try {
      await _appState.loadAccount();
      if (_appState.account == null) return false;
      await _appState.loadOrganizations();
      await _appState.loadNotifications();
      return true;
    } on ApiException {
      await _sessions.clear();
      return false;
    }
  }

  void _handleSignedIn() {
    setState(() => _init = _tryRestore());
  }

  void _handleSignedOut() {
    setState(() => _init = Future.value(false));
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: MaterialApp(
        title: 'Sababisha PMS',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: FutureBuilder<bool>(
          future: _init,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (snap.data == true) {
              return _HomeShell(
                onSignedOut: _handleSignedOut,
                onToggleTheme: _toggleTheme,
              );
            }
            return AuthPage(
              api: _api,
              onSignedIn: _handleSignedIn,
            );
          },
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3156D3),
        brightness: brightness,
      ),
      useMaterial3: true,
      fontFamily: 'Roboto',
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: Color(0x1A000000)),
        ),
      ),
    );
  }
}

// ─── Home shell with bottom nav, app bar, org+project picker ─────────────────

class _HomeShell extends StatefulWidget {
  const _HomeShell(
      {required this.onSignedOut, required this.onToggleTheme});
  final VoidCallback onSignedOut;
  final VoidCallback onToggleTheme;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _navIndex = 0;

  final _pages = const [
    _NavItem(label: 'Dashboard', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard),
    _NavItem(label: 'Board', icon: Icons.view_kanban_outlined, activeIcon: Icons.view_kanban),
    _NavItem(label: 'Members', icon: Icons.group_outlined, activeIcon: Icons.group),
    _NavItem(label: 'Notifications', icon: Icons.notifications_outlined, activeIcon: Icons.notifications),
    _NavItem(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings),
  ];

  String _pageTitle(AppState state) {
    switch (_navIndex) {
      case 0:
        return state.selectedProject?.name ?? 'Dashboard';
      case 1:
        return state.selectedProject?.name ?? 'Board';
      case 2:
        return 'Members';
      case 3:
        return 'Notifications';
      case 4:
        return 'Settings';
      default:
        return 'Sababisha PMS';
    }
  }

  Widget _buildPage(AppState state) {
    switch (_navIndex) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const BoardScreen();
      case 2:
        return const MembersScreen();
      case 3:
        return NotificationsScreen(
          onNavigateToTask: (projectId, taskId) async {
            // Navigate to board and open task
            final project = state.projects
                .where((p) => p.id == projectId)
                .firstOrNull;
            if (project != null) {
              await state.selectProject(project);
              setState(() => _navIndex = 1);
              // Task will be found in board and can be tapped
            }
          },
        );
      case 4:
        return SettingsScreen(
          onSignedOut: widget.onSignedOut,
          onToggleTheme: widget.onToggleTheme,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final unread = state.unreadCount;
    final canWrite =
        _navIndex == 1 && (state.selectedProject?.canWrite ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_pageTitle(state),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (state.selectedOrg != null && _navIndex <= 1)
            Text(state.selectedOrg!.name,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6))),
        ]),
        actions: [
          // Notification badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => setState(() => _navIndex = 3),
              ),
              if (unread > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // New task FAB-like button in app bar when on board
          if (canWrite)
            IconButton(
              icon: const Icon(Icons.add_task),
              onPressed: () => _openNewTask(context, state),
              tooltip: 'New task',
            ),
          // Project selector / org dropdown
          _OrgProjectPicker(state: state),
        ],
      ),
      body: Column(children: [
        // Error global banner
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ErrorBanner(state.error!, onDismiss: state.clearError),
          ),
        Expanded(child: _buildPage(state)),
      ]),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openNewTask(context, state),
              icon: const Icon(Icons.add),
              label: const Text('New task'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: _pages
            .asMap()
            .entries
            .map((e) => NavigationDestination(
                  icon: Badge(
                    isLabelVisible: e.key == 3 && unread > 0,
                    label: Text(unread > 9 ? '9+' : '$unread'),
                    child: Icon(e.value.icon),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: e.key == 3 && unread > 0,
                    label: Text(unread > 9 ? '9+' : '$unread'),
                    child: Icon(e.value.activeIcon),
                  ),
                  label: e.value.label,
                ))
            .toList(),
      ),
    );
  }

  Future<void> _openNewTask(BuildContext context, AppState state) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
                value: state,
                child: TaskFormScreen(
                  state: state,
                  onSaved: () => state.refreshTasks(),
                ),
              )),
    );
  }
}

// ─── Org + project picker in app bar ─────────────────────────────────────────

class _OrgProjectPicker extends StatelessWidget {
  const _OrgProjectPicker({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune_outlined),
      tooltip: 'Switch workspace',
      onSelected: (_) {},
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<String>>[];

        // Organizations
        if (state.organizations.isNotEmpty) {
          items.add(const PopupMenuItem(
              enabled: false,
              height: 32,
              child: Text('ORGANIZATIONS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1))));
          for (final org in state.organizations) {
            items.add(PopupMenuItem(
              value: 'org:${org.id}',
              child: Row(children: [
                if (state.selectedOrg?.id == org.id)
                  Icon(Icons.check,
                      size: 16,
                      color: Theme.of(ctx).colorScheme.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(org.name)),
                Text(org.role,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).colorScheme.outline)),
              ]),
              onTap: () => state.selectOrg(org),
            ));
          }
          items.add(const PopupMenuDivider());
        }

        // Projects
        if (state.projects.isNotEmpty) {
          items.add(const PopupMenuItem(
              enabled: false,
              height: 32,
              child: Text('PROJECTS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1))));
          for (final project in state.projects) {
            items.add(PopupMenuItem(
              value: 'proj:${project.id}',
              child: Row(children: [
                if (state.selectedProject?.id == project.id)
                  Icon(Icons.check,
                      size: 16,
                      color: Theme.of(ctx).colorScheme.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(project.name)),
              ]),
              onTap: () => state.selectProject(project),
            ));
          }
          items.add(const PopupMenuDivider());
        }

        // Create new
        items.add(PopupMenuItem(
          value: '__new_org__',
          child: Row(children: [
            Icon(Icons.add,
                size: 18,
                color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('New organization'),
          ]),
          onTap: () => _showNewOrgDialog(ctx, state),
        ));
        items.add(PopupMenuItem(
          value: '__new_proj__',
          enabled: state.selectedOrg != null,
          child: Row(children: [
            Icon(Icons.add,
                size: 18,
                color: state.selectedOrg != null
                    ? Theme.of(ctx).colorScheme.primary
                    : Theme.of(ctx).colorScheme.outline),
            const SizedBox(width: 8),
            const Text('New project'),
          ]),
          onTap: state.selectedOrg != null
              ? () => _showNewProjectDialog(ctx, state)
              : null,
        ));

        return items;
      },
    );
  }
}

Future<void> _showNewOrgDialog(BuildContext context, AppState state) async {
  final ctrl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? error;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('New organization'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null)
              Text(error!,
                  style:
                      TextStyle(color: Theme.of(ctx).colorScheme.error)),
            TextFormField(
              controller: ctrl,
              decoration:
                  const InputDecoration(labelText: 'Organization name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required.' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                final org = await state.api
                    .createOrganization(name: ctrl.text.trim());
                await state.loadOrganizations();
                final created =
                    state.organizations.where((o) => o.id == org.id).firstOrNull;
                if (created != null) await state.selectOrg(created);
                if (ctx.mounted) Navigator.pop(ctx);
              } on ApiException catch (e) {
                set(() => error = e.message);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
}

Future<void> _showNewProjectDialog(
    BuildContext context, AppState state) async {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  String status = 'ACTIVE';
  DateTime? startDate;
  DateTime? dueDate;
  final formKey = GlobalKey<FormState>();
  String? error;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('New project'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error)),
                ),
              TextFormField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Project name *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: projectStatuses
                    .map((s) =>
                        DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => set(() => status = v!),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start date'),
                subtitle: Text(dateLabel(isoDateOnly(startDate))),
                trailing: const Icon(Icons.calendar_today_outlined,
                    size: 18),
                onTap: () async {
                  final d = await pickDate(ctx, initial: startDate);
                  if (d != null) set(() => startDate = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due date'),
                subtitle: Text(dateLabel(isoDateOnly(dueDate))),
                trailing:
                    const Icon(Icons.event_outlined, size: 18),
                onTap: () async {
                  final d = await pickDate(ctx, initial: dueDate);
                  if (d != null) set(() => dueDate = d);
                },
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                final project = await state.api.createProject(
                  orgId: state.selectedOrg!.id,
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  startDate: isoDateOnly(startDate),
                  dueDate: isoDateOnly(dueDate),
                  status: status,
                );
                await state.loadOrganizations();
                final created = state.projects
                    .where((p) => p.id == project.id)
                    .firstOrNull;
                if (created != null) await state.selectProject(created);
                if (ctx.mounted) Navigator.pop(ctx);
              } on ApiException catch (e) {
                set(() => error = e.message);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
  nameCtrl.dispose();
  descCtrl.dispose();
}

class _NavItem {
  const _NavItem(
      {required this.label,
      required this.icon,
      required this.activeIcon});
  final String label;
  final IconData icon;
  final IconData activeIcon;
}
