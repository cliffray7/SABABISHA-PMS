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
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final account = state.account;
    final project = state.selectedProject;
    final tasks = state.tasks;
    final metrics = state.metrics;
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
            : 'Choose a project from the selector at the top.',
      );
    }

    // Compute metrics from local tasks when API metrics aren't ready
    final done = tasks.where((t) => t.status == 'DONE').length;
    final progress = tasks.isEmpty ? 0.0 : done / tasks.length;
    final mine = tasks.where((t) => t.assigneeIds.contains(userId)).toList();
    final mineOpen =
        metrics?.myTasks ?? mine.where((t) => t.status != 'DONE').length;
    final mineOverdue =
        metrics?.overdueTasks ?? mine.where((t) => t.isOverdue).length;
    final mineInProgress =
        metrics?.inProgressTasks ??
            mine.where((t) => t.status == 'IN PROGRESS').length;
    final isOverdueRed = mineOverdue > 0;

    return RefreshIndicator(
      color: kViolet,
      onRefresh: () => state.refreshTasks(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Metric grid ──────────────────────────────────────────────
          // Web: .metric-grid — 4 columns, gap 12px, metric card 24px padding
          _MetricGrid(
            items: [
              _MetricItem(
                label: 'Project tasks',
                value: '${tasks.length}',
              ),
              _MetricItem(
                label: 'My open tasks',
                value: '$mineOpen',
              ),
              _MetricItem(
                label: 'My overdue',
                value: '$mineOverdue',
                danger: isOverdueRed,
              ),
              _MetricItem(
                label: 'In progress',
                value: '$mineInProgress',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Progress panel ─────────────────────────────────────────────
          // Web: .progress-panel — project name + %, bar, subtitle text
          _ProgressPanel(
            project: project,
            progress: progress,
            done: done,
            total: tasks.length,
            memberCount: members.length,
          ),
          const SizedBox(height: 16),

          // ── Upcoming deadlines ──────────────────────────────────────────
          // Web: .list-panel with h2 "Upcoming deadlines"
          _ListPanel(
            title: 'Upcoming deadlines',
            child: _UpcomingDeadlines(tasks: tasks, state: state),
          ),
          const SizedBox(height: 16),

          // ── Team workload ───────────────────────────────────────────────
          // Web: .list-panel.workload — member name + open count + bar
          _ListPanel(
            title: 'Team workload',
            child: _TeamWorkload(members: members, tasks: tasks),
          ),
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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: items
          .map((item) => _MetricCard(item: item))
          .toList(),
    );
  }
}

class _MetricItem {
  const _MetricItem({
    required this.label,
    required this.value,
    this.danger = false,
  });
  final String label;
  final String value;
  final bool danger;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});
  final _MetricItem item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final numColor = item.danger ? kDanger : kViolet;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? kPanelDark : kPanel,
        borderRadius: BorderRadius.circular(8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 13,
              color: kMuted,
            ),
          ),
          const Spacer(),
          Text(
            item.value,
            style: GoogleFonts.dmSans(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: numColor,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Progress panel ───────────────────────────────────────────────────────────
// Web .progress-panel: name + %, progress bar, subtitle

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.project,
    required this.progress,
    required this.done,
    required this.total,
    required this.memberCount,
  });
  final Project project;
  final double progress;
  final int done;
  final int total;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pct = (progress * 100).round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? kPanelDark : kPanel,
        borderRadius: BorderRadius.circular(8),
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
        // heading row: project name + percentage
        Row(children: [
          Expanded(
            child: Text(
              project.name,
              style: GoogleFonts.dmSans(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFEEF0F8) : kInk,
              ),
            ),
          ),
          Text(
            '$pct%',
            style: GoogleFonts.dmSans(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: kViolet,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Progress bar — web .progress-track
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: isDark
                ? const Color(0xFF2A2D38)
                : const Color(0xFFE6E6ED),
            valueColor:
                const AlwaysStoppedAnimation(kViolet),
          ),
        ),
        const SizedBox(height: 10),
        // Subtitle
        Text(
          '$done of $total project tasks completed · $memberCount team members',
          style: const TextStyle(fontSize: 12, color: kMuted),
        ),
      ]),
    );
  }
}

// ─── List panel wrapper ────────────────────────────────────────────────────────
// Web .list-panel: white bg, 1px border, 20px padding, bold h2

class _ListPanel extends StatelessWidget {
  const _ListPanel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? kPanelDark : kPanel,
        borderRadius: BorderRadius.circular(8),
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
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFEEF0F8) : kInk,
          ),
        ),
        const SizedBox(height: 12),
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
        .take(6)
        .toList();

    if (upcoming.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('No upcoming deadlines.',
            style: TextStyle(color: kMuted, fontSize: 14)),
      );
    }

    return Column(
      children: upcoming.map((t) {
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
                  fontWeight:
                      overdue ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ]),
          ),
        );
      }).expand((w) sync* {
        yield const Divider(height: 1);
        yield w;
      }).skip(1).toList(),
    );
  }

  void _openTask(BuildContext context, Task t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: TaskDetailScreen(taskId: t.id, state: state),
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
            .where((t) =>
                t.status != 'DONE' && t.assigneeIds.contains(m.userId))
            .length;
        final frac = tasks.isEmpty ? 0.0 : open / tasks.length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  AvatarChip(initials: m.initials, size: 26),
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
                    valueColor:
                        const AlwaysStoppedAnimation(kViolet),
                  ),
                ),
              ]),
        );
      }).toList(),
    );
  }
}

// ─── Create org dialog ────────────────────────────────────────────────────────

Future<void> _showCreateOrgDialog(
    BuildContext context, AppState state) async {
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
              ErrorBanner(error!,
                  onDismiss: () => set(() => error = null)),
            const SizedBox(height: 4),
            TextFormField(
              controller: nameCtrl,
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
