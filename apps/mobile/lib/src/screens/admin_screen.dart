import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';

// ─── Palette (mirrors web + app.dart) ─────────────────────────────────────────
const _kViolet = Color(0xFF4D40ED);
const _kVioletLight = Color(0xFFEEEDFF);
const _kDanger = Color(0xFFEF4444);
const _kWarning = Color(0xFFF59E0B);
const _kSuccess = Color(0xFF22C55E);
const _kMuted = Color(0xFF9EA3B0);
const _kLine = Color(0xFFE5E7EB);
const _kLineDark = Color(0xFF343845);
const _eatOffset = Duration(hours: 3);

DateTime _eatNow() => DateTime.now().toUtc().add(_eatOffset);

DateTime _dateInEat(String value) {
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return DateTime.parse(value);
  }
  final parsed = DateTime.parse(value);
  if (!RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$', caseSensitive: false)
      .hasMatch(value)) {
    return DateTime(parsed.year, parsed.month, parsed.day, parsed.hour,
        parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
  }
  return parsed.toUtc().add(_eatOffset);
}

String _dateOnly(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

// ═══════════════════════════════════════════════════════════════════════════════
// Section enum — mirrors web AdminNav exactly
// ═══════════════════════════════════════════════════════════════════════════════

enum _AdminSection {
  overview,
  analytics,
  users,
  organizations,
  projects,
  activity,
  audit,
  health,
  reports,
  platformSettings,
  accountSettings,
}

extension _AdminSectionExt on _AdminSection {
  String get label {
    switch (this) {
      case _AdminSection.overview:
        return 'Overview';
      case _AdminSection.analytics:
        return 'Analytics';
      case _AdminSection.users:
        return 'Users';
      case _AdminSection.organizations:
        return 'Organizations';
      case _AdminSection.projects:
        return 'Projects';
      case _AdminSection.activity:
        return 'Activity';
      case _AdminSection.audit:
        return 'Audit Trail';
      case _AdminSection.health:
        return 'System Health';
      case _AdminSection.reports:
        return 'Reports';
      case _AdminSection.platformSettings:
        return 'Platform Settings';
      case _AdminSection.accountSettings:
        return 'Account & Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case _AdminSection.overview:
        return Icons.dashboard_outlined;
      case _AdminSection.analytics:
        return Icons.bar_chart_outlined;
      case _AdminSection.users:
        return Icons.people_outlined;
      case _AdminSection.organizations:
        return Icons.business_outlined;
      case _AdminSection.projects:
        return Icons.folder_outlined;
      case _AdminSection.activity:
        return Icons.show_chart;
      case _AdminSection.audit:
        return Icons.history;
      case _AdminSection.health:
        return Icons.favorite_border;
      case _AdminSection.reports:
        return Icons.file_download_outlined;
      case _AdminSection.platformSettings:
        return Icons.settings_outlined;
      case _AdminSection.accountSettings:
        return Icons.manage_accounts_outlined;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case _AdminSection.overview:
        return Icons.dashboard;
      case _AdminSection.analytics:
        return Icons.bar_chart;
      case _AdminSection.users:
        return Icons.people;
      case _AdminSection.organizations:
        return Icons.business;
      case _AdminSection.projects:
        return Icons.folder;
      case _AdminSection.activity:
        return Icons.show_chart;
      case _AdminSection.audit:
        return Icons.history;
      case _AdminSection.health:
        return Icons.favorite;
      case _AdminSection.reports:
        return Icons.file_download;
      case _AdminSection.platformSettings:
        return Icons.settings;
      case _AdminSection.accountSettings:
        return Icons.manage_accounts;
    }
  }
}

// ─── Nav group definitions (mirrors web AdminNav sections) ────────────────────
const _navGroups = [
  _NavGroup('PLATFORM', [_AdminSection.overview, _AdminSection.analytics]),
  _NavGroup('MANAGEMENT', [
    _AdminSection.users,
    _AdminSection.organizations,
    _AdminSection.projects
  ]),
  _NavGroup('MONITORING',
      [_AdminSection.activity, _AdminSection.audit, _AdminSection.health]),
  _NavGroup('REPORTING', [_AdminSection.reports]),
  _NavGroup('ADMINISTRATION', [_AdminSection.platformSettings]),
  _NavGroup('ACCOUNT', [_AdminSection.accountSettings]),
];

class _NavGroup {
  const _NavGroup(this.label, this.items);
  final String label;
  final List<_AdminSection> items;
}

// ═══════════════════════════════════════════════════════════════════════════════
// AdminScreen
// Full-screen experience: no bottom nav bar. A branded side drawer handles
// all navigation. The AppBar carries the section title and a back-to-app
// button so the user is never stranded.
// ═══════════════════════════════════════════════════════════════════════════════

class AdminScreen extends StatefulWidget {
  const AdminScreen({
    super.key,
    required this.onSignedOut,
    required this.onToggleTheme,
    required this.themeMode,
  });

  final VoidCallback onSignedOut;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  _AdminSection _section = _AdminSection.overview;
  String? _adminOrganizationFilterId;
  ThemeMode _adminThemeMode = ThemeMode.light;

  void _toggleAdminTheme() {
    setState(() {
      _adminThemeMode =
          _adminThemeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void _navigate(_AdminSection s) {
    setState(() {
      _section = s;
      if (s == _AdminSection.projects) _adminOrganizationFilterId = null;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _openOrganizationProjects(String organizationId) {
    setState(() {
      _adminOrganizationFilterId = organizationId;
      _section = _AdminSection.projects;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> _signOut() async {
    await context.read<AppState>().api.logout();
    widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _adminThemeMode == ThemeMode.dark;
    final bg = isDark ? const Color(0xFF13151F) : const Color(0xFFF4F5FA);
    final border = isDark ? _kLineDark : _kLine;
    final baseTheme = Theme.of(context);

    return Theme(
      data: baseTheme.copyWith(
        brightness: isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: bg,
        colorScheme: baseTheme.colorScheme.copyWith(
          brightness: isDark ? Brightness.dark : Brightness.light,
          surface: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: bg,

        // ── AppBar ─────────────────────────────────────────────────────────────
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1B1D2A) : Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 56,
          automaticallyImplyLeading: true,
          shape: Border(bottom: BorderSide(color: border, width: 1)),

          // Compact platform breadcrumb mirrors the web admin mobile header.
          title: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Platform',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: _kViolet,
                    ),
                  ),
                  Text(
                    _section.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ],
          ),

          actions: [
            IconButton(
              tooltip: 'Search admin pages',
              onPressed: () => _showAdminPageSearch(context),
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: isDark ? 'Use light theme' : 'Use dark theme',
              onPressed: _toggleAdminTheme,
              icon: Icon(isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => _navigate(_AdminSection.accountSettings),
                child: AvatarChip(
                  initials: _accountInitials(context.watch<AppState>().account),
                  avatarUrl: context.watch<AppState>().account?.avatarUrl,
                  size: 34,
                ),
              ),
            ),
          ],
        ),

        // ── Side drawer ────────────────────────────────────────────────────────
        drawer: _AdminDrawer(
          current: _section,
          onNavigate: _navigate,
          isDark: isDark,
          account: context.watch<AppState>().account,
          onSignedOut: _signOut,
        ),

        // ── Content ────────────────────────────────────────────────────────────
        body: _buildSection(),
      ),
    );
  }

  Widget _buildSection() {
    switch (_section) {
      case _AdminSection.overview:
        return const _AdminOverview();
      case _AdminSection.analytics:
        return const _AdminAnalytics();
      case _AdminSection.users:
        return const _AdminUsers();
      case _AdminSection.organizations:
        return _AdminOrganizations(onOpenProjects: _openOrganizationProjects);
      case _AdminSection.projects:
        return _AdminProjects(organizationFilterId: _adminOrganizationFilterId);
      case _AdminSection.activity:
        return const _AdminActivity();
      case _AdminSection.audit:
        return const _AdminAuditTrail();
      case _AdminSection.health:
        return const _AdminHealth();
      case _AdminSection.reports:
        return const _AdminReports();
      case _AdminSection.platformSettings:
        return const _AdminPlatformSettings();
      case _AdminSection.accountSettings:
        return SettingsScreen(
          onSignedOut: widget.onSignedOut,
          onToggleTheme: _toggleAdminTheme,
          themeMode: _adminThemeMode,
        );
    }
  }

  Future<void> _showAdminPageSearch(BuildContext context) async {
    final searchController = TextEditingController();
    final sections = _navGroups.expand((group) => group.items).toList();
    final section = await showDialog<_AdminSection>(
      context: context,
      builder: (dialogContext) => Theme(
        data: Theme.of(context).copyWith(
          brightness: _adminThemeMode == ThemeMode.dark
              ? Brightness.dark
              : Brightness.light,
          colorScheme: Theme.of(context).colorScheme.copyWith(
                brightness: _adminThemeMode == ThemeMode.dark
                    ? Brightness.dark
                    : Brightness.light,
              ),
        ),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchController.text.trim().toLowerCase();
            final results = sections
                .where((item) => item.label.toLowerCase().contains(query))
                .toList();
            return AlertDialog(
              title: const Text('Search platform pages'),
              content: SizedBox(
                width: 380,
                height: 360,
                child: Column(children: [
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search pages and tools',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: results.isEmpty
                        ? const Center(child: Text('No pages found.'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final item = results[index];
                              return ListTile(
                                leading: Icon(item.icon),
                                title: Text(item.label),
                                onTap: () => Navigator.pop(dialogContext, item),
                              );
                            },
                          ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
    searchController.dispose();
    if (section != null && mounted) _navigate(section);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Side Drawer
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({
    required this.current,
    required this.onNavigate,
    required this.isDark,
    required this.account,
    required this.onSignedOut,
  });

  final _AdminSection current;
  final void Function(_AdminSection) onNavigate;
  final bool isDark;
  final Account? account;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1B1D2A) : Colors.white;
    final border = isDark ? _kLineDark : _kLine;

    return Drawer(
      width: 270,
      backgroundColor: bg,
      shape: Border(right: BorderSide(color: border)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Branded header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(children: [
                const TaskFlowBrand(
                    iconSize: 36, textSize: 15, showWordmark: false),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TaskFlow',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                      ),
                    ),
                    Text('Super Admin',
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : _kMuted)),
                  ],
                ),
              ]),
            ),
            Divider(height: 1, color: border),
            const SizedBox(height: 8),

            // ── Nav groups ──────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                children: [
                  for (final group in _navGroups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                      child: Text(
                        group.label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: _kMuted,
                        ),
                      ),
                    ),
                    for (final s in group.items)
                      _DrawerTile(
                        section: s,
                        selected: s == current,
                        isDark: isDark,
                        onTap: () => onNavigate(s),
                      ),
                  ],
                ],
              ),
            ),

            // ── Version footer ──────────────────────────────────────────────
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      AvatarChip(
                          initials: account == null
                              ? 'SA'
                              : '${account!.firstName.isNotEmpty ? account!.firstName[0] : ''}${account!.lastName.isNotEmpty ? account!.lastName[0] : ''}',
                          avatarUrl: account?.avatarUrl,
                          size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                account == null
                                    ? 'Super Admin'
                                    : '${account!.firstName} ${account!.lastName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1D2E))),
                            Text(account?.email ?? 'Platform administrator',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10, color: _kMuted)),
                          ])),
                      IconButton(
                          tooltip: 'Sign out',
                          onPressed: onSignedOut,
                          icon: const Icon(Icons.logout, size: 18)),
                    ]),
                    const SizedBox(height: 8),
                    const Text('TaskFlow · Platform console',
                        style: TextStyle(fontSize: 10, color: _kMuted)),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.section,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final _AdminSection section;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? _kViolet.withValues(alpha: 0.18) : _kVioletLight)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(
              selected ? section.selectedIcon : section.icon,
              size: 18,
              color: selected ? _kViolet : _kMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                section.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected
                      ? _kViolet
                      : (isDark ? Colors.white70 : const Color(0xFF3A3F5C)),
                ),
              ),
            ),
            if (selected)
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: _kViolet,
                  shape: BoxShape.circle,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared section scaffold — consistent page padding & pull-to-refresh
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionPage extends StatelessWidget {
  const _SectionPage({
    required this.child,
    this.onRefresh,
  });

  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scrollable = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: child,
    );
    if (onRefresh != null) {
      return RefreshIndicator(
        color: _kViolet,
        onRefresh: onRefresh!,
        child: scrollable,
      );
    }
    return scrollable;
  }
}

// ─── Section heading widget ───────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    this.action,
    this.badge,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badge == null)
                  Text(title,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700))
                else
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      badge!,
                    ],
                  ),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(fontSize: 13, color: _kMuted)),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1 — Overview
// ═══════════════════════════════════════════════════════════════════════════════

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF8BD3B1) : const Color(0xFF5A9D78);
    return Container(
      constraints: const BoxConstraints(minHeight: 23),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D332B) : const Color(0xFFF4FAF6),
        border: Border.all(
          color: isDark ? const Color(0xFF315B49) : const Color(0xFFDCEEE4),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFF62BD8B),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? const Color(0xFF315B49)
                    : const Color(0xFFE9F7EF),
                spreadRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('Live',
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _AdminOverview extends StatefulWidget {
  const _AdminOverview();

  @override
  State<_AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<_AdminOverview> {
  bool _downloading = false;
  String? _downloadMsg;
  bool _downloadSuccess = false;
  int _days = 30;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadOverview());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (!state.loadingAdminMetrics &&
          !state.loadingAdminAnalytics &&
          !state.loadingAdminProjects) {
        _reloadOverview();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _downloadReport() async {
    setState(() {
      _downloading = true;
      _downloadMsg = null;
    });
    try {
      final bytes = await context.read<AppState>().api.adminReport(format: 'pdf');
      final now = _eatNow();
      final name =
          'taskflow-platform-report-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save platform report',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted) {
        setState(() {
          _downloadSuccess = path != null;
          _downloadMsg =
              path == null ? 'Report save was cancelled.' : 'PDF report saved.';
          _downloading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _downloadSuccess = false;
          _downloadMsg = e.message;
          _downloading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloadSuccess = false;
          _downloadMsg = 'Report download failed. Please try again.';
          _downloading = false;
        });
      }
    }
  }

  Future<void> _reloadOverview() async {
    final now = _eatNow();
    final state = context.read<AppState>();
    await Future.wait<void>([
      state.loadAdminDashboard(),
      state.loadAdminAnalytics(
        from: _dateOnly(now.subtract(Duration(days: _days))),
        to: _dateOnly(now),
      ),
      state.loadAdminProjects(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final m = state.adminMetrics;
    final analytics = state.adminAnalytics;

    final cards = [
      _MetricDef('Total users', Icons.people_outlined, m?.totalUsers),
      _MetricDef(
          'Organizations', Icons.business_outlined, m?.totalOrganizations),
      _MetricDef('Projects', Icons.folder_outlined, m?.totalProjects),
      _MetricDef('Tasks', Icons.format_list_bulleted, m?.totalTasks),
      _MetricDef(
          'Completed tasks', Icons.check_circle_outline, m?.completedTasks),
      _MetricDef('Active projects', Icons.show_chart, m?.activeProjects),
    ];
    final userGrowth = analytics?.userGrowth ?? const <AdminGrowthPoint>[];
    final projectGrowth = analytics?.projectGrowth ?? const <AdminGrowthPoint>[];
    final userTrend = _trendCount(userGrowth, 30);
    final projectTrend = _trendCount(projectGrowth, 30);
    final projectsCreatedInPeriod =
        projectGrowth.fold<int>(0, (sum, point) => sum + point.count);
    final recentProjects = [...state.adminProjects]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final statusPoints = (analytics?.tasksByStatus ?? const <AdminStatusPoint>[])
        .where((point) => point.count > 0)
        .toList();

    return _SectionPage(
      onRefresh: _reloadOverview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            title: _greeting(),
            subtitle: 'Usage and delivery across your platform.',
            badge: const _LiveBadge(),
            action: FilledButton.icon(
              onPressed: _downloading ? null : _downloadReport,
              icon: _downloading
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.file_download_outlined, size: 17),
              label: Text(_downloading ? 'Preparing…' : 'Download report',
                  style: const TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
          ),

          // Metric cards
          if (state.loadingAdminMetrics && m == null)
            const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_kViolet)),
            ))
          else if (m == null)
            const _ErrorBanner('Could not load dashboard metrics.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 120,
              ),
              itemCount: cards.length,
              itemBuilder: (_, i) => _MetricCard(
                def: cards[i],
                trend: i == 0 ? userTrend : i == 2 ? projectTrend : null,
                growth: i == 0 ? userGrowth : i == 2 ? projectGrowth : null,
                trendLabel: i == 0 || i == 2 ? 'created · 30d' : null,
              ),
            ),

          if (analytics == null && state.loadingAdminAnalytics)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (analytics != null) ...[
            const SizedBox(height: 18),
            _AdminPeriodSelector(
              days: _days,
              onChanged: (days) {
                setState(() => _days = days);
                _reloadOverview();
              },
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Project growth',
              subtitle: 'Projects created in the last $_days days',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$projectsCreatedInPeriod created',
                      style: const TextStyle(
                          fontSize: 12,
                          color: _kMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _AdminLineChart(
                    data: analytics.projectGrowth,
                    color: _kViolet,
                    unit: 'projects',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Task status',
              subtitle: 'Current status of tasks created in this period',
              child: _AdminStatusDonut(data: statusPoints),
            ),
          ] else
            const _ErrorBanner('Could not load platform analytics.'),

          if (state.loadingAdminProjects && state.adminProjects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Recent projects',
              subtitle: 'Latest platform projects',
              child: recentProjects.isEmpty && !state.loadingAdminProjects
                  ? const Text('No projects have been created yet.',
                      style: TextStyle(color: _kMuted))
                  : recentProjects.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 20,
                        horizontalMargin: 0,
                        columns: const [
                          DataColumn(label: Text('Project')),
                          DataColumn(label: Text('Organization')),
                          DataColumn(label: Text('Tasks')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Created')),
                        ],
                        rows: recentProjects.take(5).map((project) {
                          return DataRow(cells: [
                            DataCell(SizedBox(
                                width: 130,
                                child: Text(project.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis))),
                            DataCell(SizedBox(
                                width: 110,
                                child: Text(project.organizationName ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis))),
                            DataCell(Text('${project.taskCount}')),
                            DataCell(Text(_prettyLabel(project.displayStatus))),
                            DataCell(Text(_fmtDate(project.createdAt))),
                          ]);
                        }).toList(),
                      ),
                    ),
            ),
          ],

          // Download feedback
          if (_downloadMsg != null) ...[
            const SizedBox(height: 16),
            _FeedbackBanner(message: _downloadMsg!, success: _downloadSuccess),
          ],

          // Hint
        ],
      ),
    );
  }

  String _greeting() {
    final hour = _eatNow().hour;
    final firstName = context.read<AppState>().account?.firstName;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    return firstName == null || firstName.isEmpty
        ? greeting
        : '$greeting, $firstName';
  }

  int _trendCount(List<AdminGrowthPoint> points, int days) {
    final now = _eatNow();
    final today = DateTime.utc(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1));
    return points.where((point) {
      DateTime date;
      try {
        date = _dateInEat(point.date);
      } catch (_) {
        return false;
      }
      final dateKey = DateTime.utc(date.year, date.month, date.day);
      return !dateKey.isBefore(start) &&
          dateKey.isBefore(today.add(const Duration(days: 1)));
    }).fold<int>(0, (sum, point) => sum + point.count);
  }
}

String _accountInitials(Account? account) {
  if (account == null) return 'SA';
  final first = account.firstName.isNotEmpty ? account.firstName[0] : '';
  final last = account.lastName.isNotEmpty ? account.lastName[0] : '';
  final initials = '$first$last';
  return initials.isEmpty ? 'SA' : initials;
}

class _MetricDef {
  const _MetricDef(this.label, this.icon, this.value);
  final String label;
  final IconData icon;
  final int? value;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.def, this.trend, this.growth, this.trendLabel});
  final _MetricDef def;
  final int? trend;
  final List<AdminGrowthPoint>? growth;
  final String? trendLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? _kLineDark : _kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                def.label,
                style: const TextStyle(
                    fontSize: 12, color: _kMuted, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _kViolet.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(def.icon, size: 17, color: const Color(0xFFB9AEFF)),
            ),
          ]),
          Text(
            def.value?.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',') ?? '—',
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
          ),
          if (trend != null) Row(children: [
            Expanded(child: Text('+$trend $trendLabel', style: const TextStyle(fontSize: 10, color: _kMuted), overflow: TextOverflow.ellipsis)),
            SizedBox(
              width: 58,
              height: 22,
              child: CustomPaint(
                painter: _SparklinePainter(
                  values: (growth ?? const <AdminGrowthPoint>[])
                      .map((point) => point.count)
                      .toList()
                      .skip((growth?.length ?? 0) > 7
                          ? (growth!.length - 7)
                          : 0)
                      .toList(),
                  color: _kViolet,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.fold<int>(1, (max, value) => value > max ? value : max);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length < 2 ? size.width / 2 : i * size.width / (values.length - 1);
      final y = size.height - (values[i] / maxValue) * (size.height - 3) - 1.5;
      points.add(Offset(x, y));
    }
    if (points.length == 1) {
      canvas.drawCircle(points.single, 1.5, Paint()..color = color);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _AnalyticsMetricCard extends StatelessWidget {
  const _AnalyticsMetricCard(
      {required this.label,
      required this.value,
      required this.period,
      this.suffix});
  final String label;
  final int value;
  final int period;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? _kLineDark : _kLine),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _kMuted)),
            Text('$value',
                style:
                    const TextStyle(fontSize: 27, fontWeight: FontWeight.w700)),
            Text(suffix ?? 'in $period days',
                style: const TextStyle(fontSize: 11, color: _kMuted)),
          ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2 — Analytics
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminAnalytics extends StatefulWidget {
  const _AdminAnalytics();

  @override
  State<_AdminAnalytics> createState() => _AdminAnalyticsState();
}

class _AdminAnalyticsState extends State<_AdminAnalytics> {
  int _days = 30;
  Timer? _refreshTimer;

  String _from(int d) {
    return _dateOnly(_eatNow().subtract(Duration(days: d)));
  }

  String get _today {
    return _dateOnly(_eatNow());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !context.read<AppState>().loadingAdminAnalytics) _load();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _load() => context
      .read<AppState>()
      .loadAdminAnalytics(from: _from(_days), to: _today);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final a = state.adminAnalytics;
    final hasData = a != null &&
        (a.userGrowth.isNotEmpty ||
            a.projectGrowth.isNotEmpty ||
            a.tasksByStatus.isNotEmpty ||
            a.tasksByPriority.isNotEmpty);

    final newUsers =
        a?.userGrowth.fold<int>(0, (sum, item) => sum + item.count) ?? 0;
    final newProjects =
        a?.projectGrowth.fold<int>(0, (sum, item) => sum + item.count) ?? 0;
    final tasksCreated =
        a?.tasksByPriority.fold<int>(0, (sum, item) => sum + item.count) ?? 0;
    final highPriority = a?.tasksByPriority
            .where((item) => item.label.toUpperCase() == 'HIGH')
            .fold<int>(0, (sum, item) => sum + item.count) ??
        0;

    return _SectionPage(
      onRefresh: () async => _load(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeader(
            title: 'Platform Analytics',
            subtitle: 'Monitor platform growth and task activity.',
          ),

          // Range chips
          Wrap(spacing: 8, children: [
            for (final d in [7, 30, 90])
              ChoiceChip(
                label: Text('$d Days'),
                selected: _days == d,
                onSelected: (_) {
                  setState(() => _days = d);
                  _load();
                },
                selectedColor: Theme.of(context).brightness == Brightness.dark
                    ? _kViolet.withValues(alpha: 0.22)
                    : _kVioletLight,
                labelStyle: TextStyle(
                  color: _days == d ? _kViolet : _kMuted,
                  fontWeight: _days == d ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 13,
                ),
                side: BorderSide(color: _days == d ? _kViolet : _kLine),
                shape: const StadiumBorder(),
              ),
          ]),
          const SizedBox(height: 16),

          if (a != null && hasData) ...[
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                _AnalyticsMetricCard(
                    label: 'New users', value: newUsers, period: _days),
                _AnalyticsMetricCard(
                    label: 'New projects', value: newProjects, period: _days),
                _AnalyticsMetricCard(
                    label: 'Tasks created', value: tasksCreated, period: _days),
                _AnalyticsMetricCard(
                    label: 'High priority',
                    value: highPriority,
                    period: _days,
                    suffix: 'tasks in range'),
              ],
            ),
            const SizedBox(height: 16),
          ],

          if (state.loadingAdminAnalytics && a == null)
            const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_kViolet)),
            ))
          else if (a == null)
            const _ErrorBanner('Could not load analytics.')
          else if (!hasData)
            const _InfoBanner(
                'No platform activity was recorded for this date range.')
          else ...[
            _ChartCard(
              title: 'User Growth',
              subtitle: 'New accounts created each day',
              child: _AdminLineChart(
                data: a.userGrowth,
                color: _kViolet,
                unit: 'new users',
              ),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Project Growth',
              subtitle: 'New projects created each day',
              child: _AdminLineChart(
                data: a.projectGrowth,
                color: const Color(0xFF399779),
                unit: 'new projects',
              ),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Tasks by Status',
              subtitle: 'Current status of tasks created in this period',
              child: _AdminCategoryBarChart(
                data: a.tasksByStatus,
                colorFor: _statusColor,
              ),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Tasks by Priority',
              subtitle: 'Priority of tasks created in this period',
              child: _AdminStatusDonut(
                data: a.tasksByPriority,
                colorFor: _priorityColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child, this.subtitle});
  final String title;
  final Widget child;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? _kLineDark : _kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(subtitle!,
                style: const TextStyle(fontSize: 12, color: _kMuted)),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _AdminPeriodSelector extends StatelessWidget {
  const _AdminPeriodSelector({required this.days, required this.onChanged});
  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [7, 30, 90].map((value) {
          final selected = value == days;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: value == 90 ? 0 : 6),
              child: OutlinedButton(
                onPressed: () => onChanged(value),
                style: OutlinedButton.styleFrom(
                  backgroundColor:
                      selected ? _kViolet.withValues(alpha: 0.2) : null,
                  foregroundColor: selected
                      ? (isDark ? const Color(0xFFC2B8FF) : _kViolet)
                      : null,
                  side: BorderSide(
                      color:
                          selected ? _kViolet : (isDark ? _kLineDark : _kLine)),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                ),
                child:
                    Text('Last $value days',
                        style: const TextStyle(fontSize: 12)),
              ),
            ),
          );
        }).toList(),
      );
}

class _AdminLineChart extends StatelessWidget {
  const _AdminLineChart(
      {required this.data, required this.color, required this.unit});
  final List<AdminGrowthPoint> data;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
          height: 160,
          child: Center(
              child: Text('No data for this period.',
                  style: TextStyle(color: _kMuted))));
    }
    final points = data;
    final max = points
        .map((point) => point.count)
        .fold<int>(1, (a, b) => a > b ? a : b);
    return Column(children: [
      SizedBox(
        height: 170,
        width: double.infinity,
        child: CustomPaint(
          painter: _AdminLinePainter(
              values: points.map((point) => point.count).toList(),
              max: max,
              color: color,
              isDark: Theme.of(context).brightness == Brightness.dark),
          child: Tooltip(
            message: '${points.last.count} $unit',
            child: const SizedBox.expand(),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_compactDate(points.first.date),
            style: const TextStyle(fontSize: 11, color: _kMuted)),
        Text(_compactDate(points.last.date),
            style: const TextStyle(fontSize: 11, color: _kMuted)),
      ]),
    ]);
  }
}

class _AdminLinePainter extends CustomPainter {
  _AdminLinePainter(
      {required this.values,
      required this.max,
      required this.color,
      required this.isDark});
  final List<int> values;
  final int max;
  final Color color;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 24.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 8.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.09)
      ..strokeWidth = 1;
    const labelStyle = TextStyle(color: _kMuted, fontSize: 10);
    for (var step = 0; step <= 4; step++) {
      final y = top + chartHeight * step / 4;
      canvas.drawLine(
          Offset(left, y), Offset(size.width - right, y), gridPaint);
      final value = (max * (4 - step) / 4).round();
      final painter = TextPainter(
          text: TextSpan(text: '$value', style: labelStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      painter.paint(
          canvas, Offset(left - painter.width - 5, y - painter.height / 2));
    }
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = left +
          (values.length <= 1
              ? chartWidth / 2
              : chartWidth * index / (values.length - 1));
      final y = top + chartHeight * (1 - values[index] / max);
      points.add(Offset(x, y));
    }
    if (points.isEmpty) return;
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final area = Path.from(line)
      ..lineTo(points.last.dx, size.height - bottom)
      ..lineTo(points.first.dx, size.height - bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(points.last, 4.5, Paint()..color = color);
    canvas.drawCircle(points.last, 2,
        Paint()..color = isDark ? const Color(0xFF1B1D2A) : Colors.white);
  }

  @override
  bool shouldRepaint(covariant _AdminLinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.max != max ||
      oldDelegate.color != color ||
      oldDelegate.isDark != isDark;
}

class _AdminCategoryBarChart extends StatelessWidget {
  const _AdminCategoryBarChart({required this.data, required this.colorFor});
  final List<AdminStatusPoint> data;
  final Color Function(String) colorFor;

  @override
  Widget build(BuildContext context) {
    final values = data.where((item) => item.count > 0).toList();
    if (values.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text('No task status data is available yet.',
              style: TextStyle(color: _kMuted)),
        ),
      );
    }
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: CustomPaint(
        painter: _AdminCategoryBarPainter(
          values: values,
          colorFor: colorFor,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _AdminCategoryBarPainter extends CustomPainter {
  _AdminCategoryBarPainter({
    required this.values,
    required this.colorFor,
    required this.isDark,
  });

  final List<AdminStatusPoint> values;
  final Color Function(String) colorFor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const right = 8.0;
    const top = 10.0;
    const bottom = 32.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final max = values.map((item) => item.count).reduce((a, b) => a > b ? a : b);
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.09)
      ..strokeWidth = 1;
    const tickStyle = TextStyle(color: _kMuted, fontSize: 10);
    for (var step = 0; step <= 4; step++) {
      final y = top + chartHeight * step / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
      final count = (max * (4 - step) / 4).round();
      final label = TextPainter(
        text: TextSpan(text: '$count', style: tickStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(left - label.width - 6, y - label.height / 2));
    }

    final slotWidth = chartWidth / values.length;
    final barWidth = (slotWidth * 0.52).clamp(12.0, 42.0).toDouble();
    for (var index = 0; index < values.length; index++) {
      final item = values[index];
      final height = chartHeight * item.count / max;
      final x = left + slotWidth * index + (slotWidth - barWidth) / 2;
      final y = top + chartHeight - height;
      final rect = Rect.fromLTWH(x, y, barWidth, height);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
        ),
        Paint()..color = colorFor(item.label),
      );
      final text = _prettyLabel(item.label);
      final label = TextPainter(
        text: TextSpan(text: text, style: tickStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: slotWidth - 2);
      label.paint(
        canvas,
        Offset(left + slotWidth * index + (slotWidth - label.width) / 2,
            size.height - label.height - 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AdminCategoryBarPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.isDark != isDark;
}

class _AdminStatusDonut extends StatelessWidget {
  const _AdminStatusDonut({required this.data, this.colorFor = _statusColor});
  final List<AdminStatusPoint> data;
  final Color Function(String) colorFor;

  @override
  Widget build(BuildContext context) {
    final items = data.where((item) => item.count > 0).toList();
    final total = items.fold<int>(0, (sum, item) => sum + item.count);
    final colors = items.map((item) => colorFor(item.label)).toList();
    if (total == 0) {
      return const Text('No task status data is available yet.',
          style: TextStyle(color: _kMuted));
    }
    return Column(children: [
      SizedBox(
        height: 205,
        child: Center(
          child: SizedBox(
            width: 176,
            height: 176,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(
                  size: const Size.square(176),
                  painter: _DonutPainter(
                      values: items.map((item) => item.count).toList(),
                      colors: colors)),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$total',
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w700)),
                const Text('tasks',
                    style: TextStyle(fontSize: 12, color: _kMuted)),
              ]),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (var index = 0; index < items.length; index++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: colors[index], shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(_prettyLabel(items[index].label),
                    style: const TextStyle(color: _kMuted))),
            Text('${(items[index].count * 100 / total).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors});
  final List<int> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 23
      ..strokeCap = StrokeCap.round;
    var start = -1.5708;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * 6.28318;
      paint.color = colors[index % colors.length];
      canvas.drawArc(rect.deflate(14), start + 0.025,
          (sweep - 0.05).clamp(0.0, 6.28318).toDouble(), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _RecentProjectRow extends StatelessWidget {
  const _RecentProjectRow(
      {required this.project,
      required this.isDark,
      required this.organizationName});
  final AdminProject project;
  final bool isDark;
  final String organizationName;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF17181E) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? _kLineDark : _kLine),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: _kViolet.withValues(alpha: 0.17),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.folder_outlined,
                  size: 19, color: Color(0xFFB9AEFF))),
          const SizedBox(height: 10),
          Text(project.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(organizationName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: _kMuted)),
        ]),
      );
}

String _compactDate(String value) {
  DateTime parsed;
  try {
    parsed = _dateInEat(value);
  } catch (_) {
    return value;
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[parsed.month - 1]} ${parsed.day}';
}

String _prettyLabel(String value) => value
    .toLowerCase()
    .split(RegExp(r'[_ ]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

Color _statusColor(String status) {
  switch (status.trim().toUpperCase().replaceAll('_', ' ')) {
    case 'DONE':
    case 'COMPLETED':
      return const Color(0xFF369875);
    case 'IN PROGRESS':
      return const Color(0xFF6C5CE7);
    case 'REVIEW':
      return const Color(0xFFD39B36);
    case 'TO DO':
      return const Color(0xFF9A9AA5);
    default:
      return const Color(0xFF5590D1);
  }
}

Color _priorityColor(String priority) {
  switch (priority.trim().toUpperCase()) {
    case 'HIGH':
      return const Color(0xFFD65B63);
    case 'MEDIUM':
      return const Color(0xFFD49335);
    case 'LOW':
      return const Color(0xFF9696A3);
    default:
      return _kViolet;
  }
}

class _HorizBar extends StatelessWidget {
  const _HorizBar({required this.data, required this.color});
  final List<AdminStatusPoint> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Text('No data for this period.',
          style: TextStyle(color: _kMuted, fontSize: 13));
    }
    final total = data.fold<int>(0, (s, e) => s + e.count);
    return Column(
      children: data.map((pt) {
        final ratio = total > 0 ? pt.count / total : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(pt.label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500)),
                  Text('${pt.count}',
                      style: const TextStyle(fontSize: 12, color: _kMuted)),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: ratio,
                backgroundColor: _kLine,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3 — Users
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminUsers extends StatefulWidget {
  const _AdminUsers();

  @override
  State<_AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<_AdminUsers> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<AppState>().loadAdminUsers());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final state = context.read<AppState>();
      if (mounted && !state.loadingAdminUsers) state.loadAdminUsers();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AdminUser> _filtered(List<AdminUser> all) {
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all
        .where((u) =>
            u.fullName.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.status.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rows = _filtered(state.adminUsers);

    return Column(
      children: [
        // Header + search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Users',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('Manage and monitor registered TaskFlow accounts.',
                          style: TextStyle(fontSize: 12, color: _kMuted)),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: () => _showCreateUser(context, state),
                    icon: const Icon(Icons.person_add_outlined, size: 17),
                    label: const Text('Add user'),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search users…',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: state.loadingAdminUsers && state.adminUsers.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(_kViolet)))
              : rows.isEmpty
                  ? Center(
                      child: Text(
                        _search.isEmpty
                            ? 'No users found.'
                            : 'No users match "$_search".',
                        style: const TextStyle(fontSize: 14, color: _kMuted),
                      ),
                    )
                  : RefreshIndicator(
                      color: _kViolet,
                      onRefresh: () =>
                          context.read<AppState>().loadAdminUsers(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (ctx, i) => _UserTile(
                          user: rows[i],
                          onRefresh: () =>
                              context.read<AppState>().loadAdminUsers(),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  void _showCreateUser(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ChangeNotifierProvider.value(
        value: state,
        child: const _CreateUserSheet(),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onRefresh});
  final AdminUser user;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final isSuspended = user.status == 'suspended';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Opacity(
      opacity: isSuspended ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? _kLineDark : _kLine),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: _kVioletLight,
            child: Text(
              (user.firstName.isNotEmpty ? user.firstName[0] : '') +
                  (user.lastName.isNotEmpty ? user.lastName[0] : ''),
              style: const TextStyle(
                  color: _kViolet, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(user.fullName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  _StatusPill(user.status),
                ]),
                Text(user.email,
                    style: const TextStyle(fontSize: 12, color: _kMuted),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${user.organizationCount} org${user.organizationCount != 1 ? 's' : ''} · ${_fmtDate(user.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: _kMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: _kMuted),
            onSelected: (a) => _handleAction(context, a),
            itemBuilder: (_) => [
              if (!isSuspended)
                const PopupMenuItem(
                  value: 'suspend',
                  child: Row(children: [
                    Icon(Icons.block_outlined, size: 16, color: _kWarning),
                    SizedBox(width: 8),
                    Text('Suspend'),
                  ]),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 16, color: _kDanger),
                  SizedBox(width: 8),
                  Text('Delete permanently', style: TextStyle(color: _kDanger)),
                ]),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _handleAction(BuildContext ctx, String action) async {
    final state = ctx.read<AppState>();
    if (action == 'suspend') {
      final ok = await _confirmDialog(ctx,
          title: 'Suspend account',
          message:
              'Suspend ${user.fullName}? They will no longer be able to log in.',
          confirmLabel: 'Suspend',
          destructive: false);
      if (!ok) return;
      try {
        await state.api.adminSuspendUser(user.id);
        onRefresh();
      } on ApiException catch (e) {
        if (ctx.mounted) _snackError(ctx, e.message);
      }
    } else if (action == 'delete') {
      final ok = await _confirmDialog(ctx,
          title: 'Delete account',
          message:
              'Permanently delete ${user.fullName}? This cannot be undone.',
          confirmLabel: 'Delete',
          destructive: true);
      if (!ok) return;
      try {
        await state.api.adminDeleteUser(user.id);
        onRefresh();
      } on ApiException catch (e) {
        if (ctx.mounted) _snackError(ctx, e.message);
      }
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: (isActive ? _kSuccess : _kMuted).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isActive ? _kSuccess : _kMuted,
        ),
      ),
    );
  }
}

// Create user bottom sheet
class _CreateUserSheet extends StatefulWidget {
  const _CreateUserSheet();

  @override
  State<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends State<_CreateUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _tz = TextEditingController(text: 'UTC');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _pass.dispose();
    _tz.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().api.adminCreateUser(
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            email: _email.text.trim(),
            password: _pass.text,
            timezone: _tz.text.trim().isEmpty ? 'UTC' : _tz.text.trim(),
          );
      if (!mounted) return;
      await context.read<AppState>().loadAdminUsers();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Create user account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _first,
                    decoration:
                        const InputDecoration(labelText: 'First name *'),
                    validator: (v) =>
                        v?.trim().isEmpty == true ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _last,
                    decoration: const InputDecoration(labelText: 'Last name *'),
                    validator: (v) =>
                        v?.trim().isEmpty == true ? 'Required' : null,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email address *'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v?.trim().isEmpty == true) return 'Required';
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v!.trim())) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                decoration: const InputDecoration(
                  labelText: 'Temporary password *',
                  helperText: 'Minimum 8 characters.',
                ),
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 8) return 'Minimum 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tz,
                decoration: const InputDecoration(
                  labelText: 'Timezone',
                  hintText: 'Africa/Nairobi',
                  helperText: 'Optional — defaults to UTC.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(_error!),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Create user'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4 — Organizations
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminOrganizations extends StatefulWidget {
  const _AdminOrganizations({required this.onOpenProjects});
  final ValueChanged<String> onOpenProjects;

  @override
  State<_AdminOrganizations> createState() => _AdminOrganizationsState();
}

class _AdminOrganizationsState extends State<_AdminOrganizations> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _ownerFilter = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<AppState>().loadAdminOrgs());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final state = context.read<AppState>();
      if (mounted && !state.loadingAdminOrgs) state.loadAdminOrgs();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AdminOrganization> _filtered(List<AdminOrganization> all) {
    final q = _search.toLowerCase();
    return all
        .where((o) =>
            q.isEmpty ||
            o.name.toLowerCase().contains(q) ||
            o.slug.toLowerCase().contains(q) ||
            (o.owner ?? '').toLowerCase().contains(q))
        .where((o) => _ownerFilter.isEmpty || o.owner == _ownerFilter)
        .toList();
  }

  Future<void> _export(List<AdminOrganization> organizations) async {
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
    final rows = [
      ['Organization', 'Slug', 'Owner', 'Members', 'Projects', 'Created'],
      for (final organization in organizations)
        [
          organization.name,
          organization.slug,
          organization.owner ?? '',
          '${organization.memberCount}',
          '${organization.projectCount}',
          organization.createdAt,
        ],
    ];
    final csv = rows.map((row) => row.map(cell).join(',')).join('\r\n');
    final now = _eatNow();
    await FilePicker.platform.saveFile(
      fileName:
          'taskflow-organizations-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv',
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rows = _filtered(state.adminOrgs);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Organizations',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text('View organizations across the TaskFlow platform.',
                  style: TextStyle(fontSize: 12, color: _kMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search organizations…',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _ownerFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Owner',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('All owners')),
                      for (final owner in state.adminOrgs
                          .map((organization) => organization.owner)
                          .whereType<String>()
                          .toSet()
                          .toList()
                        ..sort())
                        DropdownMenuItem(value: owner, child: Text(owner)),
                    ],
                    onChanged: (value) =>
                        setState(() => _ownerFilter = value ?? ''),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: rows.isEmpty ? null : () => _export(rows),
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('CSV'),
                ),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${rows.length} of ${state.adminOrgs.length} records',
                    style: const TextStyle(fontSize: 12, color: _kMuted)),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.loadingAdminOrgs && state.adminOrgs.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(_kViolet)))
              : rows.isEmpty
                  ? Center(
                      child: Text(
                        _search.isEmpty
                            ? 'No organizations found.'
                            : 'No organizations match "$_search".',
                        style: const TextStyle(fontSize: 14, color: _kMuted),
                      ),
                    )
                  : RefreshIndicator(
                      color: _kViolet,
                      onRefresh: () => context.read<AppState>().loadAdminOrgs(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (_, i) => _OrgTile(
                          rows[i],
                          onTap: () => _showOrganization(context, rows[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  void _showOrganization(BuildContext context, AdminOrganization org) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(org.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(org.slug, style: const TextStyle(color: _kMuted)),
            const Divider(height: 24),
            _DetailRow('Owner', org.owner ?? 'No owner'),
            _DetailRow('Members', '${org.memberCount}'),
            _DetailRow('Projects', '${org.projectCount}'),
            _DetailRow('Created', _fmtDate(org.createdAt)),
            _DetailRow('Organization ID', org.id),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: () { Navigator.of(context).pop(); widget.onOpenProjects(org.id); },
              icon: const Icon(Icons.folder_open_outlined), label: const Text('View projects'))),
          ]),
        ),
      ),
    );
  }
}

class _OrgTile extends StatelessWidget {
  const _OrgTile(this.org, {required this.onTap});
  final AdminOrganization org;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? _kLineDark : _kLine),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _kVioletLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.business_outlined, size: 18, color: _kViolet),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(org.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(org.slug,
                  style: const TextStyle(fontSize: 11, color: _kMuted)),
              const SizedBox(height: 4),
              Row(children: [
                _InfoChip(Icons.people_outline, '${org.memberCount} members'),
                const SizedBox(width: 8),
                _InfoChip(
                    Icons.folder_outlined, '${org.projectCount} projects'),
              ]),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(org.owner ?? 'No owner',
                style: const TextStyle(fontSize: 11, color: _kMuted)),
            const SizedBox(height: 2),
            Text(_fmtDate(org.createdAt),
                style: const TextStyle(fontSize: 11, color: _kMuted)),
          ],
        ),
      ]),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: _kMuted)),
          ),
          Expanded(child: SelectableText(value)),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5 — Projects
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminProjects extends StatefulWidget {
  const _AdminProjects({this.organizationFilterId});
  final String? organizationFilterId;

  @override
  State<_AdminProjects> createState() => _AdminProjectsState();
}

class _AdminProjectsState extends State<_AdminProjects> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = '';
  String _sortBy = 'dueDate';
  Timer? _refreshTimer;
  AdminProject? _selectedProject;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppState>().loadAdminProjects());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final state = context.read<AppState>();
      if (mounted && !state.loadingAdminProjects) state.loadAdminProjects();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AdminProject> _filtered(List<AdminProject> all) => all.where((p) {
        final q = _search.toLowerCase();
        return (q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                (p.organizationName ?? '').toLowerCase().contains(q) ||
                p.displayStatus.toLowerCase().contains(q)) &&
            (_statusFilter.isEmpty || p.displayStatus == _statusFilter) &&
            (widget.organizationFilterId == null || p.organizationId == widget.organizationFilterId);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_selectedProject != null) {
      return _AdminProjectDetails(project: _selectedProject!, onBack: () => setState(() => _selectedProject = null));
    }
    final rows = _filtered(state.adminProjects)
      ..sort((a, b) {
        String value(AdminProject project) => switch (_sortBy) {
              'name' => project.name,
              'status' => project.displayStatus,
              'tasks' => project.taskCount.toString().padLeft(10, '0'),
              _ => project.dueDate ?? '',
            };
        return value(b).toLowerCase().compareTo(value(a).toLowerCase());
      });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Projects',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text('Read-only oversight of projects across the platform.',
                  style: TextStyle(fontSize: 12, color: _kMuted)),
              if (widget.organizationFilterId != null) ...[
                const SizedBox(height: 5),
                Text('Filtered to ${state.adminOrgs.where((organization) => organization.id == widget.organizationFilterId).map((organization) => organization.name).firstOrNull ?? 'selected organization'}',
                    style: const TextStyle(fontSize: 12, color: _kViolet)),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search projects…',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in [
                    '',
                    'PLANNING',
                    'ACTIVE',
                    'ON_HOLD',
                    'COMPLETED',
                    'ARCHIVED'
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(s.isEmpty ? 'All' : s,
                            style: const TextStyle(fontSize: 11)),
                        selected: _statusFilter == s,
                        onSelected: (_) => setState(() => _statusFilter = s),
                        selectedColor:
                            Theme.of(context).brightness == Brightness.dark
                                ? _kViolet.withValues(alpha: 0.22)
                                : _kVioletLight,
                        labelStyle: TextStyle(
                            color: _statusFilter == s ? _kViolet : _kMuted),
                        side: BorderSide(
                            color: _statusFilter == s ? _kViolet : _kLine),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 0),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: _sortBy,
                    decoration: const InputDecoration(
                      labelText: 'Sort projects',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'dueDate', child: Text('Due date')),
                      DropdownMenuItem(value: 'name', child: Text('Project name')),
                      DropdownMenuItem(value: 'status', child: Text('Status')),
                      DropdownMenuItem(value: 'tasks', child: Text('Task count')),
                    ],
                    onChanged: (value) => setState(() => _sortBy = value ?? 'dueDate'),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.loadingAdminProjects && state.adminProjects.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(_kViolet)))
              : rows.isEmpty
                  ? Center(
                      child: Text(
                        _search.isEmpty
                            ? 'No projects found.'
                            : 'No projects match "$_search".',
                        style: const TextStyle(fontSize: 14, color: _kMuted),
                      ),
                    )
                  : RefreshIndicator(
                      color: _kViolet,
                      onRefresh: () =>
                          context.read<AppState>().loadAdminProjects(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (_, i) => _ProjectTile(
                          rows[i],
                          onTap: () => setState(() => _selectedProject = rows[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

}

class _AdminProjectDetails extends StatefulWidget {
  const _AdminProjectDetails({required this.project, required this.onBack});
  final AdminProject project;
  final VoidCallback onBack;

  @override
  State<_AdminProjectDetails> createState() => _AdminProjectDetailsState();
}

class _AdminProjectDetailsState extends State<_AdminProjectDetails> {
  late Future<AdminProjectDetails> _details;
  late Future<AdminProjectPage<AdminProjectMember>> _members;
  late Future<AdminProjectPage<AdminProjectTask>> _tasks;
  int _memberPage = 1, _taskPage = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<AppState>().api;
    _details = api.adminProjectDetails(widget.project.id);
    _members = api.adminProjectMembers(widget.project.id, page: _memberPage);
    _tasks = api.adminProjectTasks(widget.project.id, page: _taskPage);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_details, _members, _tasks]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextButton.icon(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back, size: 17), label: const Text('Back to projects')),
              Row(children: [Expanded(child: _ProjectHero(project: widget.project)), IconButton(onPressed: _refresh, tooltip: 'Refresh project details', icon: const Icon(Icons.refresh))]),
            ]),
          ),
          const TabBar(isScrollable: true, tabs: [Tab(text: 'Overview'), Tab(text: 'Members'), Tab(text: 'Tasks'), Tab(text: 'Activity')]),
          Expanded(child: TabBarView(children: [
            Builder(builder: (tabContext) => _OverviewTab(
              future: _details,
              onViewAll: () => DefaultTabController.of(tabContext).animateTo(3),
            )),
            _MembersTab(future: _members, page: _memberPage, onPage: (page) => setState(() { _memberPage = page; _load(); })),
            _TasksTab(future: _tasks, page: _taskPage, onPage: (page) => setState(() { _taskPage = page; _load(); })),
            _ProjectActivityTab(projectId: widget.project.id, organizationId: widget.project.organizationId ?? ''),
          ])),
        ]),
      );
}

class _ProjectHero extends StatelessWidget {
  const _ProjectHero({required this.project});
  final AdminProject project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final historical = project.isArchived || project.isTrashed;
    final accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _kLine),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.surface, accent.withValues(alpha: .06)],
        ),
      ),
      child: Row(children: [
        Container(
          width: 37,
          height: 37,
          decoration: BoxDecoration(color: accent.withValues(alpha: .11), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.folder_copy_outlined, color: accent, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(project.organizationName ?? 'Organization', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: _kMuted)),
        ])),
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: historical ? const Color(0xFFFFF5DF) : const Color(0xFFEAF6EF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(project.displayStatus, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: historical ? const Color(0xFF8A6928) : const Color(0xFF347654))),
        ),
      ]),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.future, required this.onViewAll});
  final Future<AdminProjectDetails> future;
  final VoidCallback onViewAll;
  @override
  Widget build(BuildContext context) => FutureBuilder<AdminProjectDetails>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError || !snapshot.hasData) return const _ErrorBanner('Could not load project overview.');
      final project = snapshot.data!;
      final historical = project.archivedAt != null || project.deletedAt != null;
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (historical) const _InfoBanner('Historical project · viewing does not restore or change its lifecycle.'),
        GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, mainAxisSpacing: 9, crossAxisSpacing: 9, childAspectRatio: 1.65, children: [
          _AdminMetricCard(label: 'Active members', value: project.memberCount, detail: 'Current project access', icon: Icons.people_outline, tone: _MetricTone.violet),
          _AdminMetricCard(label: 'Eligible tasks', value: project.hasTasks ? project.totalEligibleTasks : 'No tasks', detail: project.hasTasks ? '${project.completedTasks} completed' : 'Awaiting first task', icon: Icons.task_alt_outlined, tone: _MetricTone.blue),
          _AdminMetricCard(label: 'Progress', value: project.progressPercent == null ? '—' : '${project.progressPercent}%', detail: project.hasTasks ? '${project.outstandingTaskCount} outstanding' : 'No task activity', icon: Icons.donut_small_outlined, tone: _MetricTone.green, progress: project.progressPercent),
          _AdminMetricCard(label: 'Overdue', value: project.overdueTaskCount, detail: 'Organization local time', icon: Icons.schedule, tone: project.overdueTaskCount > 0 ? _MetricTone.amber : _MetricTone.neutral),
        ]),
        const SizedBox(height: 12),
        _ChartCard(title: 'Project overview', subtitle: 'Ownership and lifecycle details', child: Column(children: [
          _DetailRow('Organization', project.organizationName), _DetailRow('Owner', project.ownerName ?? 'No owner listed'),
          _DetailRow('Status', historical ? '${project.status} · Historical' : project.status),
          _DetailRow('Completed tasks', '${project.completedTasks} of ${project.totalEligibleTasks}'),
          _DetailRow('Outstanding tasks', '${project.outstandingTaskCount}'),
          _DetailRow('Due date', project.dueDate == null ? 'No due date' : _fmtDate(project.dueDate!)),
          _DetailRow('Created', _fmtDate(project.createdAt)),
        ])),
        const SizedBox(height: 12),
        _RecentProjectActivity(projectId: project.projectId, organizationId: project.organizationId, onViewAll: onViewAll),
      ]);
    });
}

class _RecentProjectActivity extends StatefulWidget {
  const _RecentProjectActivity({required this.projectId, required this.organizationId, required this.onViewAll});
  final String projectId;
  final String organizationId;
  final VoidCallback onViewAll;

  @override
  State<_RecentProjectActivity> createState() => _RecentProjectActivityState();
}

class _RecentProjectActivityState extends State<_RecentProjectActivity> {
  late Future<PlatformActivityPage> _activity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _activity = context.read<AppState>().api.adminActivityPage(
      projectId: widget.projectId,
      organizationId: widget.organizationId,
      pageSize: 4,
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: const BorderSide(color: _kLine)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Recent activity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            SizedBox(height: 3),
            Text('Latest recorded project changes', style: TextStyle(fontSize: 10, color: _kMuted)),
          ])),
          TextButton(onPressed: widget.onViewAll, child: const Text('View all', style: TextStyle(fontSize: 11))),
        ]),
        FutureBuilder<PlatformActivityPage>(future: _activity, builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          if (snapshot.hasError || !snapshot.hasData) return Row(children: [const Expanded(child: Text('Could not load recent activity.', style: TextStyle(fontSize: 11, color: _kMuted))), TextButton(onPressed: () => setState(_load), child: const Text('Retry'))]);
          final events = snapshot.data!.items.take(4).toList();
          if (events.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('No project activity recorded yet.', style: TextStyle(fontSize: 11, color: _kMuted))));
          return Column(children: [
            for (var index = 0; index < events.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(radius: 16, backgroundColor: const Color(0xFFEEECFF), child: Icon(_activityIcon(events[index].category), size: 15, color: _kViolet)),
                title: Text('${events[index].actorName} ${events[index].description}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                subtitle: Text(events[index].projectName ?? 'Project activity', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: _kMuted)),
                trailing: Text(_shortActivityTime(events[index].createdAt), style: const TextStyle(fontSize: 9, color: _kMuted)),
              ),
            ],
          ]);
        }),
      ]),
    ),
  );
}

IconData _activityIcon(String category) => switch (category.toLowerCase()) {
  'tasks' => Icons.task_alt_outlined,
  'people' => Icons.person_outline,
  'collaboration' => Icons.forum_outlined,
  'projects' => Icons.folder_outlined,
  _ => Icons.bolt_outlined,
};

String _shortActivityTime(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return 'Recently';
  final difference = DateTime.now().difference(parsed);
  if (difference.inMinutes < 1) return 'Now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return _fmtDate(value);
}

enum _MetricTone { violet, blue, green, amber, neutral }

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({required this.label, required this.value, required this.icon, required this.detail, required this.tone, this.progress});
  final String label;
  final Object value;
  final String detail;
  final IconData icon;
  final _MetricTone tone;
  final int? progress;
  @override
  Widget build(BuildContext context) {
    final palette = switch (tone) {
      _MetricTone.violet => (const Color(0xFFEEECFF), _kViolet),
      _MetricTone.blue => (const Color(0xFFEAF2FF), const Color(0xFF4777C1)),
      _MetricTone.green => (const Color(0xFFE8F6EF), const Color(0xFF398362)),
      _MetricTone.amber => (const Color(0xFFFFF3DF), const Color(0xFFA47220)),
      _MetricTone.neutral => (const Color(0xFFF0F1F5), _kMuted),
    };
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _kLine), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [Container(width: 28, height: 28, decoration: BoxDecoration(color: palette.$1, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 16, color: palette.$2)), const SizedBox(width: 7), Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: _kMuted, fontWeight: FontWeight.w600)))]),
        Text(value.toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.1)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: _kMuted)), if (progress != null) ...[const SizedBox(height: 5), ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: progress!.clamp(0, 100) / 100, minHeight: 4, backgroundColor: const Color(0xFFEAE8F7), color: _kViolet))]]),
      ]),
    );
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.future, required this.page, required this.onPage});
  final Future<AdminProjectPage<AdminProjectMember>> future;
  final int page;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => FutureBuilder<AdminProjectPage<AdminProjectMember>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError || !snapshot.hasData) return const _ErrorBanner('Could not load project members.');
      final data = snapshot.data!;
      final calculatedPages = (data.totalCount / data.pageSize).ceil();
      final pages = calculatedPages < 1 ? 1 : calculatedPages;
      return Column(children: [Expanded(child: data.items.isEmpty ? const Center(child: Text('No members recorded.')) : ListView.separated(
        padding: const EdgeInsets.all(12), itemCount: data.items.length, separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) { final member = data.items[index]; return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(member.displayName),
          subtitle: Text('${member.projectRole.replaceAll('_', ' ')} · ${member.projectMembershipStatus} · ${member.accountStatus}'),
          trailing: Text(member.organizationMembershipStatus ?? 'No org membership', style: const TextStyle(fontSize: 10, color: _kMuted)),
        ); })),
        _PageControls(page: page, pages: pages, total: data.totalCount, onPage: onPage),
      ]);
    });
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({required this.future, required this.page, required this.onPage});
  final Future<AdminProjectPage<AdminProjectTask>> future;
  final int page;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => FutureBuilder<AdminProjectPage<AdminProjectTask>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError || !snapshot.hasData) return const _ErrorBanner('Could not load project tasks.');
      final data = snapshot.data!;
      final calculatedPages = (data.totalCount / data.pageSize).ceil();
      final pages = calculatedPages < 1 ? 1 : calculatedPages;
      return Column(children: [Expanded(child: data.items.isEmpty ? const Center(child: Text('No non-deleted top-level tasks.')) : ListView.separated(
        padding: const EdgeInsets.all(12), itemCount: data.items.length, separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) { final task = data.items[index]; return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.task_outlined)), title: Text(task.title),
          subtitle: Text('${task.status.replaceAll('_', ' ')} · ${task.priority} · ${task.effectiveAssigneeCount} active assignees'),
          trailing: Text(task.dueDate == null ? 'No due date' : _fmtDate(task.dueDate!), style: const TextStyle(fontSize: 10, color: _kMuted)),
        ); })),
        _PageControls(page: page, pages: pages, total: data.totalCount, onPage: onPage),
      ]);
    });
}

class _ProjectActivityTab extends StatefulWidget {
  const _ProjectActivityTab({required this.projectId, required this.organizationId});
  final String projectId, organizationId;
  @override
  State<_ProjectActivityTab> createState() => _ProjectActivityTabState();
}

class _ProjectActivityTabState extends State<_ProjectActivityTab> {
  final List<String?> _cursors = [null];
  late Future<PlatformActivityPage> _future;
  @override
  void initState() { super.initState(); _load(); }
  void _load() => _future = context.read<AppState>().api.adminActivityPage(
      projectId: widget.projectId, organizationId: widget.organizationId,
      cursor: _cursors.last, pageSize: 30);
  @override
  Widget build(BuildContext context) => FutureBuilder<PlatformActivityPage>(future: _future, builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError || !snapshot.hasData) return const _ErrorBanner('Could not load project activity.');
    final data = snapshot.data!;
    if (data.items.isEmpty) return const Center(child: Text('No activity recorded for this project.'));
    return Column(children: [Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: data.items.length, itemBuilder: (_, index) {
      final event = data.items[index];
      return Card(child: ExpansionTile(title: Text('${event.actorName} ${event.description}'), subtitle: Text('${event.category} · ${_fmtDateTime(event.createdAt)}'), childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
        _DetailRow('Actor', event.actorName), _DetailRow('Action', event.action), _DetailRow('Target', '${event.entityType}: ${event.entityName}'), _DetailRow('Organization', event.organizationName), _DetailRow('Project', event.projectName ?? widget.projectId), _DetailRow('Status', event.status), _DetailRow('Request', event.correlationId),
      ]));
    })),
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(onPressed: _cursors.length > 1 ? () => setState(() { _cursors.removeLast(); _load(); }) : null, child: const Text('Newer')),
        Text('Page ${_cursors.length}', style: const TextStyle(fontSize: 11, color: _kMuted)),
        TextButton(onPressed: data.nextCursor == null ? null : () => setState(() { _cursors.add(data.nextCursor); _load(); }), child: const Text('Older')),
      ])),
    ]);
  });
}

class _PageControls extends StatelessWidget {
  const _PageControls({required this.page, required this.pages, required this.total, required this.onPage});
  final int page, pages, total;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text('Page $page of $pages · $total records', style: const TextStyle(fontSize: 11, color: _kMuted)),
    Row(children: [IconButton(tooltip: 'Previous page', onPressed: page > 1 ? () => onPage(page - 1) : null, icon: const Icon(Icons.chevron_left)), IconButton(tooltip: 'Next page', onPressed: page < pages ? () => onPage(page + 1) : null, icon: const Icon(Icons.chevron_right))]),
  ]));
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile(this.project, {required this.onTap});
  final AdminProject project;
  final VoidCallback onTap;

  Color _statusColor(String s) {
    switch (s) {
      case 'ACTIVE':
        return _kSuccess;
      case 'COMPLETED':
        return _kViolet;
      case 'ON_HOLD':
        return _kWarning;
      case 'ARCHIVED':
        return _kMuted;
      default:
        return const Color(0xFF06B6D4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _statusColor(project.displayStatus);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? _kLineDark : _kLine),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.folder_outlined, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(project.organizationName ?? 'Unknown organization',
                  style: const TextStyle(fontSize: 12, color: _kMuted)),
              const SizedBox(height: 4),
              Row(children: [
                _InfoChip(
                    Icons.task_alt_outlined, '${project.taskCount} tasks'),
                if (project.dueDate != null) ...[
                  const SizedBox(width: 8),
                  _InfoChip(Icons.event_outlined,
                      'Due ${_fmtDate(project.dueDate!)}'),
                ],
              ]),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            project.displayStatus,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 6 — Activity
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminActivity extends StatefulWidget {
  const _AdminActivity();

  @override
  State<_AdminActivity> createState() => _AdminActivityState();
}

class _AdminActivityState extends State<_AdminActivity> {
  late Future<PlatformActivityPage> _page;
  final _search = TextEditingController();
  final List<String?> _cursorStack = [null];
  String _category = '';
  String _organizationId = '';
  String _projectId = '';
  List<AdminProject> _projects = [];
  bool _loadingProjects = false;
  String? _projectsError;
  int _projectLoadGeneration = 0;
  int _activityLoadGeneration = 0;
  String _range = '7d';
  DateTimeRange? _customRange;
  Timer? _refreshTimer;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    _page = _load();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppState>().loadAdminOrgs());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_requestInFlight) _refresh();
    });
  }

  String _date(DateTime value) => DateTime.utc(
        value.year,
        value.month,
        value.day,
      ).subtract(_eatOffset).toIso8601String();

  ({String? from, String? to}) get _dateBounds {
    final now = _eatNow();
    if (_range == 'all') return (from: null, to: null);
    if (_range == 'custom' && _customRange != null) {
      final start = DateTime(_customRange!.start.year,
          _customRange!.start.month, _customRange!.start.day);
      final end = DateTime(_customRange!.end.year,
          _customRange!.end.month, _customRange!.end.day);
      final isToday = end.year == now.year &&
          end.month == now.month &&
          end.day == now.day;
      if (isToday) return (from: _date(start), to: null);
      return (from: _date(start), to: _date(end.add(const Duration(days: 1))));
    }
    final today = DateTime(now.year, now.month, now.day);
    final days = _range == 'today' ? 0 : _range == '30d' ? 29 : 6;
    return (from: _date(today.subtract(Duration(days: days))), to: null);
  }

  Future<PlatformActivityPage> _load({String? cursor}) {
    final bounds = _dateBounds;
    return context.read<AppState>().api.adminActivityPage(
            category: _category,
            organizationId: _organizationId,
            projectId: _projectId,
            search: _search.text.trim(),
            from: bounds.from,
            to: bounds.to,
            cursor: cursor,
            pageSize: 50);
  }

  Future<void> _loadProjects(String organizationId) async {
    final generation = ++_projectLoadGeneration;
    if (!mounted || organizationId.isEmpty) return;
    setState(() {
      _loadingProjects = true;
      _projectsError = null;
      _projects = [];
    });
    try {
      final projects = await context.read<AppState>().api.adminProjects(
            organizationId: organizationId,
            includeTrashed: true,
          );
      if (!mounted ||
          generation != _projectLoadGeneration ||
          _organizationId != organizationId) {
        return;
      }
      setState(() => _projects = projects);
    } catch (_) {
      if (!mounted ||
          generation != _projectLoadGeneration ||
          _organizationId != organizationId) {
        return;
      }
      setState(
        () => _projectsError =
            'Could not load projects for this organization.',
      );
    } finally {
      if (mounted && generation == _projectLoadGeneration) {
        setState(() => _loadingProjects = false);
      }
    }
  }

  Future<void> _refresh({bool resetPage = false, bool force = false}) async {
    if ((_requestInFlight && !force) || !mounted) return;
    _requestInFlight = true;
    if (resetPage) {
      _cursorStack
        ..clear()
        ..add(null);
    }
    final cursor = _cursorStack.last;
    final request = _load(cursor: cursor);
    setState(() {
      _page = request;
    });
    final generation = ++_activityLoadGeneration;
    try {
      await request;
    } finally {
      if (generation == _activityLoadGeneration) _requestInFlight = false;
    }
  }

  Future<void> _selectCustomRange() async {
    final now = _eatNow();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _customRange = selected;
      _range = 'custom';
    });
    await _refresh(resetPage: true);
  }

  Future<void> _nextPage(String cursor) async {
    setState(() {
      _cursorStack.add(cursor);
      _page = _load(cursor: cursor);
    });
    await _page;
  }

  Future<void> _previousPage() async {
    if (_cursorStack.length <= 1) return;
    setState(() {
      _cursorStack.removeLast();
      _page = _load(cursor: _cursorStack.last);
    });
    await _page;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SectionPage(
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeader(
            title: 'Activity',
            subtitle: 'Recent platform events across TaskFlow.',
          ),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _refresh(resetPage: true),
            decoration: InputDecoration(
              hintText: 'Search activity',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Apply search',
                onPressed: () => _refresh(resetPage: true),
                icon: const Icon(Icons.arrow_forward),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final category in [
                '',
                'Projects',
                'Tasks',
                'People',
                'Collaboration',
                'System'
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(category.isEmpty ? 'All' : category),
                    selected: _category == category,
                    onSelected: (_) async {
                      setState(() => _category = category);
                      await _refresh(resetPage: true);
                    },
                    selectedColor: Theme.of(context).brightness ==
                            Brightness.dark
                        ? _kViolet.withValues(alpha: 0.22)
                        : _kVioletLight,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _organizationId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Organization',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All organizations')),
                  for (final org in context.watch<AppState>().adminOrgs)
                    DropdownMenuItem(value: org.id, child: Text(org.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) async {
                  final organizationId = value ?? '';
                  setState(() {
                    _organizationId = organizationId;
                    _projectId = '';
                    _projects = [];
                    _projectsError = null;
                    _loadingProjects = organizationId.isNotEmpty;
                  });
                  if (organizationId.isNotEmpty) await _loadProjects(organizationId);
                  await _refresh(resetPage: true, force: true);
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _projectId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Project',
                  isDense: true,
                  suffixIcon: _loadingProjects
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_organizationId.isEmpty
                        ? 'Select an organization first'
                        : 'All projects'),
                  ),
                  for (final project in _projects)
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(
                        '${project.name}${project.isTrashed ? ' · In Trash' : project.isArchived ? ' · Archived' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _organizationId.isEmpty ||
                        _loadingProjects ||
                        _projectsError != null
                    ? null
                    : (value) async {
                        setState(() => _projectId = value ?? '');
                        await _refresh(resetPage: true, force: true);
                      },
              ),
            ),
            if (_projectsError != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Retry loading projects',
                onPressed: () => _loadProjects(_organizationId),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ]),
          if (_projectsError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _projectsError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _range,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Date range',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'today', child: Text('Today')),
                  DropdownMenuItem(value: '7d', child: Text('Last 7 days')),
                  DropdownMenuItem(value: '30d', child: Text('Last 30 days')),
                  DropdownMenuItem(value: 'all', child: Text('All time')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                ],
                onChanged: (value) async {
                  final selected = value ?? '7d';
                  if (selected == 'custom') {
                    await _selectCustomRange();
                    return;
                  }
                  setState(() => _range = selected);
                  await _refresh(resetPage: true);
                },
              ),
            ),
          ]),
          const SizedBox(height: 14),
          FutureBuilder<PlatformActivityPage>(
            future: _page,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const _ErrorBanner('Could not load platform activity.');
              }
              final page = snapshot.data!;
              if (page.items.isEmpty) {
                return const _InfoBanner(
                    'No platform activity matches this search.');
              }
              return Column(
                children: [
                  for (final item in page.items) _ActivityCard(item: item),
                  if (page.nextCursor != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _nextPage(page.nextCursor!),
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Load more'),
                    ),
                  ],
                  if (page.items.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      TextButton.icon(
                        onPressed: _cursorStack.length > 1 ? _previousPage : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      Text('Page ${_cursorStack.length}', style: const TextStyle(fontSize: 12, color: _kMuted)),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Refresh activity',
                        onPressed: () => _refresh(),
                        icon: const Icon(Icons.refresh),
                      ),
                    ]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item});
  final PlatformActivityItem item;

  Widget _detailLine(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: ExpansionTile(
          leading: const Icon(Icons.bolt_outlined, color: _kViolet, size: 20),
          title: Text(
            item.description.isEmpty ? item.action : item.description,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${item.actorName} · ${item.organizationName} · ${_fmtDateTime(item.createdAt)}',
              style: const TextStyle(fontSize: 12, color: _kMuted),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            _detailLine(
              'Actor',
              '${item.actorName}${item.actorUserId.isEmpty ? '' : ' (${item.actorUserId})'}',
            ),
            _detailLine('Action', '${item.action} · ${item.category} · ${item.status}'),
            _detailLine('Time', _fmtDateTime(item.createdAt)),
            _detailLine(
              'Organization',
              item.organizationId.isEmpty
                  ? 'Platform'
                  : '${item.organizationName} (${item.organizationId})',
            ),
            if (item.projectName != null || item.projectId != null)
              _detailLine(
                'Project',
                '${item.projectName ?? 'Unknown project'}${item.projectId == null ? '' : ' (${item.projectId})'}',
              ),
            _detailLine(
              'Target',
              '${item.entityType} · ${item.entityName} (${item.entityId})',
            ),
            _detailLine('Request', item.correlationId),
          ],
        ),
      );
}

String _fmtDateTime(String value) {
  try {
    final date = _dateInEat(value);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return value;
  }
}

class _AdminAuditTrail extends StatefulWidget {
  const _AdminAuditTrail();

  @override
  State<_AdminAuditTrail> createState() => _AdminAuditTrailState();
}

class _AdminAuditTrailState extends State<_AdminAuditTrail> {
  late Future<AdminAuditPage> _page;
  final List<String?> _cursorStack = [null];
  String _action = '';
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _page = _load();
  }

  Future<AdminAuditPage> _load({String? cursor}) {
    final range = _dateRange;
    final now = _eatNow();
    final from = range == null
        ? null
        : DateTime.utc(range.start.year, range.start.month, range.start.day)
            .subtract(_eatOffset)
            .toIso8601String();
    final to = range == null
        ? null
        : range.end.year == now.year &&
                range.end.month == now.month &&
                range.end.day == now.day
            ? now.toUtc().toIso8601String()
            : DateTime.utc(range.end.year, range.end.month, range.end.day + 1)
                .subtract(_eatOffset)
                .toIso8601String();
    return context.read<AppState>().api.adminAuditPage(
          action: _action,
          from: from,
          to: to,
          cursor: cursor,
          pageSize: 50,
        );
  }

  Future<void> _refresh({bool resetPage = false}) async {
    if (resetPage) {
      _cursorStack
        ..clear()
        ..add(null);
    }
    final request = _load(cursor: _cursorStack.last);
    setState(() => _page = request);
    await request;
  }

  Future<void> _selectDateRange() async {
    final now = _eatNow();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (selected == null || !mounted) return;
    setState(() => _dateRange = selected);
    await _refresh(resetPage: true);
  }

  Future<void> _nextPage(String cursor) async {
    setState(() {
      _cursorStack.add(cursor);
      _page = _load(cursor: cursor);
    });
    await _page;
  }

  Future<void> _previousPage() async {
    if (_cursorStack.length <= 1) return;
    setState(() {
      _cursorStack.removeLast();
      _page = _load(cursor: _cursorStack.last);
    });
    await _page;
  }

  @override
  Widget build(BuildContext context) => _SectionPage(
        onRefresh: _refresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PageHeader(
              title: 'Audit Trail',
              subtitle: 'Recorded administrative actions and outcomes.',
            ),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _action,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Action',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All actions')),
                    DropdownMenuItem(value: 'user.create', child: Text('User created')),
                    DropdownMenuItem(value: 'user.suspend', child: Text('User suspended')),
                    DropdownMenuItem(value: 'user.delete.permanent', child: Text('User permanently deleted')),
                  ],
                  onChanged: (value) async {
                    setState(() => _action = value ?? '');
                    await _refresh(resetPage: true);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _selectDateRange,
                icon: const Icon(Icons.date_range_outlined, size: 17),
                label: Text(_dateRange == null
                    ? 'Last 30 days'
                    : '${_fmtDate(_dateRange!.start.toIso8601String())} – ${_fmtDate(_dateRange!.end.toIso8601String())}'),
              ),
            ]),
            const SizedBox(height: 12),
            FutureBuilder<AdminAuditPage>(
              future: _page,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _ErrorBanner('Could not load the audit trail.');
                }
                final page = snapshot.data!;
                if (page.items.isEmpty) {
                  return const _InfoBanner(
                      'No administrative audit events found.');
                }
                return Column(children: [
                  for (final event in page.items) _AuditEventCard(event: event),
                  if (page.nextCursor != null)
                    OutlinedButton.icon(
                      onPressed: () => _nextPage(page.nextCursor!),
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Load more'),
                    ),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton.icon(
                      onPressed: _cursorStack.length > 1 ? _previousPage : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Previous'),
                    ),
                    Text('Page ${_cursorStack.length}',
                        style: const TextStyle(fontSize: 12, color: _kMuted)),
                    IconButton(
                      tooltip: 'Refresh audit trail',
                      onPressed: () => _refresh(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ]),
                ]);
              },
            ),
          ],
        ),
      );
}

class _AuditEventCard extends StatelessWidget {
  const _AuditEventCard({required this.event});
  final AdminAuditEvent event;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              event.outcome.toLowerCase() == 'succeeded'
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color: event.outcome.toLowerCase() == 'succeeded'
                  ? _kSuccess
                  : _kWarning,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(event.action,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      '${event.actorName} · ${event.targetName.isEmpty ? event.targetType : event.targetName}',
                      style: const TextStyle(fontSize: 12, color: _kMuted)),
                  if (event.reason?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(event.reason!, style: const TextStyle(fontSize: 12)),
                  ],
                  const SizedBox(height: 4),
                  Text('${event.outcome} · ${_fmtDateTime(event.occurredAt)}',
                      style: const TextStyle(fontSize: 11, color: _kMuted)),
                ])),
          ]),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 7 — System Health
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminHealth extends StatefulWidget {
  const _AdminHealth();

  @override
  State<_AdminHealth> createState() => _AdminHealthState();
}

class _AdminHealthState extends State<_AdminHealth> {
  DateTime? _lastChecked;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !context.read<AppState>().loadingAdminHealth) _load();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await context.read<AppState>().loadAdminHealth();
    if (mounted) setState(() => _lastChecked = _eatNow());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final h = state.adminHealth;

    return _SectionPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeader(
            title: 'System Health',
            subtitle: 'Current availability of TaskFlow services.',
          ),
          Row(children: [
            OutlinedButton.icon(
              onPressed: state.loadingAdminHealth ? null : _load,
              icon: state.loadingAdminHealth
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_outlined, size: 16),
              label: const Text('Refresh'),
            ),
            if (_lastChecked != null) ...[
              const SizedBox(width: 12),
              Text(
                'Last checked ${_fmtTime(_lastChecked!)}',
                style: const TextStyle(fontSize: 12, color: _kMuted),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          if (state.loadingAdminHealth && h == null)
            const Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(_kViolet)))
          else if (h == null)
            const _ErrorBanner('Could not check health status.')
          else
            Column(children: [
              _HealthTile(label: 'API', status: h.api),
              const SizedBox(height: 10),
              _HealthTile(label: 'Database', status: h.database),
            ]),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({required this.label, required this.status});
  final String label;
  final String status;

  Color get _color {
    switch (status.toLowerCase()) {
      case 'healthy':
        return _kSuccess;
      case 'degraded':
        return _kWarning;
      default:
        return _kDanger;
    }
  }

  IconData get _icon {
    switch (status.toLowerCase()) {
      case 'healthy':
        return Icons.check_circle_outline;
      case 'degraded':
        return Icons.warning_amber_outlined;
      default:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? _kLineDark : _kLine),
      ),
      child: Row(children: [
        Icon(_icon, color: _color, size: 32),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: _kMuted)),
            Text(status,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: _color)),
          ],
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 8 — Reports
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminReports extends StatefulWidget {
  const _AdminReports();

  @override
  State<_AdminReports> createState() => _AdminReportsState();
}

class _AdminReportsState extends State<_AdminReports> {
  bool _downloading = false;
  String? _error;
  String? _success;
  String _format = 'pdf';

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
      _success = null;
    });
    try {
      final bytes = await context
          .read<AppState>()
          .api
          .adminReport(format: _format);
      final now = _eatNow();
      final name = 'taskflow-platform-report-${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}.$_format';
      final location = await FilePicker.platform.saveFile(
        fileName: name,
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted) {
        setState(() {
          _success = location == null
              ? 'Report save was cancelled.'
              : 'Report saved as $name.';
          _downloading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _downloading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Report download failed. Please try again.';
          _downloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _SectionPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeader(
            title: 'Reports',
            subtitle:
                'Choose a format for a current snapshot of platform data.',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in ['pdf', 'xlsx', 'csv'])
                ChoiceChip(
                  label: Text(format == 'pdf'
                      ? 'PDF report'
                      : format == 'xlsx'
                          ? 'Excel workbook'
                          : 'Raw data'),
                  selected: _format == format,
                  onSelected: (_) => setState(() {
                    _format = format;
                    _success = null;
                    _error = null;
                  }),
                  selectedColor: Theme.of(context).brightness == Brightness.dark
                      ? _kViolet.withValues(alpha: 0.22)
                      : _kVioletLight,
                  side: BorderSide(
                      color: _format == format ? _kViolet : _kLine),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? _kLineDark : _kLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.summarize_outlined,
                      size: 20, color: _kViolet),
                  const SizedBox(width: 8),
                  Text(_format == 'pdf'
                          ? 'PDF report'
                          : _format == 'xlsx'
                              ? 'Excel workbook'
                              : 'Raw data',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                Text(
                  _format == 'pdf'
                      ? 'Presentation-ready platform totals, task status, and project progress.'
                      : _format == 'xlsx'
                          ? 'A summary and filterable workbook with platform records.'
                          : 'Clean rows for users, organizations, projects, and tasks.',
                  style: const TextStyle(fontSize: 13, color: _kMuted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: _downloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_outlined, size: 18),
                  label: Text(_downloading
                      ? 'Preparing report…'
                      : 'Download ${_format.toUpperCase()}'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(_error!),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            _FeedbackBanner(message: _success!, success: true),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 9 — Platform Settings
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminPlatformSettings extends StatelessWidget {
  const _AdminPlatformSettings();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _SectionPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeader(
            title: 'Platform Settings',
            subtitle: 'Safe read-only platform information.',
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? _kLineDark : _kLine),
            ),
            child: const Column(
              children: [
                _SettingsRow(label: 'Application', value: 'TaskFlow'),
                Divider(height: 20),
                _SettingsRow(label: 'Platform', value: 'Sababisha PMS'),
                Divider(height: 20),
                _SettingsRow(
                    label: 'API endpoint', value: 'Configured via dart-define'),
                Divider(height: 20),
                _SettingsRow(label: 'Mobile client', value: 'Flutter'),
                Divider(height: 20),
                Text(
                  'Theme, credentials, and runtime configuration are '
                  'managed from Account & Settings.',
                  style: TextStyle(fontSize: 12, color: _kMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 13, color: _kMuted)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared primitive widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) =>
      _Banner(message: message, color: _kDanger, icon: Icons.error_outline);
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) =>
      _Banner(message: message, color: _kViolet, icon: Icons.info_outline);
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.success});
  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) => _Banner(
      message: message,
      color: success ? _kSuccess : _kDanger,
      icon: success ? Icons.check_circle_outline : Icons.error_outline);
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.message, required this.color, required this.icon});
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 8),
        Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: color))),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _kMuted),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 11, color: _kMuted)),
        ],
      );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: _kDanger)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void _snackError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: _kDanger,
    behavior: SnackBarBehavior.floating,
  ));
}

String _fmtDate(String iso) {
  try {
    final dt = _dateInEat(iso);
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  } catch (_) {
    return iso;
  }
}
