import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import 'settings_screen.dart';

// ─── Palette (mirrors web + app.dart) ─────────────────────────────────────────
const _kViolet      = Color(0xFF4D40ED);
const _kVioletLight = Color(0xFFEEEDFF);
const _kDanger      = Color(0xFFEF4444);
const _kWarning     = Color(0xFFF59E0B);
const _kSuccess     = Color(0xFF22C55E);
const _kMuted       = Color(0xFF9EA3B0);
const _kLine        = Color(0xFFE5E7EB);
const _kLineDark    = Color(0xFF343845);

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
  health,
  reports,
  platformSettings,
  accountSettings,
}

extension _AdminSectionExt on _AdminSection {
  String get label {
    switch (this) {
      case _AdminSection.overview:          return 'Overview';
      case _AdminSection.analytics:         return 'Analytics';
      case _AdminSection.users:             return 'Users';
      case _AdminSection.organizations:     return 'Organizations';
      case _AdminSection.projects:          return 'Projects';
      case _AdminSection.activity:          return 'Activity';
      case _AdminSection.health:            return 'System Health';
      case _AdminSection.reports:           return 'Reports';
      case _AdminSection.platformSettings:  return 'Platform Settings';
      case _AdminSection.accountSettings:   return 'Account & Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case _AdminSection.overview:         return Icons.dashboard_outlined;
      case _AdminSection.analytics:        return Icons.bar_chart_outlined;
      case _AdminSection.users:            return Icons.people_outlined;
      case _AdminSection.organizations:    return Icons.business_outlined;
      case _AdminSection.projects:         return Icons.folder_outlined;
      case _AdminSection.activity:         return Icons.show_chart;
      case _AdminSection.health:           return Icons.favorite_border;
      case _AdminSection.reports:          return Icons.file_download_outlined;
      case _AdminSection.platformSettings: return Icons.settings_outlined;
      case _AdminSection.accountSettings:  return Icons.manage_accounts_outlined;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case _AdminSection.overview:         return Icons.dashboard;
      case _AdminSection.analytics:        return Icons.bar_chart;
      case _AdminSection.users:            return Icons.people;
      case _AdminSection.organizations:    return Icons.business;
      case _AdminSection.projects:         return Icons.folder;
      case _AdminSection.activity:         return Icons.show_chart;
      case _AdminSection.health:           return Icons.favorite;
      case _AdminSection.reports:          return Icons.file_download;
      case _AdminSection.platformSettings: return Icons.settings;
      case _AdminSection.accountSettings:  return Icons.manage_accounts;
    }
  }
}

// ─── Nav group definitions (mirrors web AdminNav sections) ────────────────────
const _navGroups = [
  _NavGroup('PLATFORM',       [_AdminSection.overview, _AdminSection.analytics]),
  _NavGroup('MANAGEMENT',     [_AdminSection.users, _AdminSection.organizations, _AdminSection.projects]),
  _NavGroup('MONITORING',     [_AdminSection.activity, _AdminSection.health]),
  _NavGroup('REPORTING',      [_AdminSection.reports]),
  _NavGroup('ADMINISTRATION', [_AdminSection.platformSettings]),
  _NavGroup('ACCOUNT',        [_AdminSection.accountSettings]),
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
  _AdminSection _section = _AdminSection.overview;

  void _navigate(_AdminSection s) {
    setState(() => _section = s);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF13151F) : const Color(0xFFF4F5FA);
    final border = isDark ? _kLineDark : _kLine;

    return Scaffold(
      backgroundColor: bg,

      // ── AppBar ─────────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        automaticallyImplyLeading: false,
        shape: Border(bottom: BorderSide(color: border, width: 1)),

        // Left: logo mark + section breadcrumb
        title: Row(
          children: [
            // Violet shield icon — brand mark
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _kViolet,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Super Admin',
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
          // Menu button — opens the side nav drawer
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu_rounded,
                  size: 22,
                  color: isDark ? Colors.white70 : const Color(0xFF4A4F6A)),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              tooltip: 'Navigation',
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),

      // ── Side drawer ────────────────────────────────────────────────────────
      endDrawer: _AdminDrawer(
        current: _section,
        onNavigate: _navigate,
        isDark: isDark,
      ),

      // ── Content ────────────────────────────────────────────────────────────
      body: _buildSection(),
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
        return const _AdminOrganizations();
      case _AdminSection.projects:
        return const _AdminProjects();
      case _AdminSection.activity:
        return const _AdminActivity();
      case _AdminSection.health:
        return const _AdminHealth();
      case _AdminSection.reports:
        return const _AdminReports();
      case _AdminSection.platformSettings:
        return const _AdminPlatformSettings();
      case _AdminSection.accountSettings:
        return SettingsScreen(
          onSignedOut: widget.onSignedOut,
          onToggleTheme: widget.onToggleTheme,
          themeMode: widget.themeMode,
        );
    }
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
  });

  final _AdminSection current;
  final void Function(_AdminSection) onNavigate;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg     = isDark ? const Color(0xFF1B1D2A) : Colors.white;
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
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kViolet,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.shield_outlined,
                      color: Colors.white, size: 20),
                ),
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
                    Text(
                      'Platform Administration',
                      style: TextStyle(fontSize: 11, color: _kMuted),
                    ),
                  ],
                ),
              ]),
            ),
            Divider(height: 1, color: border),
            const SizedBox(height: 8),

            // ── Nav groups ──────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                children: [
                  for (final group in _navGroups) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 14, 12, 4),
                      child: Text(
                        group.label,
                        style: TextStyle(
                          fontSize: 9.5,
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Text(
                'Sababisha PMS · v0.1.0',
                style: TextStyle(fontSize: 11, color: _kMuted),
              ),
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
                ? (isDark
                    ? _kViolet.withValues(alpha: 0.18)
                    : _kVioletLight)
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
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400,
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
  });

  final String title;
  final String subtitle;
  final Widget? action;

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
                Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
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

class _AdminOverview extends StatefulWidget {
  const _AdminOverview();

  @override
  State<_AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<_AdminOverview> {
  bool _downloading = false;
  String? _downloadMsg;
  bool _downloadSuccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppState>().loadAdminDashboard());
  }

  Future<void> _downloadReport() async {
    setState(() {
      _downloading = true;
      _downloadMsg = null;
    });
    try {
      final bytes = await context.read<AppState>().api.adminReport();
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final name =
          'taskflow-report-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      if (mounted) {
        setState(() {
          _downloadSuccess = true;
          _downloadMsg = 'Saved to ${file.path}';
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final m = state.adminMetrics;

    final cards = [
      _MetricDef('Total Users',         Icons.people_outlined,          m?.totalUsers),
      _MetricDef('Organizations',        Icons.business_outlined,        m?.totalOrganizations),
      _MetricDef('Total Projects',       Icons.folder_outlined,          m?.totalProjects),
      _MetricDef('Total Tasks',          Icons.format_list_bulleted,     m?.totalTasks),
      _MetricDef('Completed Tasks',      Icons.check_circle_outline,     m?.completedTasks),
      _MetricDef('Active Projects',      Icons.show_chart,               m?.activeProjects),
    ];

    return _SectionPage(
      onRefresh: () => context.read<AppState>().loadAdminDashboard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            title: 'Super Admin Dashboard',
            subtitle: 'System-wide overview of TaskFlow.',
            action: FilledButton.icon(
              onPressed: _downloading ? null : _downloadReport,
              icon: _downloading
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.file_download_outlined, size: 17),
              label: Text(_downloading ? 'Saving…' : 'Download Report',
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
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 108,
              ),
              itemCount: cards.length,
              itemBuilder: (_, i) => _MetricCard(def: cards[i]),
            ),

          // Download feedback
          if (_downloadMsg != null) ...[
            const SizedBox(height: 16),
            _FeedbackBanner(
                message: _downloadMsg!, success: _downloadSuccess),
          ],

          // Hint
          if (m != null) ...[
            const SizedBox(height: 16),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 12, color: _kMuted),
                children: [
                  TextSpan(text: 'For charts open '),
                  TextSpan(
                      text: 'Analytics',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: _kViolet)),
                  TextSpan(
                      text: ' from the menu. Metrics refresh every 30 s.'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricDef {
  const _MetricDef(this.label, this.icon, this.value);
  final String label;
  final IconData icon;
  final int? value;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.def});
  final _MetricDef def;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? _kLineDark : _kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _kVioletLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(def.icon, size: 17, color: _kViolet),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                def.label,
                style: const TextStyle(
                    fontSize: 11,
                    color: _kMuted,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            def.value != null ? '${def.value}' : '—',
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w700),
          ),
        ],
      ),
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

  String _from(int d) {
    final dt = DateTime.now().subtract(Duration(days: d));
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String get _today {
    final dt = DateTime.now();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() => context.read<AppState>().loadAdminAnalytics(
      from: _from(_days), to: _today);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final a = state.adminAnalytics;
    final hasData = a != null &&
        (a.userGrowth.isNotEmpty ||
            a.projectGrowth.isNotEmpty ||
            a.tasksByStatus.isNotEmpty ||
            a.tasksByPriority.isNotEmpty);

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
                selectedColor: _kVioletLight,
                labelStyle: TextStyle(
                  color: _days == d ? _kViolet : _kMuted,
                  fontWeight:
                      _days == d ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 13,
                ),
                side: BorderSide(color: _days == d ? _kViolet : _kLine),
                shape: const StadiumBorder(),
              ),
          ]),
          const SizedBox(height: 16),

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
              child: _BarChart(data: a.userGrowth, color: _kViolet),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Project Growth',
              child: _BarChart(
                  data: a.projectGrowth,
                  color: const Color(0xFF06B6D4)),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Tasks by Status',
              child: _HorizBar(data: a.tasksByStatus, color: _kSuccess),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Tasks by Priority',
              child: _HorizBar(data: a.tasksByPriority, color: _kWarning),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

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
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.data, required this.color});
  final List<AdminGrowthPoint> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Text('No data for this period.',
          style: TextStyle(color: _kMuted, fontSize: 13));
    }
    final maxVal = data.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((pt) {
          final ratio = maxVal > 0 ? pt.count / maxVal : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (pt.count > 0)
                    Text('${pt.count}',
                        style: const TextStyle(
                            fontSize: 8, color: _kMuted)),
                  const SizedBox(height: 2),
                  Flexible(
                    flex: (ratio * 100).round().clamp(1, 100),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.85),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _shortDate(pt.date),
                    style: const TextStyle(
                        fontSize: 7.5, color: _kMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _shortDate(String iso) {
    if (iso.length < 10) return iso;
    final p = iso.substring(0, 10).split('-');
    return p.length < 3 ? iso : '${p[1]}/${p[2]}';
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
                      style: const TextStyle(
                          fontSize: 12, color: _kMuted)),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppState>().loadAdminUsers());
  }

  @override
  void dispose() {
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
    final rows  = _filtered(state.adminUsers);

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
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text(
                          'Manage and monitor registered TaskFlow accounts.',
                          style:
                              TextStyle(fontSize: 12, color: _kMuted)),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        _showCreateUser(context, state),
                    icon:
                        const Icon(Icons.person_add_outlined, size: 17),
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
                        style: const TextStyle(
                            fontSize: 14, color: _kMuted),
                      ),
                    )
                  : RefreshIndicator(
                      color: _kViolet,
                      onRefresh: () =>
                          context.read<AppState>().loadAdminUsers(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
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
                  color: _kViolet,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  _StatusPill(user.status),
                ]),
                Text(user.email,
                    style: const TextStyle(
                        fontSize: 12, color: _kMuted),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${user.organizationCount} org${user.organizationCount != 1 ? 's' : ''} · ${_fmtDate(user.createdAt)}',
                  style: const TextStyle(
                      fontSize: 11, color: _kMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 18, color: _kMuted),
            onSelected: (a) => _handleAction(context, a),
            itemBuilder: (_) => [
              if (!isSuspended)
                const PopupMenuItem(
                  value: 'suspend',
                  child: Row(children: [
                    Icon(Icons.block_outlined,
                        size: 16, color: _kWarning),
                    SizedBox(width: 8),
                    Text('Suspend'),
                  ]),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline,
                      size: 16, color: _kDanger),
                  SizedBox(width: 8),
                  Text('Delete permanently',
                      style: TextStyle(color: _kDanger)),
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
  final _formKey  = GlobalKey<FormState>();
  final _first    = TextEditingController();
  final _last     = TextEditingController();
  final _email    = TextEditingController();
  final _pass     = TextEditingController();
  final _tz       = TextEditingController(text: 'UTC');
  bool _loading   = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose(); _last.dispose(); _email.dispose();
    _pass.dispose();  _tz.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AppState>().api.adminCreateUser(
        firstName: _first.text.trim(),
        lastName:  _last.text.trim(),
        email:     _email.text.trim(),
        password:  _pass.text,
        timezone:  _tz.text.trim().isEmpty ? 'UTC' : _tz.text.trim(),
      );
      if (!mounted) return;
      await context.read<AppState>().loadAdminUsers();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() { _loading = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Create user account',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _first,
                    decoration: const InputDecoration(
                        labelText: 'First name *'),
                    validator: (v) =>
                        v?.trim().isEmpty == true ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _last,
                    decoration: const InputDecoration(
                        labelText: 'Last name *'),
                    validator: (v) =>
                        v?.trim().isEmpty == true ? 'Required' : null,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                    labelText: 'Email address *'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v?.trim().isEmpty == true) return 'Required';
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                      .hasMatch(v!.trim())) {
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
                    onPressed:
                        _loading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
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
  const _AdminOrganizations();

  @override
  State<_AdminOrganizations> createState() => _AdminOrganizationsState();
}

class _AdminOrganizationsState extends State<_AdminOrganizations> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppState>().loadAdminOrgs());
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<AdminOrganization> _filtered(List<AdminOrganization> all) {
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all
        .where((o) =>
            o.name.toLowerCase().contains(q) ||
            o.slug.toLowerCase().contains(q) ||
            (o.owner ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rows  = _filtered(state.adminOrgs);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Organizations',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text(
                  'View organizations across the TaskFlow platform.',
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
                        style: const TextStyle(
                            fontSize: 14, color: _kMuted),
                      ),
                    )
                  : RefreshIndicator(
                      color: _kViolet,
                      onRefresh: () =>
                          context.read<AppState>().loadAdminOrgs(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (_, i) => _OrgTile(rows[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _OrgTile extends StatelessWidget {
  const _OrgTile(this.org);
  final AdminOrganization org;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? _kLineDark : _kLine),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _kVioletLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.business_outlined,
              size: 18, color: _kViolet),
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
                  style: const TextStyle(
                      fontSize: 11, color: _kMuted)),
              const SizedBox(height: 4),
              Row(children: [
                _InfoChip(Icons.people_outline,
                    '${org.memberCount} members'),
                const SizedBox(width: 8),
                _InfoChip(Icons.folder_outlined,
                    '${org.projectCount} projects'),
              ]),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(org.owner ?? 'No owner',
                style: const TextStyle(
                    fontSize: 11, color: _kMuted)),
            const SizedBox(height: 2),
            Text(_fmtDate(org.createdAt),
                style: const TextStyle(
                    fontSize: 11, color: _kMuted)),
          ],
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5 — Projects
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminProjects extends StatefulWidget {
  const _AdminProjects();

  @override
  State<_AdminProjects> createState() => _AdminProjectsState();
}

class _AdminProjectsState extends State<_AdminProjects> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppState>().loadAdminProjects());
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<AdminProject> _filtered(List<AdminProject> all) =>
      all.where((p) {
        final q = _search.toLowerCase();
        return (q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                (p.organizationName ?? '').toLowerCase().contains(q) ||
                p.displayStatus.toLowerCase().contains(q)) &&
            (_statusFilter.isEmpty ||
                p.displayStatus == _statusFilter);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rows  = _filtered(state.adminProjects);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Projects',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text(
                  'Read-only oversight of projects across the platform.',
                  style: TextStyle(fontSize: 12, color: _kMuted)),
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
                    '', 'PLANNING', 'ACTIVE',
                    'ON_HOLD', 'COMPLETED', 'ARCHIVED'
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(s.isEmpty ? 'All' : s,
                            style: const TextStyle(fontSize: 11)),
                        selected: _statusFilter == s,
                        onSelected: (_) =>
                            setState(() => _statusFilter = s),
                        selectedColor: _kVioletLight,
                        labelStyle: TextStyle(
                            color: _statusFilter == s
                                ? _kViolet
                                : _kMuted),
                        side: BorderSide(
                            color: _statusFilter == s
                                ? _kViolet
                                : _kLine),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 0),
                      ),
                    ),
                ]),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.loadingAdminProjects &&
                  state.adminProjects.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(_kViolet)))
              : rows.isEmpty
                  ? Center(
                      child: Text(
                        _search.isEmpty
                            ? 'No projects found.'
                            : 'No projects match "$_search".',
                        style: const TextStyle(
                            fontSize: 14, color: _kMuted),
                      ),
                    )
                  : RefreshIndicator(
                      color: _kViolet,
                      onRefresh: () =>
                          context.read<AppState>().loadAdminProjects(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (_, i) => _ProjectTile(rows[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile(this.project);
  final AdminProject project;

  Color _statusColor(String s) {
    switch (s) {
      case 'ACTIVE':    return _kSuccess;
      case 'COMPLETED': return _kViolet;
      case 'ON_HOLD':   return _kWarning;
      case 'ARCHIVED':  return _kMuted;
      default:          return const Color(0xFF06B6D4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final color   = _statusColor(project.displayStatus);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? _kLineDark : _kLine),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
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
                  style: const TextStyle(
                      fontSize: 12, color: _kMuted)),
              const SizedBox(height: 4),
              Row(children: [
                _InfoChip(Icons.task_alt_outlined,
                    '${project.taskCount} tasks'),
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
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 3),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 6 — Activity
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminActivity extends StatelessWidget {
  const _AdminActivity();

  @override
  Widget build(BuildContext context) {
    return const _SectionPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            title: 'Activity',
            subtitle: 'Platform audit activity.',
          ),
          _InfoBanner(
            'TaskFlow does not currently store a persistent platform '
            'audit log. This page intentionally does not present sample '
            'activity as real data.',
          ),
        ],
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<AppState>().loadAdminHealth();
    if (mounted) setState(() => _lastChecked = DateTime.now());
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
                      child: CircularProgressIndicator(
                          strokeWidth: 2))
                  : const Icon(Icons.refresh_outlined, size: 16),
              label: const Text('Refresh'),
            ),
            if (_lastChecked != null) ...[
              const SizedBox(width: 12),
              Text(
                'Last checked ${_fmtTime(_lastChecked!)}',
                style: const TextStyle(
                    fontSize: 12, color: _kMuted),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          if (state.loadingAdminHealth && h == null)
            const Center(
                child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation(_kViolet)))
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

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({required this.label, required this.status});
  final String label;
  final String status;

  Color get _color {
    switch (status.toLowerCase()) {
      case 'healthy':  return _kSuccess;
      case 'degraded': return _kWarning;
      default:         return _kDanger;
    }
  }

  IconData get _icon {
    switch (status.toLowerCase()) {
      case 'healthy':  return Icons.check_circle_outline;
      case 'degraded': return Icons.warning_amber_outlined;
      default:         return Icons.error_outline;
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
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: _kMuted)),
            Text(status,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _color)),
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

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
      _success = null;
    });
    try {
      final bytes = await context.read<AppState>().api.adminReport();
      final dir  = await getTemporaryDirectory();
      final now  = DateTime.now();
      final name =
          'taskflow-report-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      if (mounted) {
        setState(() {
          _success = 'Saved to ${file.path}';
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
            subtitle: 'Generate and export system-wide TaskFlow reports.',
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1B1D2A) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isDark ? _kLineDark : _kLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.summarize_outlined,
                      size: 20, color: _kViolet),
                  SizedBox(width: 8),
                  Text('System Report',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Exports all users, organizations, projects, and tasks '
                  'in CSV format.',
                  style: TextStyle(fontSize: 13, color: _kMuted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: _downloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.download_outlined,
                          size: 18),
                  label: Text(
                      _downloading ? 'Downloading…' : 'Download CSV'),
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
              border: Border.all(
                  color: isDark ? _kLineDark : _kLine),
            ),
            child: const Column(
              children: [
                _SettingsRow(
                    label: 'Application', value: 'TaskFlow'),
                Divider(height: 20),
                _SettingsRow(
                    label: 'Platform', value: 'Sababisha PMS'),
                Divider(height: 20),
                _SettingsRow(
                    label: 'API endpoint',
                    value: 'Configured via dart-define'),
                Divider(height: 20),
                _SettingsRow(
                    label: 'Mobile client', value: 'Flutter'),
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
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        Text(value,
            style: const TextStyle(fontSize: 13, color: _kMuted)),
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
  Widget build(BuildContext context) => _Banner(
      message: message,
      color: _kDanger,
      icon: Icons.error_outline);
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => _Banner(
      message: message,
      color: _kViolet,
      icon: Icons.info_outline);
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.success});
  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) => _Banner(
      message: message,
      color: success ? _kSuccess : _kDanger,
      icon: success
          ? Icons.check_circle_outline
          : Icons.error_outline);
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.message,
      required this.color,
      required this.icon});
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
            child: Text(message,
                style: TextStyle(fontSize: 13, color: color))),
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
      Text(label,
          style: const TextStyle(fontSize: 11, color: _kMuted)),
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
    final dt = DateTime.parse(iso);
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  } catch (_) {
    return iso;
  }
}
