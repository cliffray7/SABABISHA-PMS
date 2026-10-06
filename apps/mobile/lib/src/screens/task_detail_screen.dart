import 'package:flutter/material.dart';
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
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Task?'),
                  content: const Text('This action cannot be undone.'),
                  actions: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    TextButton(
                      child: const Text('Delete'),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          ],
        ),
      ),
    );
  }
}
