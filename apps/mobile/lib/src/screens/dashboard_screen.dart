import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

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

    if (state.loadingOrgs || state.loadingProjects) {
      return const Center(child: CircularProgressIndicator());
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

    final done = tasks.where((t) => t.status == 'DONE').length;
    final progress = tasks.isEmpty ? 0.0 : done / tasks.length;
    final mine = tasks.where((t) => t.assigneeIds.contains(userId)).toList();
    final mineOpen = mine.where((t) => t.status != 'DONE').length;
    final mineOverdue = mine.where((t) => t.isOverdue).length;
    final mineInProgress =
        mine.where((t) => t.status == 'IN PROGRESS').length;

    return RefreshIndicator(
      onRefresh: () => state.refreshTasks(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.error != null) ...[
            ErrorBanner(state.error!, onDismiss: state.clearError),
            const SizedBox(height: 16),
          ],

          // Metric cards
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _MetricCard(
                  label: 'Project tasks',
                  value: '${tasks.length}',
                  icon: Icons.task_alt),
              _MetricCard(
                  label: 'My open tasks',
                  value: '${metrics?.myTasks ?? mineOpen}',
                  icon: Icons.assignment_outlined),
              _MetricCard(
                  label: 'My overdue',
                  value: '${metrics?.overdueTasks ?? mineOverdue}',
                  icon: Icons.warning_amber_outlined,
                  danger: (metrics?.overdueTasks ?? mineOverdue) > 0),
              _MetricCard(
                  label: 'In progress',
                  value: '${metrics?.inProgressTasks ?? mineInProgress}',
                  icon: Icons.pending_outlined),
            ],
          ),
          const SizedBox(height: 20),

          // Progress card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(project.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16))),
                  Text('${(progress * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                    '$done of ${tasks.length} tasks completed · ${members.length} team members',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Upcoming deadlines
          SectionHeader('Upcoming deadlines'),
          const SizedBox(height: 8),
          ...([...tasks]
                ..removeWhere((t) => t.status == 'DONE' || t.dueDate == null)
                ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? '')))
              .take(6)
              .map((t) => _DeadlineRow(task: t)),
          if (!tasks.any((t) => t.status != 'DONE' && t.dueDate != null))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No upcoming deadlines.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline)),
            ),

          const SizedBox(height: 20),

          // Team workload
          SectionHeader('Team workload'),
          const SizedBox(height: 8),
          ...members.map((m) {
            final count = tasks
                .where((t) =>
                    t.status != 'DONE' && t.assigneeIds.contains(m.userId))
                .length;
            final frac = tasks.isEmpty ? 0.0 : count / tasks.length;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      AvatarChip(initials: m.initials, size: 28),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m.fullName)),
                      Text('$count open',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 4,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    ),
                  ]),
            );
          }),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? cs.error : cs.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 22),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(task.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          dateLabel(task.dueDate),
          style: TextStyle(
              color: overdue
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.outline,
              fontSize: 12),
        ),
        leading: PriorityBadge(task.priority),
      ),
    );
  }
}

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
              Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            const SizedBox(height: 8),
            TextFormField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Organization name'),
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
                      await state.loadOrganizations();
                      if (ctx.mounted) Navigator.pop(ctx);
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
