import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'task_detail_screen.dart';

enum BoardView { board, list, timeline }

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  BoardView _view = BoardView.board;
  String _search = '';
  String _priorityFilter = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = state.selectedProject;
    final all = state.tasks;

    if (state.loadingTasks && all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (project == null) {
      return EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No project selected',
        message: 'Pick a project from the top bar to see tasks.',
      );
    }

    final filtered = all.where((t) {
      final matchText = _search.isEmpty ||
          t.title.toLowerCase().contains(_search.toLowerCase()) ||
          (t.description ?? '')
              .toLowerCase()
              .contains(_search.toLowerCase());
      final matchPriority =
          _priorityFilter.isEmpty || t.priority == _priorityFilter;
      return matchText && matchPriority;
    }).toList();

    return Column(children: [
      // Toolbar
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(children: [
          if (state.error != null)
            ErrorBanner(state.error!, onDismiss: state.clearError),
          Row(children: [
            // View toggle
            SegmentedButton<BoardView>(
              segments: const [
                ButtonSegment(
                    value: BoardView.board,
                    icon: Icon(Icons.view_kanban_outlined, size: 18)),
                ButtonSegment(
                    value: BoardView.list,
                    icon: Icon(Icons.list_alt_outlined, size: 18)),
                ButtonSegment(
                    value: BoardView.timeline,
                    icon: Icon(Icons.timeline_outlined, size: 18)),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact),
            ),
            const Spacer(),
            Text('${filtered.length} tasks',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search tasks…',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _priorityFilter.isEmpty ? null : _priorityFilter,
              hint: const Text('Priority'),
              underline: const SizedBox(),
              items: [
                const DropdownMenuItem(value: '', child: Text('All')),
                ...taskPriorities.map((p) =>
                    DropdownMenuItem(value: p, child: Text(p))),
              ],
              onChanged: (v) =>
                  setState(() => _priorityFilter = v ?? ''),
            ),
          ]),
        ]),
      ),

      // Content
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => state.refreshTasks(),
          child: _buildView(context, state, filtered),
        ),
      ),
    ]);
  }

  Widget _buildView(
      BuildContext context, AppState state, List<Task> tasks) {
    switch (_view) {
      case BoardView.board:
        return _BoardView(tasks: tasks, state: state);
      case BoardView.list:
        return _ListView(tasks: tasks, state: state);
      case BoardView.timeline:
        return _TimelineView(tasks: tasks, state: state);
    }
  }
}

// ─── Board (Kanban) view ──────────────────────────────────────────────────────

class _BoardView extends StatelessWidget {
  const _BoardView({required this.tasks, required this.state});
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      children: taskStatuses.map((status) {
        final cols = tasks.where((t) => t.status == status).toList();
        return Container(
          width: 260,
          margin: const EdgeInsets.only(right: 12),
          child: Column(children: [
            // Column header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: statusColor(status, context).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Expanded(
                    child: Text(status,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                StatusBadge(status),
                const SizedBox(width: 4),
                Text('${cols.length}',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: cols.isEmpty
                  ? Center(
                      child: Text('No tasks',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline)))
                  : ListView.builder(
                      itemCount: cols.length,
                      itemBuilder: (ctx, i) => _TaskCard(
                          task: cols[i], state: state, showStatus: false),
                    ),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ─── List view ────────────────────────────────────────────────────────────────

class _ListView extends StatelessWidget {
  const _ListView({required this.tasks, required this.state});
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const EmptyState(
          icon: Icons.task_alt, title: 'No tasks match this filter');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tasks.length,
      itemBuilder: (ctx, i) =>
          _TaskCard(task: tasks[i], state: state, showStatus: true),
    );
  }
}

// ─── Timeline view ────────────────────────────────────────────────────────────

class _TimelineView extends StatelessWidget {
  const _TimelineView({required this.tasks, required this.state});
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final sorted = [...tasks]
      ..sort((a, b) =>
          (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999'));

    if (sorted.isEmpty) {
      return const EmptyState(
          icon: Icons.timeline, title: 'No tasks scheduled yet');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (ctx, i) {
        final t = sorted[i];
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 80,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, right: 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(dateLabel(t.dueDate),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.isOverdue
                                ? Theme.of(ctx).colorScheme.error
                                : Theme.of(ctx).colorScheme.outline)),
                    if (t.startDate != null)
                      Text('Start: ${dateLabel(t.startDate)}',
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(ctx).colorScheme.outline)),
                  ]),
            ),
          ),
          Expanded(
              child: _TaskCard(task: t, state: state, showStatus: true)),
        ]);
      },
    );
  }
}

// ─── Task card ───────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  const _TaskCard(
      {required this.task, required this.state, required this.showStatus});
  final Task task;
  final AppState state;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final members = state.projectMembers;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TaskDetailScreen(
                    taskId: task.id,
                    state: state,
                  )),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  PriorityBadge(task.priority),
                  if (showStatus) ...[
                    const SizedBox(width: 6),
                    StatusBadge(task.status),
                  ],
                  const Spacer(),
                  if (task.isOverdue)
                    Icon(Icons.warning_amber,
                        size: 16,
                        color: Theme.of(context).colorScheme.error),
                ]),
                const SizedBox(height: 8),
                Text(task.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (task.description != null &&
                    task.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(task.description!,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  // Assignees
                  ...task.assigneeIds.take(3).map((id) {
                    final m = members
                        .where((x) => x.userId == id)
                        .firstOrNull;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child:
                          AvatarChip(initials: m?.initials ?? '?', size: 24),
                    );
                  }),
                  if (task.assigneeIds.isEmpty)
                    Text('Unassigned',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline)),
                  const Spacer(),
                  if (task.dueDate != null)
                    Row(children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 12,
                          color: task.isOverdue
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(dateLabel(task.dueDate),
                          style: TextStyle(
                              fontSize: 11,
                              color: task.isOverdue
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.outline)),
                    ]),
                  if (task.subtaskCount > 0) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_box_outlined,
                        size: 14,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 2),
                    Text(
                        '${task.completedSubtaskCount}/${task.subtaskCount}',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).colorScheme.outline)),
                  ],
                ]),
              ]),
        ),
      ),
    );
  }
}
