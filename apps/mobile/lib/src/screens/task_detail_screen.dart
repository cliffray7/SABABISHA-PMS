import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

/// Matches the web task detail modal:
/// - Title at top with status/priority badge row
/// - Details tab: status dropdown, priority, dates, assignees, description
/// - Comments tab: comment feed + input bar
/// - Subtasks tab: checklist + add bar
/// - Attachments in Details (upload + download)
/// - Edit button opens TaskFormScreen
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen(
      {super.key, required this.taskId, required this.state});
  final String taskId;
  final AppState state;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Task? _task;
  List<Comment> _comments = [];
  List<Subtask> _subtasks = [];
  List<Attachment> _attachments = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _task = widget.state.tasks
        .where((t) => t.id == widget.taskId)
        .firstOrNull;
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final api = widget.state.api;
      final id = widget.taskId;
      final results = await Future.wait([
        api.comments(id),
        api.subtasks(id),
        api.attachments(id),
      ]);
      if (mounted) {
        setState(() {
          _comments = results[0] as List<Comment>;
          _subtasks = results[1] as List<Subtask>;
          _attachments = results[2] as List<Attachment>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final c = await widget.state.api
          .addComment(taskId: widget.taskId, content: text);
      _commentCtrl.clear();
      setState(() => _comments.insert(0, c));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSubtask(String title) async {
    setState(() => _busy = true);
    try {
      final s = await widget.state.api
          .createSubtask(taskId: widget.taskId, title: title);
      setState(() => _subtasks.add(s));
      await widget.state.refreshTasks();
      if (mounted) {
        setState(() {
          _task = widget.state.tasks
              .where((t) => t.id == widget.taskId)
              .firstOrNull;
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSubtask(Subtask s) async {
    final done = !s.isDone;
    setState(() {
      _subtasks = [
        for (final x in _subtasks)
          if (x.id == s.id)
            Subtask(
                id: x.id,
                title: x.title,
                status: done ? 'DONE' : 'TO DO',
                createdAt: x.createdAt)
          else
            x
      ];
    });
    try {
      await widget.state.api.updateSubtask(
          taskId: widget.taskId, subtaskId: s.id, done: done);
    } on ApiException {
      await _loadAll();
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.first;
    if (pf.path == null) return;
    setState(() => _busy = true);
    try {
      final att = await widget.state.api.uploadAttachment(
          taskId: widget.taskId,
          file: File(pf.path!),
          fileName: pf.name);
      setState(() => _attachments.add(att));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openEdit() {
    if (_task == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: widget.state,
          child: TaskFormScreen(
            task: _task,
            state: widget.state,
            onSaved: () async {
              await widget.state.refreshTasks();
              if (mounted) {
                setState(() {
                  _task = widget.state.tasks
                      .where((t) => t.id == widget.taskId)
                      .firstOrNull;
                });
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    if (task == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(kViolet)),
        ),
      );
    }

    final writable = widget.state.selectedProject?.canWrite ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? kPageDark : kPage,
      appBar: AppBar(
        title: Text(
          task.title,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.dmSans(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (writable)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: _openEdit,
              tooltip: 'Edit task',
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Comments'),
            Tab(text: 'Subtasks'),
          ],
        ),
      ),
      body: LoadingOverlay(
        loading: _loading,
        child: TabBarView(
          controller: _tabs,
          children: [
            // ── Details tab ───────────────────────────────────────────────
            _DetailsTab(
              task: task,
              subtasks: _subtasks,
              attachments: _attachments,
              writable: writable,
              busy: _busy,
              error: _error,
              state: widget.state,
              onErrorDismiss: () => setState(() => _error = null),
              onStatusChanged: (s) async {
                await widget.state.moveTask(task.id, s);
                if (mounted) {
                  setState(() {
                    _task = widget.state.tasks
                        .where((t) => t.id == task.id)
                        .firstOrNull;
                  });
                }
              },
              onUpload: _pickAndUpload,
            ),

            // ── Comments tab ──────────────────────────────────────────────
            Column(children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ErrorBanner(_error!,
                      onDismiss: () => setState(() => _error = null)),
                ),
              Expanded(
                child: _comments.isEmpty
                    ? const EmptyState(
                        icon: Icons.chat_bubble_outline,
                        title: 'No comments yet',
                        message: 'Be the first to add a comment.')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) =>
                            _CommentCard(comment: _comments[i]),
                      ),
              ),
              if (writable) _CommentInput(ctrl: _commentCtrl, busy: _busy, onSend: _addComment),
            ]),

            // ── Subtasks tab ──────────────────────────────────────────────
            Column(children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ErrorBanner(_error!,
                      onDismiss: () => setState(() => _error = null)),
                ),
              Expanded(
                child: _subtasks.isEmpty
                    ? const EmptyState(
                        icon: Icons.checklist_outlined,
                        title: 'No subtasks',
                        message:
                            'Break this task into smaller steps.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _subtasks.length,
                        itemBuilder: (_, i) => _SubtaskItem(
                          subtask: _subtasks[i],
                          onToggle: writable
                              ? () => _toggleSubtask(_subtasks[i])
                              : null,
                        ),
                      ),
              ),
              if (writable)
                _AddSubtaskBar(
                    busy: _busy, onAdd: (title) => _addSubtask(title)),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─── Details tab ─────────────────────────────────────────────────────────────

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.task,
    required this.subtasks,
    required this.attachments,
    required this.writable,
    required this.busy,
    required this.error,
    required this.state,
    required this.onErrorDismiss,
    required this.onStatusChanged,
    required this.onUpload,
  });

  final Task task;
  final List<Subtask> subtasks;
  final List<Attachment> attachments;
  final bool writable;
  final bool busy;
  final String? error;
  final AppState state;
  final VoidCallback onErrorDismiss;
  final Future<void> Function(String) onStatusChanged;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final members = state.projectMembers;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark ? kPanelDark : kPanel;
    final panelBorder =
        isDark ? const Color(0xFF343845) : kLine;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (error != null) ErrorBanner(error!, onDismiss: onErrorDismiss),

      // ── Title + badges ──────────────────────────────────────────────────
      // Web: .detail-tags row below the h1
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: panelBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Task title — web .task-detail h1
          Text(
            task.title,
            style: GoogleFonts.dmSans(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFEEF0F8) : kInk,
              letterSpacing: -0.3,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          // Badges row: status + priority + overdue
          Wrap(spacing: 8, runSpacing: 6, children: [
            StatusBadge(task.status),
            PriorityBadge(task.priority),
            if (task.isOverdue)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'OVERDUE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kDanger,
                  ),
                ),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      // ── Detail fields — web .task-detail dl ────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: panelBorder),
        ),
        child: Column(children: [
          // Status (interactive if writable)
          _DetailRow(
            label: 'Status',
            child: writable
                ? _StatusDropdown(
                    value: task.status, onChanged: onStatusChanged)
                : StatusBadge(task.status),
          ),
          const _Divider(),
          _DetailRow(
            label: 'Priority',
            child: PriorityBadge(task.priority),
          ),
          const _Divider(),
          _DetailRow(
            label: 'Start date',
            text: dateLabel(task.startDate),
          ),
          const _Divider(),
          _DetailRow(
            label: 'Due date',
            text: dateLabel(task.dueDate),
            danger: task.isOverdue,
          ),
          const _Divider(),
          _DetailRow(
            label: 'Assignees',
            child: task.assigneeIds.isEmpty
                ? const Text('Unassigned',
                    style: TextStyle(color: kMuted))
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: task.assigneeIds.map((id) {
                      final m = members
                          .where((x) => x.userId == id)
                          .firstOrNull;
                      return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AvatarChip(
                                initials: m?.initials ?? '?',
                                size: 22),
                            const SizedBox(width: 4),
                            Text(
                              m?.fullName ?? id,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ]);
                    }).toList(),
                  ),
          ),
          if (task.subtaskCount > 0) ...[
            const _Divider(),
            _DetailRow(
              label: 'Subtasks',
              text:
                  '${task.completedSubtaskCount}/${task.subtaskCount} completed',
            ),
          ],
        ]),
      ),

      // ── Description ───────────────────────────────────────────────────
      if (task.description != null && task.description!.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panelBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: panelBorder),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Description',
                style: GoogleFonts.dmSans(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              task.description!,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF6D6E7E), height: 1.5),
            ),
          ]),
        ),
      ],

      // ── Attachments section ───────────────────────────────────────────
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: panelBorder),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(
              'Attachments (${attachments.length})',
              style: GoogleFonts.dmSans(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (writable)
              GestureDetector(
                onTap: busy ? null : onUpload,
                child: const Icon(Icons.upload_file_outlined,
                    color: kViolet, size: 20),
              ),
          ]),
          const SizedBox(height: 10),
          if (attachments.isEmpty)
            const Text('No attachments.',
                style: TextStyle(fontSize: 13, color: kMuted))
          else
            ...attachments.map((a) => _AttachmentRow(
                  attachment: a,
                  api: state.api,
                )),
        ]),
      ),
      const SizedBox(height: 32),
    ]);
  }
}

// ─── Detail row ──────────────────────────────────────────────────────────────
// Web .task-detail dl: dt 150px, dd flex-1

class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.label, this.text, this.child, this.danger = false});
  final String label;
  final String? text;
  final Widget? child;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: kMuted),
          ),
        ),
        Expanded(
          child: child ??
              Text(
                text ?? '',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: danger ? kDanger : null,
                ),
              ),
        ),
      ]),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: kLine);
  }
}

// ─── Status dropdown ──────────────────────────────────────────────────────────

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown(
      {required this.value, required this.onChanged});
  final String value;
  final Future<void> Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox(),
      items: taskStatuses
          .map((s) => DropdownMenuItem(
                value: s,
                child: StatusBadge(s),
              ))
          .toList(),
      onChanged: (v) => v != null ? onChanged(v) : null,
    );
  }
}

// ─── Comment card ─────────────────────────────────────────────────────────────
// Web .comment: avatar + author bold + timestamp + content

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment});
  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final initials = comment.authorName.isNotEmpty
        ? comment.authorName
            .split(' ')
            .map((p) => p.isNotEmpty ? p[0] : '')
            .take(2)
            .join()
        : '?';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? kPanelDark : kPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF343845) : kLine,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AvatarChip(initials: initials, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              comment.authorName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            timeAgo(comment.createdAt),
            style: const TextStyle(fontSize: 11, color: kMuted),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          comment.content,
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF6D6E7E), height: 1.5),
        ),
      ]),
    );
  }
}

// ─── Comment input bar ────────────────────────────────────────────────────────

class _CommentInput extends StatelessWidget {
  const _CommentInput(
      {required this.ctrl, required this.busy, required this.onSend});
  final TextEditingController ctrl;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1C26)
            : const Color(0xFFF7F7FA),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF343845) : kLine,
          ),
        ),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: 'Add a comment…',
              isDense: true,
            ),
            maxLines: 3,
            minLines: 1,
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: busy ? null : onSend,
          style: FilledButton.styleFrom(
            backgroundColor: kViolet,
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
          ),
          child: const Icon(Icons.send, size: 18),
        ),
      ]),
    );
  }
}

// ─── Subtask item ─────────────────────────────────────────────────────────────
// Web .subtask-item: checkbox + title (strikethrough if done)

class _SubtaskItem extends StatelessWidget {
  const _SubtaskItem({required this.subtask, this.onToggle});
  final Subtask subtask;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF252834)
            : const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(children: [
        Checkbox(
          value: subtask.isDone,
          onChanged: onToggle != null ? (_) => onToggle!() : null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          activeColor: kViolet,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtask.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              decoration:
                  subtask.isDone ? TextDecoration.lineThrough : null,
              color: subtask.isDone ? kMuted : null,
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Add subtask bar ──────────────────────────────────────────────────────────

class _AddSubtaskBar extends StatefulWidget {
  const _AddSubtaskBar({required this.busy, required this.onAdd});
  final bool busy;
  final void Function(String) onAdd;

  @override
  State<_AddSubtaskBar> createState() => _AddSubtaskBarState();
}

class _AddSubtaskBarState extends State<_AddSubtaskBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.trim().isEmpty) return;
    widget.onAdd(_ctrl.text.trim());
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1C26)
            : const Color(0xFFF7F7FA),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF343845) : kLine,
          ),
        ),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              hintText: 'Add subtask…',
              isDense: true,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: kViolet,
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
          ),
          child: const Icon(Icons.add, size: 20),
        ),
      ]),
    );
  }
}

// ─── Attachment row ───────────────────────────────────────────────────────────
// Web .attachment: flex row with filename + size + download icon

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow(
      {required this.attachment, required this.api});
  final Attachment attachment;
  final ApiClient api;

  Future<void> _download(BuildContext context) async {
    try {
      final url = await api.attachmentDownloadUrl(attachment.id);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the file.')),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF252834)
            : const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF343845) : kLine,
        ),
      ),
      child: Row(children: [
        const Icon(Icons.attach_file_outlined, size: 18, color: kMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              attachment.fileName,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${(attachment.fileSize / 1024).toStringAsFixed(1)} KB · ${dateLabel(attachment.createdAt)}',
              style: const TextStyle(fontSize: 11, color: kMuted),
            ),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.download_outlined,
              size: 18, color: kViolet),
          onPressed: () => _download(context),
          tooltip: 'Download',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TaskFormScreen — Create / edit task
// Matches web TaskForm modal: title, description, status, priority, dates,
// assignee checkboxes, save button
// ═══════════════════════════════════════════════════════════════════════════════

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({
    super.key,
    this.task,
    required this.state,
    required this.onSaved,
  });
  final Task? task;
  final AppState state;
  final VoidCallback onSaved;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _status;
  late String _priority;
  DateTime? _startDate;
  DateTime? _dueDate;
  late List<String> _assigneeIds;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _description = TextEditingController(text: t?.description ?? '');
    _status = t?.status ?? 'TO DO';
    _priority = t?.priority ?? 'MEDIUM';
    _startDate =
        t?.startDate != null ? DateTime.tryParse(t!.startDate!) : null;
    _dueDate = t?.dueDate != null ? DateTime.tryParse(t!.dueDate!) : null;
    _assigneeIds = List.from(t?.assigneeIds ?? []);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.state.api;
      final projectId = widget.state.selectedProject!.id;
      if (widget.task == null) {
        await api.createTask(
          projectId: projectId,
          title: _title.text.trim(),
          description:
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          status: _status,
          priority: _priority,
          startDate: isoDateOnly(_startDate),
          dueDate: isoDateOnly(_dueDate),
          assigneeIds: _assigneeIds,
        );
      } else {
        await api.updateTask(
          taskId: widget.task!.id,
          title: _title.text.trim(),
          description:
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          status: _status,
          priority: _priority,
          startDate: isoDateOnly(_startDate),
          dueDate: isoDateOnly(_dueDate),
          assigneeIds: _assigneeIds,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.state.projectMembers;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.task == null ? 'New task' : 'Edit task',
          style: GoogleFonts.dmSans(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: kViolet,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
              ),
              child: Text(_busy ? 'Saving…' : 'Save',
                  style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null)
            ErrorBanner(_error!,
                onDismiss: () => setState(() => _error = null)),

          // Title
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Task title *'),
            autofocus: widget.task == null,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Title is required.' : null,
          ),
          const SizedBox(height: 12),

          // Description
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(
                labelText: 'Description (optional)'),
            maxLines: 4,
          ),
          const SizedBox(height: 16),

          // Status + Priority in a row
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: taskStatuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _status = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: taskPriorities
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => _priority = v!),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // Start date + Due date
          Row(children: [
            Expanded(
              child: _DateField(
                label: 'Start date',
                value: _startDate,
                onPicked: (d) => setState(() => _startDate = d),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateField(
                label: 'Due date',
                value: _dueDate,
                onPicked: (d) => setState(() => _dueDate = d),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Assignees
          const Text('Assignees',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kInk)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: kLine),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: members.map((m) {
                final checked = _assigneeIds.contains(m.userId);
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  activeColor: kViolet,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _assigneeIds.add(m.userId);
                    } else {
                      _assigneeIds.remove(m.userId);
                    }
                  }),
                  secondary: AvatarChip(initials: m.initials, size: 28),
                  title: Text(m.fullName,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(m.role,
                      style: const TextStyle(
                          fontSize: 11, color: kMuted)),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField(
      {required this.label, required this.value, required this.onPicked});
  final String label;
  final DateTime? value;
  final void Function(DateTime?) onPicked;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final d = await pickDate(context, initial: value);
        onPicked(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(4),
          color: kPanel,
        ),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: kMuted)),
              const SizedBox(height: 2),
              Text(
                dateLabel(isoDateOnly(value)),
                style: const TextStyle(fontSize: 13),
              ),
            ]),
          ),
          const Icon(Icons.calendar_today_outlined,
              size: 16, color: kMuted),
        ]),
      ),
    );
  }
}
