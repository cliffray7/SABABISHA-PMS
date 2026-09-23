import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

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
  late Task? _task;
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
      final taskId = widget.taskId;
      final results = await Future.wait([
        api.comments(taskId),
        api.subtasks(taskId),
        api.attachments(taskId),
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
      setState(() => _busy = false);
    }
  }

  Future<void> _addSubtask(String title) async {
    setState(() => _busy = true);
    try {
      final s = await widget.state.api
          .createSubtask(taskId: widget.taskId, title: title);
      setState(() => _subtasks.add(s));
      // Reload full task to update subtaskCount
      await widget.state.refreshTasks();
      setState(() {
        _task = widget.state.tasks
            .where((t) => t.id == widget.taskId)
            .firstOrNull;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _busy = false);
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
      // revert
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
      setState(() => _busy = false);
    }
  }

  void _openEditTask() {
    if (_task == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => TaskFormScreen(
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
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    if (task == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final members = widget.state.projectMembers;
    final writable = widget.state.selectedProject?.canWrite ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(task.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (writable)
            IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: _openEditTask),
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
            // ── Details tab ──────────────────────────────────────────────
            ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null)
                ErrorBanner(_error!, onDismiss: () => setState(() => _error = null)),
              _DetailRow('Status',
                  child: _StatusDropdown(
                    value: task.status,
                    enabled: writable,
                    onChanged: (s) async {
                      await widget.state.moveTask(task.id, s);
                      setState(() {
                        _task = widget.state.tasks
                            .where((t) => t.id == task.id)
                            .firstOrNull;
                      });
                    },
                  )),
              _DetailRow('Priority', child: PriorityBadge(task.priority)),
              _DetailRow('Start date',
                  text: dateLabel(task.startDate)),
              _DetailRow('Due date',
                  text: dateLabel(task.dueDate),
                  danger: task.isOverdue),
              _DetailRow('Assignees',
                  child: task.assigneeIds.isEmpty
                      ? const Text('Unassigned')
                      : Wrap(
                          spacing: 4,
                          children: task.assigneeIds.map((id) {
                            final m = members
                                .where((x) => x.userId == id)
                                .firstOrNull;
                            return Chip(
                              avatar: AvatarChip(
                                  initials: m?.initials ?? '?',
                                  size: 22),
                              label: Text(m?.fullName ?? id,
                                  style: const TextStyle(fontSize: 12)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        )),
              if (task.subtaskCount > 0)
                _DetailRow('Subtasks',
                    text:
                        '${task.completedSubtaskCount}/${task.subtaskCount} completed'),
              if (task.description != null && task.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Description',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(task.description!),
              ],

              // Attachments section
              const SizedBox(height: 20),
              SectionHeader(
                'Attachments (${_attachments.length})',
                trailing: writable
                    ? IconButton(
                        icon: const Icon(Icons.upload_file_outlined),
                        onPressed: _busy ? null : _pickAndUpload,
                        tooltip: 'Upload file',
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              ..._attachments.map((a) => _AttachmentTile(
                  attachment: a, taskId: task.id, api: widget.state.api)),
              if (_attachments.isEmpty)
                Text('No attachments.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline)),
            ]),

            // ── Comments tab ─────────────────────────────────────────────
            Column(children: [
              Expanded(
                child: _comments.isEmpty
                    ? const EmptyState(
                        icon: Icons.chat_bubble_outline,
                        title: 'No comments yet',
                        message: 'Be the first to comment.')
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) =>
                            _CommentTile(comment: _comments[i]),
                      ),
              ),
              if (writable)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border(
                        top: BorderSide(
                            color:
                                Theme.of(context).colorScheme.outlineVariant)),
                  ),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                      controller: _commentCtrl,
                      decoration: const InputDecoration(
                          hintText: 'Add a comment…',
                          isDense: true),
                      maxLines: 3,
                      minLines: 1,
                    )),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed: _busy ? null : _addComment,
                        icon: const Icon(Icons.send)),
                  ]),
                ),
            ]),

            // ── Subtasks tab ─────────────────────────────────────────────
            Column(children: [
              Expanded(
                child: _subtasks.isEmpty
                    ? EmptyState(
                        icon: Icons.checklist_outlined,
                        title: 'No subtasks',
                        message: 'Break this task into smaller steps.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _subtasks.length,
                        itemBuilder: (_, i) => _SubtaskTile(
                          subtask: _subtasks[i],
                          onToggle: writable
                              ? () => _toggleSubtask(_subtasks[i])
                              : null,
                        ),
                      ),
              ),
              if (writable)
                _AddSubtaskBar(
                    busy: _busy,
                    onAdd: (title) => _addSubtask(title)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, {this.text, this.child, this.danger = false});
  final String label;
  final String? text;
  final Widget? child;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 13)),
        ),
        Expanded(
          child: child ??
              Text(text ?? '',
                  style: TextStyle(
                      color: danger
                          ? Theme.of(context).colorScheme.error
                          : null)),
        ),
      ]),
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown(
      {required this.value, required this.onChanged, this.enabled = true});
  final String value;
  final Future<void> Function(String) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox(),
      items: taskStatuses
          .map((s) => DropdownMenuItem(value: s, child: StatusBadge(s)))
          .toList(),
      onChanged: enabled ? (v) => v != null ? onChanged(v) : null : null,
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final Comment comment;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AvatarChip(
                initials: comment.authorName.isNotEmpty
                    ? comment.authorName
                        .split(' ')
                        .map((p) => p.isNotEmpty ? p[0] : '')
                        .take(2)
                        .join()
                    : '?',
                size: 28),
            const SizedBox(width: 8),
            Expanded(
                child: Text(comment.authorName,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(timeAgo(comment.createdAt),
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline)),
          ]),
          const SizedBox(height: 8),
          Text(comment.content),
        ]),
      ),
    );
  }
}

class _SubtaskTile extends StatelessWidget {
  const _SubtaskTile({required this.subtask, this.onToggle});
  final Subtask subtask;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Checkbox(
          value: subtask.isDone,
          onChanged: onToggle != null ? (_) => onToggle!() : null,
        ),
        title: Text(
          subtask.title,
          style: TextStyle(
              decoration: subtask.isDone ? TextDecoration.lineThrough : null),
        ),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
            top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(children: [
        Expanded(
            child: TextField(
          controller: _ctrl,
          decoration:
              const InputDecoration(hintText: 'Add subtask…', isDense: true),
          onSubmitted: (v) {
            if (v.trim().isEmpty) return;
            widget.onAdd(v.trim());
            _ctrl.clear();
          },
        )),
        const SizedBox(width: 8),
        IconButton.filled(
            onPressed: widget.busy
                ? null
                : () {
                    if (_ctrl.text.trim().isEmpty) return;
                    widget.onAdd(_ctrl.text.trim());
                    _ctrl.clear();
                  },
            icon: const Icon(Icons.add)),
      ]),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile(
      {required this.attachment,
      required this.taskId,
      required this.api});
  final Attachment attachment;
  final String taskId;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.attach_file_outlined),
      title: Text(attachment.fileName,
          overflow: TextOverflow.ellipsis, maxLines: 1),
      subtitle: Text(
          '${(attachment.fileSize / 1024).toStringAsFixed(1)} KB · ${dateLabel(attachment.createdAt)}'),
      trailing: const Icon(Icons.download_outlined, size: 18),
    );
  }
}

// ─── Task form (create / edit) ───────────────────────────────────────────────

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
    _startDate = t?.startDate != null ? DateTime.tryParse(t!.startDate!) : null;
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
        title: Text(widget.task == null ? 'New task' : 'Edit task'),
        actions: [
          TextButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null)
            ErrorBanner(_error!, onDismiss: () => setState(() => _error = null)),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Task title *'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Title is required.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(
                labelText: 'Description (optional)'),
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          // Status
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: taskStatuses
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _status = v!),
          ),
          const SizedBox(height: 12),
          // Priority
          DropdownButtonFormField<String>(
            value: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: taskPriorities
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() => _priority = v!),
          ),
          const SizedBox(height: 12),
          // Start date
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start date'),
            subtitle: Text(dateLabel(isoDateOnly(_startDate))),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final d = await pickDate(context, initial: _startDate);
              if (d != null) setState(() => _startDate = d);
            },
          ),
          // Due date
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Due date'),
            subtitle: Text(dateLabel(isoDateOnly(_dueDate))),
            trailing: const Icon(Icons.event_outlined),
            onTap: () async {
              final d = await pickDate(context, initial: _dueDate);
              if (d != null) setState(() => _dueDate = d);
            },
          ),
          const SizedBox(height: 8),
          // Assignees
          const Text('Assignees',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...members.map((m) => CheckboxListTile(
                dense: true,
                value: _assigneeIds.contains(m.userId),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _assigneeIds.add(m.userId);
                  } else {
                    _assigneeIds.remove(m.userId);
                  }
                }),
                title: Text(m.fullName),
                subtitle: Text(m.role),
                secondary: AvatarChip(initials: m.initials),
              )),
        ]),
      ),
    );
  }
}
