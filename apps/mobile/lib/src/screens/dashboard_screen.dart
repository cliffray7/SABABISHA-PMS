import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'task_detail_screen.dart';

/// Matches the web Dashboard screen:
/// - 4-column metric grid (Project tasks / My open / My overdue / My in progress)
/// - Progress panel (project name + % bar + subtitle)
/// - Upcoming deadlines list
/// - Team workload list with bars
class DashboardScreen extends StatelessWidget {
  const DashboardScreen(
      {super.key, this.onOpenBoard, this.onOpenActivity, this.onFilterTasks});

  final VoidCallback? onOpenBoard;
  final VoidCallback? onOpenActivity;
  final ValueChanged<String>? onFilterTasks;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final account = state.account;
    final project = state.selectedProject;
    final tasks = state.tasks;
    final members = state.projectMembers;
    final userId = account?.id ?? '';

    if (state.loadingOrgs) {
      return const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(kViolet)),
      );
    }

    if (state.selectedOrg == null) {
      return EmptyState(
        icon: Icons.business_outlined,
        title: 'No organization yet',
        message:
            'Create your first organization to start planning projects and tracking tasks.',
        action: () => _showCreateOrgDialog(context, state),
        actionLabel: 'Create organization',
      );
    }

    if (project == null) {
      return EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No project selected',
        message: state.projects.isEmpty
            ? 'Create a project to start adding tasks.'
            : 'Choose a project from your account menu.',
        action: state.selectedOrg!.role == 'GUEST'
            ? null
            : () => _showCreateProjectDialog(context, state),
        actionLabel: state.selectedOrg!.role == 'GUEST' ? null : 'New project',
      );
    }

    final canSeeTeamData =
        state.selectedOrg!.isAdminOrOwner || project.isManagerOrLead;
    final mine =
        tasks.where((task) => task.assigneeIds.contains(userId)).toList();
    final scopeTasks = canSeeTeamData ? tasks : mine;
    final done = scopeTasks.where((task) => task.status == 'DONE').length;
    final progress = scopeTasks.isEmpty ? 0.0 : done / scopeTasks.length;
    final open = scopeTasks.where((task) => task.status != 'DONE').length;
    final overdue = scopeTasks.where((task) => task.isOverdue).length;
    final priorities = mine.where((task) => task.status != 'DONE').toList()
      ..sort((a, b) {
        final overdueOrder = (b.isOverdue ? 1 : 0) - (a.isOverdue ? 1 : 0);
        if (overdueOrder != 0) return overdueOrder;
        return (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999');
      });
    final activity = _loadDashboardActivity(state);
    final wide = MediaQuery.sizeOf(context).width >= 960;
    void openFilter(String filter) {
      if (onFilterTasks != null) {
        onFilterTasks!(filter);
      } else {
        onOpenBoard?.call();
      }
    }

    return RefreshIndicator(
      color: kViolet,
      onRefresh: () => state.refreshTasks(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(wide ? 20 : 8, 16, wide ? 20 : 8, 24),
        children: [
          Text('${state.selectedOrg!.name.toUpperCase()} / OVERVIEW',
              style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: kMuted)),
          const SizedBox(height: 8),
          Text(
              'Welcome back, ${account?.firstName ?? ''} ${account?.lastName ?? ''}'
                  .trim(),
              style: GoogleFonts.dmSans(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: kInk)),
          const SizedBox(height: 4),
          const Text("A clear view of your team's work.",
              style: TextStyle(fontSize: 12, color: kMuted)),
          const SizedBox(height: 12),
          Row(children: [
            if (state.selectedOrg!.role != 'GUEST')
              Expanded(
                  child: OutlinedButton(
                onPressed: () => _showCreateProjectDialog(context, state),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: kLine),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                child: const Text('New project',
                    style: TextStyle(fontSize: 12, color: kInk)),
              )),
            if (state.selectedOrg!.role != 'GUEST' && project.canWrite)
              const SizedBox(width: 8),
            if (project.canWrite)
              Expanded(
                  child: FilledButton.icon(
                onPressed: () => _showCreateTaskDialog(context, state),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    backgroundColor: kViolet,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('New task', style: TextStyle(fontSize: 12)),
              )),
          ]),
          const SizedBox(height: 14),
          _MetricGrid(items: [
            _MetricItem(
                label: canSeeTeamData ? 'Total tasks' : 'My tasks',
                value: '${scopeTasks.length}',
                icon: Icons.checklist_rounded,
                color: const Color(0xFF8275E8),
                softColor: const Color(0xFFF0EEFF),
                onTap: () => openFilter(canSeeTeamData ? '' : 'MINE')),
            _MetricItem(
                label: canSeeTeamData ? 'Open' : 'My open',
                value: '$open',
                icon: Icons.radio_button_unchecked,
                color: const Color(0xFF3D85D8),
                softColor: const Color(0xFFECF5FF),
                onTap: () => openFilter('OPEN')),
            _MetricItem(
                label: canSeeTeamData ? 'Overdue' : 'My overdue',
                value: '$overdue',
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFD44570),
                softColor: const Color(0xFFFFEAF1),
                numberColor: kDanger,
                onTap: () => openFilter('OVERDUE')),
            _MetricItem(
                label: 'Completed',
                value: '$done',
                icon: Icons.schedule_rounded,
                color: const Color(0xFFD97716),
                softColor: const Color(0xFFFFF1E3),
                onTap: () => openFilter('COMPLETED')),
          ]),
          const SizedBox(height: 12),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  flex: 3,
                  child: _ListPanel(
                      minHeight: 376,
                      title: 'Task progress',
                      subtitle: 'Created and completed · last 7 days',
                      child: _TaskTrend(tasks: scopeTasks, expanded: true))),
              const SizedBox(width: 16),
              Expanded(
                  flex: 2,
                  child: _ListPanel(
                      minHeight: 376,
                      title: 'Task distribution',
                      subtitle: 'Current status across the project',
                      child: _TaskDistribution(
                          tasks: scopeTasks, expanded: true))),
            ])
          else ...[
            _ListPanel(
                title: 'Task progress',
                subtitle: 'Created and completed · last 7 days',
                child: _TaskTrend(tasks: scopeTasks)),
            const SizedBox(height: 12),
            _ListPanel(
                title: 'Task distribution',
                subtitle: 'Current status across the project',
                child: _TaskDistribution(tasks: scopeTasks)),
          ],
          const SizedBox(height: 12),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  flex: 3,
                  child: _ListPanel(
                      minHeight: 230,
                      title: 'My priorities',
                      trailing: 'Open board',
                      onTrailing: onOpenBoard,
                      subtitle: 'Assigned work that needs your attention',
                      child: _PriorityList(tasks: priorities, state: state))),
              const SizedBox(width: 16),
              Expanded(
                  flex: 2,
                  child: _ListPanel(
                      minHeight: 230,
                      title: canSeeTeamData ? 'Project health' : 'My workload',
                      subtitle:
                          canSeeTeamData ? project.name : 'Your assigned work',
                      trailing:
                          canSeeTeamData ? project.status.toLowerCase() : null,
                      child: _HealthDetails(
                          project: project,
                          progress: progress,
                          done: done,
                          total: scopeTasks.length,
                          memberCount: members.length,
                          tasks: scopeTasks,
                          showTeamData: canSeeTeamData))),
            ])
          else ...[
            _ListPanel(
                title: 'My priorities',
                trailing: 'Open board',
                onTrailing: onOpenBoard,
                subtitle: 'Assigned work that needs your attention',
                child: _PriorityList(tasks: priorities, state: state)),
            const SizedBox(height: 12),
            _ListPanel(
                title: canSeeTeamData ? 'Project health' : 'My workload',
                subtitle: canSeeTeamData ? project.name : 'Your assigned work',
                trailing: canSeeTeamData ? project.status.toLowerCase() : null,
                child: _HealthDetails(
                    project: project,
                    progress: progress,
                    done: done,
                    total: scopeTasks.length,
                    memberCount: members.length,
                    tasks: scopeTasks,
                    showTeamData: canSeeTeamData)),
          ],
          const SizedBox(height: 12),
          if (canSeeTeamData && wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: _ListPanel(
                      title: 'Upcoming deadlines',
                      trailing: 'All tasks',
                      onTrailing: onOpenBoard,
                      subtitle: 'Open project tasks due soon',
                      child:
                          _UpcomingDeadlines(tasks: scopeTasks, state: state))),
              const SizedBox(width: 16),
              Expanded(
                  child: _ListPanel(
                      title: 'Team workload',
                      trailing: 'Team',
                      onTrailing: onOpenBoard,
                      subtitle: 'Open tasks by project member',
                      child: _TeamWorkload(members: members, tasks: tasks))),
            ])
          else ...[
            _ListPanel(
                title: 'Upcoming deadlines',
                trailing: 'All tasks',
                onTrailing: onOpenBoard,
                subtitle: 'Open project tasks due soon',
                child: _UpcomingDeadlines(tasks: scopeTasks, state: state)),
            const SizedBox(height: 12),
          ],
          if (canSeeTeamData && !wide) ...[
            _ListPanel(
                title: 'Team workload',
                trailing: 'Team',
                onTrailing: onOpenBoard,
                subtitle: 'Open tasks by project member',
                child: _TeamWorkload(members: members, tasks: tasks)),
            const SizedBox(height: 12),
          ],
          _ListPanel(
              title: 'Recent activity',
              trailing: 'View all',
              onTrailing: onOpenActivity,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: activity,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator(minHeight: 2);
                  }
                  if (snapshot.hasError) {
                    return const Text('Activity is unavailable.',
                        style: TextStyle(fontSize: 11, color: kMuted));
                  }
                  final events = snapshot.data ?? const [];
                  if (events.isEmpty) {
                    return const Text('No recent activity.',
                        style: TextStyle(fontSize: 11, color: kMuted));
                  }
                  return Column(
                      children: events
                          .take(5)
                          .map((event) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(event['description'] as String? ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 10, color: kInk)),
                                    const SizedBox(height: 3),
                                    Text(
                                        '${event['actorName'] ?? 'Someone'} \u00b7 ${event['createdAt'] ?? ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 9, color: kMuted)),
                                    const Divider(height: 10),
                                  ])))
                          .toList());
                },
              )),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Metric grid ──────────────────────────────────────────────────────────────
// Web .metric-grid: 4 cols, .metric: 24px padding, 40px number, 15px label

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});
  final List<_MetricItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 960 ? 4 : 2;
      const gap = 12.0;
      final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: items
            .map((item) => SizedBox(
                width: itemWidth,
                child: _MetricCard(item: item, spacious: columns == 4)))
            .toList(),
      );
    });
  }
}

class _MetricItem {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.softColor,
    this.numberColor = kInk,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color softColor;
  final Color numberColor;
  final VoidCallback? onTap;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item, this.spacious = false});
  final _MetricItem item;
  final bool spacious;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(spacious ? 12 : 8),
      child: Container(
        height: spacious ? 182 : 90,
        padding: EdgeInsets.all(spacious ? 20 : 10),
        decoration: BoxDecoration(
          color: isDark ? kPanelDark : kPanel,
          borderRadius: BorderRadius.circular(spacious ? 12 : 8),
          border: Border.all(color: isDark ? const Color(0xFF343845) : kLine),
          boxShadow: isDark
              ? null
              : const [
                  BoxShadow(
                      color: Color(0x0C232744),
                      blurRadius: 9,
                      offset: Offset(0, 3))
                ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(item.label,
                    style: TextStyle(
                        fontSize: spacious ? 16 : 10, color: kMuted))),
            Container(
                width: spacious ? 42 : 23,
                height: spacious ? 42 : 23,
                decoration: BoxDecoration(
                    color: item.softColor,
                    borderRadius: BorderRadius.circular(spacious ? 12 : 7)),
                child: Icon(item.icon,
                    size: spacious ? 23 : 14, color: item.color)),
          ]),
          const Spacer(),
          Text(item.value,
              style: GoogleFonts.dmSans(
                  fontSize: spacious ? 34 : 18,
                  fontWeight: FontWeight.bold,
                  color: item.numberColor,
                  height: 1)),
          const Spacer(),
          Row(children: [
            Text('View tasks',
                style: TextStyle(fontSize: spacious ? 14 : 8, color: kViolet)),
            SizedBox(width: spacious ? 6 : 3),
            Icon(Icons.arrow_forward_rounded,
                size: spacious ? 16 : 10, color: kViolet)
          ]),
        ]),
      ),
    );
  }
}

// ─── Progress panel ───────────────────────────────────────────────────────────
// Web .progress-panel: name + %, progress bar, subtitle

class _ListPanel extends StatelessWidget {
  const _ListPanel(
      {required this.title,
      required this.child,
      this.subtitle,
      this.trailing,
      this.onTrailing,
      this.minHeight});
  final String title;
  final Widget child;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTrailing;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spacious = MediaQuery.sizeOf(context).width >= 960;
    return Container(
      constraints:
          minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      padding: EdgeInsets.all(spacious ? 22 : 12),
      decoration: BoxDecoration(
        color: isDark ? kPanelDark : kPanel,
        borderRadius: BorderRadius.circular(spacious ? 12 : 8),
        border: Border.all(
          color: isDark ? const Color(0xFF343845) : kLine,
        ),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0C232744),
                  blurRadius: 9,
                  offset: Offset(0, 3),
                )
              ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: GoogleFonts.dmSans(
                      fontSize: spacious ? 21 : 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFEEF0F8) : kInk))),
          if (trailing != null)
            InkWell(
                onTap: onTrailing,
                child: Text(trailing!,
                    style: TextStyle(
                        fontSize: spacious ? 14 : 9,
                        color: kViolet,
                        fontWeight: FontWeight.w600))),
        ]),
        if (subtitle != null) ...[
          SizedBox(height: spacious ? 5 : 3),
          Text(subtitle!,
              style: TextStyle(fontSize: spacious ? 13 : 9, color: kMuted)),
        ],
        SizedBox(height: spacious ? 16 : 10),
        child,
      ]),
    );
  }
}

// ─── Upcoming deadlines ───────────────────────────────────────────────────────
// Web .task-list-row: flex row, name + due date (red if overdue)

class _UpcomingDeadlines extends StatelessWidget {
  const _UpcomingDeadlines({required this.tasks, required this.state});
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final upcoming = ([...tasks]
          ..removeWhere((t) => t.status == 'DONE' || t.dueDate == null)
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!)))
        .take(4)
        .toList();

    if (upcoming.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('No upcoming deadlines.',
            style: TextStyle(color: kMuted, fontSize: 14)),
      );
    }

    return Column(
      children: upcoming
          .map((t) {
            final overdue = t.isOverdue;
            return InkWell(
              onTap: () => _openTask(context, t),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      t.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    dateLabel(t.dueDate),
                    style: TextStyle(
                      fontSize: 13,
                      color: overdue ? kDanger : kMuted,
                      fontWeight: overdue ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ]),
              ),
            );
          })
          .expand((w) sync* {
            yield const Divider(height: 1);
            yield w;
          })
          .skip(1)
          .toList(),
    );
  }

  void _openTask(BuildContext context, Task t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: TaskDetailScreen(taskId: t.id),
        ),
      ),
    );
  }
}

// ─── Team workload ────────────────────────────────────────────────────────────
// Web .workload-row: name + open count + bar (violet fill)

class _TeamWorkload extends StatelessWidget {
  const _TeamWorkload({required this.members, required this.tasks});
  final List<Member> members;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Text('No team members.',
          style: TextStyle(color: kMuted, fontSize: 14));
    }
    return Column(
      children: members.map((m) {
        final open = tasks
            .where(
                (t) => t.status != 'DONE' && t.assigneeIds.contains(m.userId))
            .length;
        final frac = tasks.isEmpty ? 0.0 : open / tasks.length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AvatarChip(
                initials: m.initials,
                size: 26,
                avatarUrl: m.avatarUrl,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.fullName,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                '$open open tasks',
                style: const TextStyle(fontSize: 12, color: kMuted),
              ),
            ]),
            const SizedBox(height: 5),
            // Workload bar — matches web .workload-row i
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 5,
                backgroundColor: const Color(0xFFEEEDF3),
                valueColor: const AlwaysStoppedAnimation(kViolet),
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ─── Create org dialog ────────────────────────────────────────────────────────

Future<List<Map<String, dynamic>>> _loadDashboardActivity(
    AppState state) async {
  final orgId = state.selectedOrg?.id;
  if (orgId == null) return const [];
  return state.api.workspaceActivityEvents(organizationId: orgId, pageSize: 4);
}

class _TaskTrend extends StatelessWidget {
  const _TaskTrend({required this.tasks, this.expanded = false});
  final List<Task> tasks;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final created = List<int>.filled(7, 0);
    final completed = List<int>.filled(7, 0);
    final today = DateTime.now();
    for (final task in tasks) {
      _countRecentDate(task.createdAt, today, created);
      if (task.status == 'DONE') {
        _countRecentDate(task.completedAt, today, completed);
      }
    }
    final available =
        tasks.any((task) => task.createdAt != null || task.completedAt != null);
    final labels = List.generate(7, (index) {
      final date = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: 6 - index));
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[date.weekday - 1];
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Spacer(),
        const Icon(Icons.circle, size: 7, color: Color(0xFF8275E8)),
        const SizedBox(width: 5),
        Text('Created',
            style: TextStyle(fontSize: expanded ? 11 : 8, color: kMuted)),
        SizedBox(width: expanded ? 14 : 8),
        const Icon(Icons.circle, size: 7, color: Color(0xFF49A58E)),
        const SizedBox(width: 5),
        Text('Completed',
            style: TextStyle(fontSize: expanded ? 11 : 8, color: kMuted)),
      ]),
      SizedBox(height: expanded ? 8 : 12),
      SizedBox(
          height: expanded ? 220 : 105,
          width: double.infinity,
          child: CustomPaint(
              painter: _TrendPainter(created, completed,
                  dark: Theme.of(context).brightness == Brightness.dark,
                  expanded: expanded))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final label in labels)
          Text(label,
              style: TextStyle(
                  fontSize: expanded ? 12 : 8,
                  color: kMuted,
                  fontWeight: expanded ? FontWeight.w500 : FontWeight.normal)),
      ]),
      SizedBox(height: expanded ? 12 : 6),
      Text(
          available
              ? expanded
                  ? 'Based on current tasks still in this project; reopened or deleted tasks may not appear in past counts.'
                  : 'Created and completed tasks over the last seven days.'
              : 'Task history is not available for this project yet.',
          style: TextStyle(fontSize: expanded ? 10 : 8, color: kMuted)),
    ]);
  }
}

void _countRecentDate(String? value, DateTime today, List<int> counts) {
  if (value == null || value.length < 10) return;
  final day = DateTime(today.year, today.month, today.day);
  for (var offset = 0; offset < 7; offset++) {
    final date = day.subtract(Duration(days: 6 - offset));
    final key =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (value.substring(0, 10) == key) counts[offset]++;
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.created, this.completed,
      {required this.dark, required this.expanded});
  final List<int> created;
  final List<int> completed;
  final bool dark;
  final bool expanded;
  @override
  void paint(Canvas canvas, Size size) {
    final left = expanded ? 30.0 : 0.0;
    final top = expanded ? 12.0 : 2.0;
    final right = size.width - 2;
    final bottom = size.height - 4;
    final maxValue = math.max(
        4, [...created, ...completed].fold<int>(0, (a, b) => math.max(a, b)));
    final grid = Paint()
      ..color = dark ? const Color(0xFF343845) : const Color(0xFFE5E6EF)
      ..strokeWidth = .7;
    final tickCount = expanded ? math.min(4, maxValue) : 3;
    for (var i = 0; i <= tickCount; i++) {
      final value = maxValue * i / tickCount;
      final y = bottom - (bottom - top) * i / tickCount;
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
      if (expanded) {
        final label = TextPainter(
            text: TextSpan(
                text: value.round().toString(),
                style: TextStyle(
                    fontSize: 10,
                    color: dark
                        ? const Color(0xFF9A9CAB)
                        : const Color(0xFF85879A))),
            textDirection: TextDirection.ltr)
          ..layout();
        label.paint(
            canvas, Offset(left - label.width - 7, y - label.height / 2));
      }
    }
    _drawLine(canvas, left, top, right, bottom, maxValue, created,
        const Color(0xFF8275E8));
    _drawLine(canvas, left, top, right, bottom, maxValue, completed,
        const Color(0xFF49A58E));
  }

  void _drawLine(Canvas canvas, double left, double top, double right,
      double bottom, int maxValue, List<int> values, Color color) {
    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final point = Offset(left + (right - left) * i / (values.length - 1),
          bottom - values[i] / maxValue * (bottom - top));
      points.add(point);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        final previous = points[i - 1];
        final mid = (previous.dx + point.dx) / 2;
        path.cubicTo(mid, previous.dy, mid, point.dy, point.dx, point.dy);
      }
    }
    if (expanded && points.isNotEmpty) {
      final area = Path.from(path)
        ..lineTo(points.last.dx, bottom)
        ..lineTo(points.first.dx, bottom)
        ..close();
      final tint = Color.fromARGB(24, (color.r * 255).round(),
          (color.g * 255).round(), (color.b * 255).round());
      canvas.drawPath(area, Paint()..color = tint);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.created != created ||
      oldDelegate.completed != completed ||
      oldDelegate.dark != dark ||
      oldDelegate.expanded != expanded;
}

class _TaskDistribution extends StatelessWidget {
  const _TaskDistribution({required this.tasks, this.expanded = false});
  final List<Task> tasks;
  final bool expanded;
  static const colors = [
    Color(0xFF8275E8),
    Color(0xFF5087C6),
    Color(0xFFE8A740),
    Color(0xFF49A58E)
  ];
  @override
  Widget build(BuildContext context) {
    final counts = taskStatuses
        .map((status) => tasks.where((t) => t.status == status).length)
        .toList();
    return Row(children: [
      SizedBox(
          width: expanded ? 220 : 100,
          height: expanded ? 220 : 100,
          child: CustomPaint(
              painter: _DonutPainter(counts,
                  strokeWidth: expanded ? 22 : 12,
                  dark: Theme.of(context).brightness == Brightness.dark))),
      SizedBox(width: expanded ? 18 : 14),
      Expanded(
          child: Column(
              children: List.generate(taskStatuses.length, (index) {
        final label =
            const ['To do', 'In progress', 'Review', 'Completed'][index];
        return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Icon(Icons.circle, color: colors[index], size: 6),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 9, color: kMuted))),
              Text('${counts[index]}',
                  style:
                      const TextStyle(fontSize: 9, fontWeight: FontWeight.w600))
            ]));
      })))
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.counts,
      {required this.strokeWidth, required this.dark});
  final List<int> counts;
  final double strokeWidth;
  final bool dark;
  static const colors = _TaskDistribution.colors;
  @override
  void paint(Canvas canvas, Size size) {
    final total = counts.fold<int>(0, (sum, value) => sum + value);
    final inset = strokeWidth / 2 + 1;
    final rect = Rect.fromLTWH(
        inset, inset, size.width - inset * 2, size.height - inset * 2);
    var start = -math.pi / 2;
    for (var i = 0; i < counts.length; i++) {
      final sweep = total == 0
          ? math.pi * 2 / counts.length
          : math.pi * 2 * counts[i] / total;
      canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..color = colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth);
      start += sweep;
    }
    final text = TextPainter(
        text: TextSpan(
            text: '$total',
            style: TextStyle(
                fontSize: strokeWidth > 12 ? 28 : 18,
                fontWeight: FontWeight.w700,
                color: dark ? const Color(0xFFEEF0F8) : kInk)),
        textDirection: TextDirection.ltr)
      ..layout();
    text.paint(
        canvas,
        Offset((size.width - text.width) / 2,
            size.height / 2 - text.height / 2 - 3));
    final label = TextPainter(
        text: TextSpan(
            text: 'tasks',
            style:
                TextStyle(fontSize: strokeWidth > 12 ? 10 : 7, color: kMuted)),
        textDirection: TextDirection.ltr)
      ..layout();
    label.paint(
        canvas, Offset((size.width - label.width) / 2, size.height / 2 + 10));
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.counts != counts ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dark != dark;
}

class _PriorityList extends StatelessWidget {
  const _PriorityList({required this.tasks, required this.state});
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Text('Nothing needs your attention.',
          style: TextStyle(fontSize: 10, color: kMuted));
    }
    return Column(
        children: tasks
            .take(4)
            .map((task) => InkWell(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChangeNotifierProvider.value(
                              value: state,
                              child: TaskDetailScreen(taskId: task.id)))),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Icon(
                            task.isOverdue
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            size: 14,
                            color: task.isOverdue ? kDanger : kViolet),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text(
                                  '${task.priority.toLowerCase()} priority \u00b7 ${task.status.toLowerCase()}',
                                  style: const TextStyle(
                                      fontSize: 8, color: kMuted)),
                            ])),
                        if (task.isOverdue)
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFFFEEF0),
                                  borderRadius: BorderRadius.circular(5)),
                              child: const Text('Overdue',
                                  style:
                                      TextStyle(fontSize: 8, color: kDanger))),
                      ])),
                ))
            .toList());
  }
}

String _onTimeLabel(List<Task> tasks) {
  final completed = tasks
      .where((task) =>
          task.status == 'DONE' &&
          task.completedAt != null &&
          task.dueDate != null)
      .toList();
  if (completed.isEmpty) return 'On time unavailable';
  final onTime = completed
      .where((task) =>
          task.completedAt!.length >= 10 &&
          task.dueDate!.length >= 10 &&
          task.completedAt!
                  .substring(0, 10)
                  .compareTo(task.dueDate!.substring(0, 10)) <=
              0)
      .length;
  return 'On time ${(onTime * 100 / completed.length).round()}%';
}

class _HealthDetails extends StatelessWidget {
  const _HealthDetails(
      {required this.project,
      required this.progress,
      required this.done,
      required this.total,
      required this.memberCount,
      required this.tasks,
      required this.showTeamData});
  final Project project;
  final double progress;
  final int done, total, memberCount;
  final List<Task> tasks;
  final bool showTeamData;
  int get overdueCount => tasks.where((task) => task.isOverdue).length;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${(progress * 100).round()}%',
              style: GoogleFonts.dmSans(
                  fontSize: 22, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(width: 7),
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('$done of $total tasks complete',
                  style: const TextStyle(fontSize: 9, color: kMuted)))
        ]),
        const SizedBox(height: 6),
        ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: const Color(0xFFE6E6ED),
                valueColor: const AlwaysStoppedAnimation(kViolet))),
        const SizedBox(height: 8),
        if (showTeamData)
          Row(children: [
            const Icon(Icons.calendar_month_outlined, size: 11, color: kViolet),
            const SizedBox(width: 4),
            Expanded(
                child: Text(
                    project.dueDate == null
                        ? 'No deadline'
                        : 'Deadline ${dateLabel(project.dueDate)}',
                    style: const TextStyle(fontSize: 8, color: kMuted))),
            const Icon(Icons.people_outline, size: 11, color: kViolet),
            const SizedBox(width: 3),
            Text('$memberCount members',
                style: const TextStyle(fontSize: 8, color: kMuted)),
            const SizedBox(width: 6),
            const Icon(Icons.radio_button_checked, size: 10, color: kViolet),
            const SizedBox(width: 3),
            Text(_onTimeLabel(tasks),
                style: const TextStyle(fontSize: 8, color: kMuted)),
          ])
        else
          Text('Overdue $overdueCount',
              style: const TextStyle(fontSize: 9, color: kMuted)),
      ]);
}

Future<void> _showCreateProjectDialog(
    BuildContext context, AppState state) async {
  final orgId = state.selectedOrg?.id;
  if (orgId == null) return;
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  DateTime? startDate;
  DateTime? dueDate;
  var status = 'PLANNING';
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Create project'),
        content: SizedBox(
          width: 480,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .68),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Project name',
                        hintText: 'e.g. Website Redesign',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Project name is required.'
                              : null,
                    ),
                    TextFormField(
                      controller: descriptionController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'What is this project about?',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _DatePickerField(
                        label: 'Start date',
                        value: startDate,
                        onTap: () async {
                          final picked =
                              await _pickFormDate(dialogContext, startDate);
                          if (picked != null) {
                            setDialogState(() => startDate = picked);
                          }
                        },
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _DatePickerField(
                        label: 'Due date',
                        value: dueDate,
                        onTap: () async {
                          final picked =
                              await _pickFormDate(dialogContext, dueDate);
                          if (picked != null) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                      )),
                    ]),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: projectStatuses
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setDialogState(() => status = value);
                      },
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(error!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    if (startDate != null &&
                        dueDate != null &&
                        dueDate!.isBefore(startDate!)) {
                      setDialogState(() => error =
                          'Due date must be on or after the start date.');
                      return;
                    }
                    setDialogState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final created = await state.api.createProject(
                        orgId: orgId,
                        name: nameController.text.trim(),
                        description: descriptionController.text.trim(),
                        startDate: _formDateValue(startDate),
                        dueDate: _formDateValue(dueDate),
                        status: status,
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      await state.loadOrganizations();
                      final project = state.projects
                          .where((item) => item.id == created.id)
                          .firstOrNull;
                      if (project != null) await state.selectProject(project);
                    } on ApiException catch (exception) {
                      setDialogState(() {
                        error = exception.message;
                        busy = false;
                      });
                    }
                  },
            child: Text(busy ? 'Creating...' : 'Create project'),
          ),
        ],
      ),
    ),
  );
  nameController.dispose();
  descriptionController.dispose();
}

Future<void> _showCreateTaskDialog(BuildContext context, AppState state) async {
  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final aiPromptController = TextEditingController();
  DateTime? startDate;
  DateTime? dueDate;
  var status = 'TO DO';
  var priority = 'MEDIUM';
  var busy = false;
  var aiBusy = false;
  String? error;
  String? aiError;
  AiTaskSuggestion? suggestion;
  final selectedAssignees = <String>{};
  final projectId = state.selectedProject?.id;
  if (projectId == null) {
    titleController.dispose();
    descriptionController.dispose();
    aiPromptController.dispose();
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Create task'),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: (MediaQuery.sizeOf(dialogContext).height -
                        MediaQuery.viewInsetsOf(dialogContext).bottom) *
                    .72),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(state.selectedProject!.name,
                        style: const TextStyle(fontSize: 12, color: kMuted)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(dialogContext).brightness ==
                                Brightness.dark
                            ? const Color(0xFF282638)
                            : const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE8E4FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Draft with AI',
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: aiPromptController,
                            maxLength: 2000,
                            maxLines: 2,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Describe the work you need to plan...',
                              counterText: '',
                              alignLabelWithHint: true,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: aiBusy ||
                                      aiPromptController.text.trim().length < 3
                                  ? null
                                  : () async {
                                      setDialogState(() {
                                        aiBusy = true;
                                        aiError = null;
                                      });
                                      try {
                                        final draft =
                                            await state.api.suggestTask(
                                          projectId: projectId,
                                          prompt:
                                              aiPromptController.text.trim(),
                                        );
                                        if (!dialogContext.mounted) return;
                                        setDialogState(() {
                                          suggestion = draft;
                                          aiBusy = false;
                                        });
                                      } on ApiException catch (exception) {
                                        if (!dialogContext.mounted) return;
                                        setDialogState(() {
                                          aiError = exception.message;
                                          aiBusy = false;
                                        });
                                      }
                                    },
                              icon: aiBusy
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.auto_awesome_outlined,
                                      size: 16),
                              label:
                                  Text(aiBusy ? 'Drafting...' : 'Draft task'),
                            ),
                          ),
                          if (aiError != null) ...[
                            const SizedBox(height: 8),
                            ErrorBanner(aiError!),
                          ],
                          if (suggestion != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(dialogContext).colorScheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFFE8E4FF)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(suggestion!.title,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  if (suggestion!.description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(suggestion!.description,
                                        style: const TextStyle(
                                            fontSize: 12, color: kMuted)),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    suggestion!.subtasks.isEmpty
                                        ? '${suggestion!.priority} priority'
                                        : '${suggestion!.priority} priority | Suggested follow-ups: ${suggestion!.subtasks.join(', ')}',
                                    style: const TextStyle(
                                        fontSize: 11, color: kMuted),
                                  ),
                                  TextButton(
                                    onPressed: () => setDialogState(() {
                                      titleController.text = suggestion!.title;
                                      descriptionController.text =
                                          suggestion!.description;
                                      priority = suggestion!.priority;
                                    }),
                                    child: const Text('Use draft'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleController,
                      autofocus: true,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: 'Task title',
                        hintText: 'What needs to be done?',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Task title is required.'
                              : null,
                    ),
                    TextFormField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: taskStatuses
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text(value)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => status = value);
                          }
                        },
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: DropdownButtonFormField<String>(
                        initialValue: priority,
                        decoration:
                            const InputDecoration(labelText: 'Priority'),
                        items: taskPriorities
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text(value)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => priority = value);
                          }
                        },
                      )),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _DatePickerField(
                        label: 'Start date',
                        value: startDate,
                        onTap: () async {
                          final picked =
                              await _pickFormDate(dialogContext, startDate);
                          if (picked != null) {
                            setDialogState(() => startDate = picked);
                          }
                        },
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _DatePickerField(
                        label: 'Due date',
                        value: dueDate,
                        onTap: () async {
                          final picked =
                              await _pickFormDate(dialogContext, dueDate);
                          if (picked != null) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                      )),
                    ]),
                    const SizedBox(height: 14),
                    Text('Assignees',
                        style: Theme.of(dialogContext).textTheme.titleSmall),
                    if (state.projectMembers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No project members available.',
                            style: TextStyle(color: kMuted, fontSize: 12)),
                      )
                    else
                      ...state.projectMembers.map((member) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(member.fullName,
                                style: const TextStyle(fontSize: 13)),
                            value: selectedAssignees.contains(member.userId),
                            onChanged: (selected) => setDialogState(() {
                              if (selected == true) {
                                selectedAssignees.add(member.userId);
                              } else {
                                selectedAssignees.remove(member.userId);
                              }
                            }),
                          )),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(error!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    if (startDate != null &&
                        dueDate != null &&
                        dueDate!.isBefore(startDate!)) {
                      setDialogState(() => error =
                          'Due date must be on or after the start date.');
                      return;
                    }
                    setDialogState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await state.api.createTask(
                        projectId: projectId,
                        title: titleController.text.trim(),
                        description: descriptionController.text.trim(),
                        status: status,
                        priority: priority,
                        startDate: _formDateValue(startDate),
                        dueDate: _formDateValue(dueDate),
                        assigneeIds: selectedAssignees.toList(),
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      await state.refreshTasks();
                    } on ApiException catch (exception) {
                      setDialogState(() {
                        error = exception.message;
                        busy = false;
                      });
                    }
                  },
            child: Text(busy ? 'Creating...' : 'Create task'),
          ),
        ],
      ),
    ),
  );
  titleController.dispose();
  descriptionController.dispose();
  aiPromptController.dispose();
}

Future<DateTime?> _pickFormDate(BuildContext context, DateTime? current) {
  final today = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: current ?? today,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
}

String? _formDateValue(DateTime? value) {
  if (value == null) return null;
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_month_outlined, size: 18),
          ),
          child: Text(
            value == null ? 'Select date' : dateLabel(_formDateValue(value)),
            style: TextStyle(
              color: value == null ? kMuted : null,
              fontSize: 14,
            ),
          ),
        ),
      );
}

Future<void> _showCreateOrgDialog(BuildContext context, AppState state) async {
  final nameCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool busy = false;
  String? error;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Create organization'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null)
              ErrorBanner(error!, onDismiss: () => set(() => error = null)),
            const SizedBox(height: 4),
            TextFormField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Organization name'),
              autofocus: true,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required.' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    set(() => busy = true);
                    try {
                      await state.api
                          .createOrganization(name: nameCtrl.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx);
                      await state.loadOrganizations();
                    } on ApiException catch (e) {
                      set(() {
                        error = e.message;
                        busy = false;
                      });
                    }
                  },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
  nameCtrl.dispose();
}
