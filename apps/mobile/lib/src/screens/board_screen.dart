import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'task_detail_screen.dart';

enum _BoardView { board, list, timeline }

/// Matches the web Board screen:
/// - Board/List/Timeline tab strip (web .view-tabs)
/// - Search bar + priority dropdown filter bar (.filter-bar)
/// - Board: horizontal kanban columns with column headers + task cards (.board)
/// - List: vertical task card list (.list-panel)
/// - Timeline: date-keyed task list (.timeline-entry)
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with SingleTickerProviderStateMixin {
  _BoardView _view = _BoardView.board;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _priorityFilter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = state.selectedProject;
    final all = state.tasks;

    if (state.loadingTasks && all.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(kViolet)),
      );
    }

    if (project == null) {
      return const EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No project selected',
        message: 'Pick a project from the top bar to see tasks.',
      );
    }

    final filtered = all.where((t) {
      final matchText = _search.isEmpty ||
          t.title.toLowerCase().contains(_search.toLowerCase()) ||
          (t.description ?? '').toLowerCase().contains(_search.toLowerCase());
      final matchPriority =
          _priorityFilter.isEmpty || t.priority == _priorityFilter;
      return matchText && matchPriority;
    }).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(children: [
      // ── View tabs + filter bar ─────────────────────────────────────────
      // Web: .view-tabs border-bottom + .filter-bar
      Container(
        decoration: BoxDecoration(
          color: isDark ? kPanelDark : kPanel,
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF343845) : kLine,
            ),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── View tabs (Board / List / Timeline) ──────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(children: [
              ...[_BoardView.board, _BoardView.list, _BoardView.timeline]
                  .map((v) {
                final label = v == _BoardView.board
                    ? 'Board'
                    : v == _BoardView.list
                        ? 'List'
                        : 'Timeline';
                final selected = _view == v;
                return InkWell(
                  onTap: () => setState(() => _view = v),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
                    margin: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: selected
                            ? const BorderSide(color: kViolet, width: 2)
                            : BorderSide.none,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: selected ? kViolet : kMuted,
                      ),
                    ),
                  ),
                );
              }),
              const Spacer(),
              Text(
                '${filtered.length} tasks',
                style: const TextStyle(fontSize: 12, color: kMuted),
              ),
            ]),
          ),

          // ── Filter bar (search + priority) ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              // Search
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search tasks…',
                      hintStyle:
                          TextStyle(fontSize: 13, color: kMuted),
                      prefixIcon: Icon(Icons.search,
                          size: 18, color: kMuted),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 0),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Priority filter
              DropdownButton<String>(
                value: _priorityFilter.isEmpty ? null : _priorityFilter,
                hint: const Text('Priority',
                    style: TextStyle(fontSize: 13, color: kMuted)),
                underline: const SizedBox(),
                isDense: true,
                style: const TextStyle(fontSize: 13, color: kInk),
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('All priorities')),
                  ...taskPriorities.map((p) =>
                      DropdownMenuItem(value: p, child: Text(p))),
                ],
                onChanged: (v) =>
                    setState(() => _priorityFilter = v ?? ''),
              ),
              if (_search.isNotEmpty || _priorityFilter.isNotEmpty)
                TextButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _search = '';
                      _priorityFilter = '';
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear',
                      style: TextStyle(fontSize: 12)),
                ),
            ]),
          ),
        ]),
      ),

      // ── Content ───────────────────────────────────────────────────────
      Expanded(
        child: RefreshIndicator(
          color: kViolet,
          onRefresh: () => state.refreshTasks(),
          child: _buildView(context, state, filtered),
        ),
      ),
    ]);
  }

  Widget _buildView(
      BuildContext context, AppState state, List<Task> tasks) {
    switch (_view) {
      case _BoardView.board:
        return _BoardColumns(tasks: tasks, state: state);
      case _BoardView.list:
        return _TaskList(tasks: tasks, state: state);
      case _BoardView.timeline:
        return _TimelineList(tasks: tasks, state: state);
    }
  }
}

// ─── Board (Kanban columns) ───────────────────────────────────────────────────
// Web .board: 4 columns, .column: #F1F1F6 bg, radius 14px, .column-title h2

class _BoardColumns extends StatelessWidget {
  const _BoardColumns({required this.tasks, required this.state});
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty && state.tasks.isEmpty) {
      return const EmptyState(
        icon: Icons.view_kanban_outlined,
        title: 'No tasks yet',
        message: 'Add your first task with the New task button.',
      );
    }

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      children: taskStatuses.map((status) {
        final cols = tasks.where((t) => t.status == status).toList();
        final isDark =
            Theme.of(context).brightness == Brightness.dark;
        final colBg = isDark
            ? const Color(0xFF1A1C26)
            : const Color(0xFFF1F1F6);
        return Container(
          width: 250,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            // Column header — web .column-title
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
              child: Row(children: [
                Text(
                  status,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: const Color(0xFF6D6E7E),
                  ),
                ),
                const Spacer(),
                Text(
                  '${cols.length}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9697A3)),
                ),
              ]),
            ),
            // Task cards
            Expanded(
              child: cols.isEmpty
                  ? Center(
                      child: Text(
                        'No tasks',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF6B7080)
                                : const Color(0xFF9697A3)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: cols.length,
                      itemBuilder: (ctx, i) => _TaskCard(
                          task: cols[i],
                          state: state,
                          showStatus: false),
                    ),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ─── List view ────────────────────────────────────────────────────────────────
// Web .list-panel: vertical card list with status tag on right

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks, required this.state});
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const EmptyState(
        icon: Icons.task_alt,
        title: 'No tasks match this filter',
      );
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
// Web .timeline-entry: date label (160px) + task card; ordered by dueDate

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.tasks, required this.state});
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final sorted = [...tasks]
      ..sort((a, b) =>
          (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999'));

    if (sorted.isEmpty) {
      return const EmptyState(
        icon: Icons.timeline,
        title: 'No tasks scheduled yet',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: sorted.length,
      itemBuilder: (ctx, i) {
        final t = sorted[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Date column — web .timeline-entry > div (left border violet)
            SizedBox(
              width: 88,
              child: Container(
                margin: const EdgeInsets.only(top: 14, right: 8),
                padding: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: kViolet, width: 3),
                  ),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    dateLabel(t.dueDate),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: t.isOverdue ? kDanger : kMuted,
                    ),
                  ),
                  if (t.startDate != null)
                    Text(
                      'Start: ${dateLabel(t.startDate)}',
                      style: const TextStyle(
                          fontSize: 10, color: kMuted),
                    ),
                ]),
              ),
            ),
            Expanded(
              child: _TaskCard(
                  task: t, state: state, showStatus: true),
            ),
          ]),
        );
      },
    );
  }
}

// ─── Task card ────────────────────────────────────────────────────────────────
// Web .task-card: white, 1px border #E1E1E6, radius 8px, 14px padding
// Priority pill top-left, title 14px bold, meta row, assignee chips

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.state,
    required this.showStatus,
  });
  final Task task;
  final AppState state;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final members = state.projectMembers;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: state,
            child: TaskDetailScreen(taskId: task.id, state: state),
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
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
                    color: Color(0x08252530),
                    blurRadius: 9,
                    offset: Offset(0, 3),
                  )
                ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // ── Top row: priority + status + overdue icon ───────────────
          Row(children: [
            PriorityBadge(task.priority),
            if (showStatus) ...[
              const SizedBox(width: 6),
              StatusBadge(task.status),
            ],
            const Spacer(),
            if (task.isOverdue)
              const Icon(Icons.warning_amber,
                  size: 14, color: kDanger),
          ]),
          const SizedBox(height: 10),

          // ── Title ─────────────────────────────────────────────────────
          Text(
            task.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          // ── Description snippet ──────────────────────────────────────
          if (task.description != null &&
              task.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              task.description!,
              style: const TextStyle(
                  fontSize: 12, color: kMuted, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // ── Subtask summary ──────────────────────────────────────────
          if (task.subtaskCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${task.completedSubtaskCount}/${task.subtaskCount} subtasks complete',
              style: const TextStyle(fontSize: 11, color: kMuted),
            ),
          ],

          // ── Meta row: assignees + due date ───────────────────────────
          // Web .task-meta + .assignee-chips
          const SizedBox(height: 10),
          Row(children: [
            // Assignee avatars
            if (task.assigneeIds.isEmpty)
              const Text('Unassigned',
                  style: TextStyle(fontSize: 11, color: kMuted))
            else
              ...task.assigneeIds.take(4).map((id) {
                final m = members
                    .where((x) => x.userId == id)
                    .firstOrNull;
                return Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: AvatarChip(
                      initials: m?.initials ?? '?', size: 22),
                );
              }),
            const Spacer(),
            // Due date
            if (task.dueDate != null)
              Row(children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 11,
                  color: task.isOverdue ? kDanger : kMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  task.status == 'DONE'
                      ? 'Completed'
                      : dateLabel(task.dueDate),
                  style: TextStyle(
                    fontSize: 11,
                    color: task.isOverdue ? kDanger : kMuted,
                  ),
                ),
              ]),
          ]),
        ]),
      ),
    );
  }
}
