import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/api_client.dart';
import '../widgets/common.dart';
import 'edit_task_screen.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Future<Task> _taskFuture;

  @override
  void initState() {
    super.initState();
    _taskFuture = context.read<AppState>().getTask(widget.taskId);
  }

  void _reloadTask() {
    setState(() {
      _taskFuture = context.read<AppState>().getTask(widget.taskId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
      ),
      body: FutureBuilder<Task>(
        future: _taskFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorBanner(snapshot.error.toString()),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Task not found.'));
          }
          final task = snapshot.data!;
          return TaskDetailView(task: task, onTaskChanged: _reloadTask);
        },
      ),
    );
  }
}

class TaskDetailView extends StatelessWidget {
  const TaskDetailView({
    super.key,
    required this.task,
    required this.onTaskChanged,
  });

  final Task task;
  final VoidCallback onTaskChanged;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Hide the back button on this AppBar
        title: const Text('Task Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (context) => ChangeNotifierProvider.value(
                    value: appState,
                    child: EditTaskScreen(task: task),
                  ),
                ),
              );
              if (changed == true) onTaskChanged();
            },
          ),
          if (appState.selectedProject?.isManagerOrLead ?? false)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Move task to Trash?'),
                    content: const Text(
                        'This task will move to Trash and can be restored for 30 days.'),
                    actions: [
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        child: const Text('Move to Trash'),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                try {
                  await appState.deleteTask(task.id);
                  if (context.mounted) Navigator.of(context).pop();
                } on ApiException catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error.message)),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(children: [
          Text(
            task.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            task.description ?? 'No description provided.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Divider(height: 32),
          Row(
            children: [
              const Icon(Icons.label_outline, size: 20),
              const SizedBox(width: 8),
              Text('Status: ${task.status.replaceAll('_', ' ')}'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 20),
              const SizedBox(width: 8),
              Text('Priority: ${task.priority.toString().split('.').last}'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                  'Due: ${task.dueDate != null ? dateLabel(task.dueDate) : 'Not set'}'),
            ],
          ),
          const Divider(height: 32),
          _TaskAttachments(
            key: ValueKey(task.id),
            taskId: task.id,
            writable: appState.selectedProject?.canWrite ?? false,
          ),
        ]),
      ),
    );
  }
}

class _TaskAttachments extends StatefulWidget {
  const _TaskAttachments({
    super.key,
    required this.taskId,
    required this.writable,
  });

  final String taskId;
  final bool writable;

  @override
  State<_TaskAttachments> createState() => _TaskAttachmentsState();
}

class _TaskAttachmentsState extends State<_TaskAttachments> {
  List<Attachment> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items =
          await context.read<AppState>().api.attachments(widget.taskId);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error =
            'Could not open the file picker: ${error.message ?? 'unknown error'}');
      }
      return;
    }
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null) {
      setState(() => _error = 'The selected file could not be opened.');
      return;
    }
    if (picked.size <= 0 || picked.size > 10000000) {
      setState(() => _error = 'Choose a file between 1 byte and 10 MB.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<AppState>().api;
    try {
      await api.uploadAttachment(
        taskId: widget.taskId,
        file: File(path),
        fileName: picked.name,
      );
      if (!mounted) return;
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Attachment attachment) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Move attachment to Trash',
      message:
          'Move ${attachment.fileName} to Trash? It can be restored for 30 days.',
      confirmLabel: 'Move to Trash',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().api.deleteAttachment(attachment.id);
      if (!mounted) return;
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final canDelete = state.selectedProject?.isManagerOrLead ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text('Attachments',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          if (widget.writable)
            TextButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text(_busy ? 'Working…' : 'Attach file'),
            ),
        ]),
        if (_error != null) ErrorBanner(_error!),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No attachments yet.', style: TextStyle(color: kMuted)),
          )
        else
          ..._items.map((attachment) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(attachment.fileName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${(attachment.fileSize / 1024).ceil()} KB · ${dateLabel(attachment.createdAt)}'),
                trailing:
                    (attachment.uploadedBy == state.account?.id || canDelete)
                        ? IconButton(
                            tooltip: 'Move attachment to Trash',
                            onPressed: _busy ? null : () => _delete(attachment),
                            icon: const Icon(Icons.delete_outline),
                          )
                        : null,
              )),
      ],
    );
  }
}
