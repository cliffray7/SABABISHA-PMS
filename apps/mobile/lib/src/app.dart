import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
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
  ThemeMode _themeMode = ThemeMode.light;
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
      final account = await _api.account();
      _appState.account = account;
      await _appState.loadOrganizations();
      await _appState.loadNotifications();
      return _appState.account != null;
    } on ApiException {
      await _sessions.clear();
      return false;
    } catch (_) {
      return false;
    }
  }

  void _handleSignedIn() {
    final future = _tryRestore();
    setState(() {
      _init = future;
    });
  }

  void _handleSignedOut() {
    _init = Future.value(false);
    setState(() {});
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
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
                backgroundColor: kPage,
                body: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(kViolet),
                  ),
                ),
              );
            }
            if (snap.data == true) {
              return _HomeShell(
                onSignedOut: _handleSignedOut,
                onToggleTheme: _toggleTheme,
                themeMode: _themeMode,
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
    final isLight = brightness == Brightness.light;
    final base = isLight ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      // ── DM Sans font — exact match to web ──────────────────────────────
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.dmSansTextTheme(base.primaryTextTheme),

      // ── Color scheme ──────────────────────────────────────────────────
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4D40ED),
        brightness: brightness,
        primary: const Color(0xFF4D40ED),
        onPrimary: Colors.white,
        secondary: kVioletLight,
        onSecondary: const Color(0xFF4D40ED),
        error: kDanger,
        surface: isLight ? kPanel : kPanelDark,
        onSurface: isLight ? kInk : const Color(0xFFEEF0F8),
        outline: kMuted,
        outlineVariant: kLine,
        surfaceContainerLowest: isLight ? kPage : kPageDark,
        surfaceContainerLow: isLight ? const Color(0xFFF7F7FA) : const Color(0xFF1A1C26),
        surfaceContainerHighest: isLight ? const Color(0xFFEEEDFF) : const Color(0xFF2A2D38),
      ),

      scaffoldBackgroundColor: isLight ? kPage : kPageDark,

      // ── AppBar — 56px height, white bg, 1px bottom border, no shadow ──
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? kPanel : kPanelDark,
        foregroundColor: isLight ? kInk : const Color(0xFFEEF0F8),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isLight ? kInk : const Color(0xFFEEF0F8),
        ),
        iconTheme: IconThemeData(
          color: isLight ? kInk : const Color(0xFFEEF0F8),
        ),
        shape: Border(
          bottom: BorderSide(
            color: isLight ? kLine : const Color(0xFF343845),
            width: 1,
          ),
        ),
        toolbarHeight: 56,
      ),

      // ── NavigationBar — web sidebar nav aesthetics ─────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? kPanel : kPanelDark,
        surfaceTintColor: Colors.transparent,
        indicatorColor: kVioletLight,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? kViolet : kMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? kViolet : kMuted,
            size: 22,
          );
        }),
      ),

      // ── Card — 0 elevation, 1px border, radius 8 ──────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? kPanel : kPanelDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isLight ? kLine : const Color(0xFF343845),
          ),
        ),
        margin: const EdgeInsets.only(bottom: 8),
      ),

      // ── Divider ───────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: kLine,
        thickness: 1,
        space: 1,
      ),

      // ── Input fields — 1px border, radius 4, 14px, 32px height ───────
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: kLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: kLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: kViolet, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: kDanger),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
        fillColor: isLight ? kPanel : const Color(0xFF252834),
        filled: true,
        labelStyle: const TextStyle(fontSize: 13, color: kMuted),
        hintStyle: const TextStyle(fontSize: 13, color: kMuted),
        helperStyle: const TextStyle(fontSize: 12, color: kMuted),
        errorStyle: const TextStyle(fontSize: 12, color: kDanger),
      ),

      // ── FilledButton — exact web .primary ─────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kViolet,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 36),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),

      // ── OutlinedButton — exact web .secondary ─────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isLight ? kInk : const Color(0xFFEEF0F8),
          minimumSize: const Size(0, 36),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          side: const BorderSide(color: kLine),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // ── TextButton — link-button style ───────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kViolet,
          textStyle: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w600),
          minimumSize: const Size(0, 32),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),

      // ── Checkbox ─────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? kViolet : null),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),

      // ── ListTile ──────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minLeadingWidth: 0,
        visualDensity: VisualDensity.compact,
      ),

      // ── TabBar — matching web .view-tabs ──────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: kViolet,
        unselectedLabelColor: kMuted,
        labelStyle: GoogleFonts.dmSans(
            fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w400),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: kViolet, width: 2),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: kLine,
      ),

      // ── SegmentedButton ───────────────────────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: isLight ? const Color(0xFFF7F7FA) : kPanelDark,
          selectedBackgroundColor: kVioletLight,
          selectedForegroundColor: kViolet,
          foregroundColor: kMuted,
          side: const BorderSide(color: kLine),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.dmSans(fontSize: 12),
          minimumSize: const Size(0, 32),
        ),
      ),

      // ── ProgressIndicator — violet ───────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: kViolet,
        linearTrackColor: Color(0xFFE6E6ED),
      ),

      // ── Chip — role pill style ────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:
            isLight ? const Color(0xFFF0F0F6) : const Color(0xFF2A2D38),
        labelStyle: GoogleFonts.dmSans(
            fontSize: 11, color: const Color(0xFF777987)),
        padding: EdgeInsets.zero,
        labelPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),

      // ── Switch ────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? kViolet
                : Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? kVioletLight
                : kLine),
      ),

      // ── PopupMenu / DropdownMenu ──────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: isLight ? kPanel : kPanelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: kLine),
        ),
        elevation: 4,
        textStyle: GoogleFonts.dmSans(fontSize: 14, color: isLight ? kInk : const Color(0xFFEEF0F8)),
      ),

      // ── AlertDialog ───────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? kPanel : kPanelDark,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        titleTextStyle: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isLight ? kInk : const Color(0xFFEEF0F8)),
        contentTextStyle: GoogleFonts.dmSans(
            fontSize: 14,
            color: isLight ? kInk : const Color(0xFFEEF0F8)),
      ),

      // ── SnackBar ──────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? kInk : const Color(0xFF2A2D38),
        contentTextStyle: GoogleFonts.dmSans(fontSize: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _HomeShell — App bar + bottom nav matching web topbar + sidebar
// ═══════════════════════════════════════════════════════════════════════════════

class _HomeShell extends StatefulWidget {
  const _HomeShell({
    required this.onSignedOut,
    required this.onToggleTheme,
    required this.themeMode,
  });
  final VoidCallback onSignedOut;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final unread = state.unreadCount;
    final project = state.selectedProject;
    final org = state.selectedOrg;
    final isDark = widget.themeMode == ThemeMode.dark;
    final canWrite = _navIndex == 1 && (project?.canWrite ?? false);

    return Scaffold(
      // ── App bar — matches web topbar ────────────────────────────────────
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 16,
        // Title: eyebrow + project/screen name (web crumb style)
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (org != null)
              Eyebrow(
                org.name + (_navIndex == 0 ? ' / OVERVIEW' : _navIndex == 1 ? ' / PROJECT' : ''),
              ),
            Text(
              _pageTitle(state),
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          // ── Notification bell with red dot (matching web .unread-dot) ──
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  _navIndex == 3
                      ? Icons.notifications
                      : Icons.notifications_outlined,
                  size: 22,
                ),
                onPressed: () => setState(() => _navIndex = 3),
                tooltip: 'Notifications',
              ),
              if (unread > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // ── New task button when on board ────────────────────────────────
          if (canWrite)
            IconButton(
              icon: const Icon(Icons.add_task_outlined, size: 22),
              onPressed: () => _openNewTask(context, state),
              tooltip: 'New task',
            ),

          // ── Org + project picker (matching web .crumb dropdowns) ─────────
          _OrgProjectPicker(state: state),
          const SizedBox(width: 4),
        ],
      ),

      // ── Body ─────────────────────────────────────────────────────────────
      body: Column(children: [
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ErrorBanner(state.error!, onDismiss: state.clearError),
          ),
        Expanded(child: _buildPage(state)),
      ]),

      // ── FAB for new task on board ─────────────────────────────────────────
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openNewTask(context, state),
              backgroundColor: kViolet,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(
                'New task',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
              ),
            )
          : null,

      // ── Bottom navigation — matches web sidebar items ─────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF343845) : kLine,
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: (i) => setState(() => _navIndex = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            // Dashboard
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            // Board
            const NavigationDestination(
              icon: Icon(Icons.view_kanban_outlined),
              selectedIcon: Icon(Icons.view_kanban),
              label: 'Board',
            ),
            // Members
            const NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group),
              label: 'Members',
            ),
            // Notifications with badge
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 9 ? '9+' : '$unread'),
                backgroundColor: kViolet,
                child: const Icon(Icons.notifications_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 9 ? '9+' : '$unread'),
                backgroundColor: kViolet,
                child: const Icon(Icons.notifications),
              ),
              label: 'Notifications',
            ),
            // Settings
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  String _pageTitle(AppState state) {
    switch (_navIndex) {
      case 0:
        final account = state.account;
        return account != null
            ? 'Welcome, ${account.firstName}'
            : 'Dashboard';
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
            final project = state.projects
                .where((p) => p.id == projectId)
                .firstOrNull;
            if (project != null) {
              await state.selectProject(project);
              setState(() => _navIndex = 1);
            }
          },
        );
      case 4:
        return SettingsScreen(
          onSignedOut: widget.onSignedOut,
          onToggleTheme: widget.onToggleTheme,
          themeMode: widget.themeMode,
        );
      default:
        return const SizedBox.shrink();
    }
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
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _OrgProjectPicker — popup matching web .crumb org/project selectors
// ═══════════════════════════════════════════════════════════════════════════════

class _OrgProjectPicker extends StatelessWidget {
  const _OrgProjectPicker({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune_outlined, size: 20),
      tooltip: 'Switch workspace',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: kLine),
      ),
      onSelected: (_) {},
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<String>>[];

        // ── Organizations section ──────────────────────────────────────
        if (state.organizations.isNotEmpty) {
          items.add(const PopupMenuItem(
            enabled: false,
            height: 28,
            child: Text(
              'ORGANIZATIONS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: kMuted,
              ),
            ),
          ));
          for (final org in state.organizations) {
            final selected = state.selectedOrg?.id == org.id;
            items.add(PopupMenuItem(
              value: 'org:${org.id}',
              child: Row(children: [
                SizedBox(
                  width: 20,
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: kViolet)
                      : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    org.name,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                RoleChip(org.role),
              ]),
              onTap: () => state.selectOrg(org),
            ));
          }
          items.add(const PopupMenuDivider());
        }

        // ── Projects section ───────────────────────────────────────────
        if (state.projects.isNotEmpty) {
          items.add(const PopupMenuItem(
            enabled: false,
            height: 28,
            child: Text(
              'PROJECTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: kMuted,
              ),
            ),
          ));
          for (final project in state.projects) {
            final selected = state.selectedProject?.id == project.id;
            items.add(PopupMenuItem(
              value: 'proj:${project.id}',
              child: Row(children: [
                SizedBox(
                  width: 20,
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: kViolet)
                      : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    project.name,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ),
              ]),
              onTap: () => state.selectProject(project),
            ));
          }
          items.add(const PopupMenuDivider());
        }

        // ── Create new ────────────────────────────────────────────────
        items.add(PopupMenuItem(
          value: '__new_org__',
          child: Row(children: [
            const SizedBox(width: 26),
            const Icon(Icons.add, size: 18, color: kViolet),
            const SizedBox(width: 8),
            Text(
              'New organization',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: kViolet, fontWeight: FontWeight.w600),
            ),
          ]),
          onTap: () => _showNewOrgDialog(context, state),
        ));
        if (state.selectedOrg != null) {
          items.add(PopupMenuItem(
            value: '__new_proj__',
            child: Row(children: [
              const SizedBox(width: 26),
              const Icon(Icons.add, size: 18, color: kViolet),
              const SizedBox(width: 8),
              Text(
                'New project',
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: kViolet, fontWeight: FontWeight.w600),
              ),
            ]),
            onTap: () => _showNewProjectDialog(context, state),
          ));
        }

        return items;
      },
    );
  }
}

// ─── New organization dialog ──────────────────────────────────────────────────

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
              ErrorBanner(error!, onDismiss: () => set(() => error = null)),
            TextFormField(
              controller: ctrl,
              decoration:
                  const InputDecoration(labelText: 'Organization name'),
              autofocus: true,
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
                final org =
                    await state.api.createOrganization(name: ctrl.text.trim());
                await state.loadOrganizations();
                final created = state.organizations
                    .where((o) => o.id == org.id)
                    .firstOrNull;
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

// ─── New project dialog ───────────────────────────────────────────────────────

Future<void> _showNewProjectDialog(BuildContext context, AppState state) async {
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
                ErrorBanner(
                    error!, onDismiss: () => set(() => error = null)),
              TextFormField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Project name *'),
                autofocus: true,
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
                dense: true,
                title: const Text('Start date'),
                subtitle: Text(
                  dateLabel(isoDateOnly(startDate)),
                  style: const TextStyle(color: kMuted),
                ),
                trailing: const Icon(Icons.calendar_today_outlined,
                    size: 18),
                onTap: () async {
                  final d = await pickDate(ctx, initial: startDate);
                  if (d != null) set(() => startDate = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Due date'),
                subtitle: Text(
                  dateLabel(isoDateOnly(dueDate)),
                  style: const TextStyle(color: kMuted),
                ),
                trailing: const Icon(Icons.event_outlined, size: 18),
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
