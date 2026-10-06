import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

class EditTaskScreen extends StatefulWidget {
  const EditTaskScreen({super.key, required this.task});

  final Task task;

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _status;
  late String _priority;
  late DateTime? _startDate;
  late DateTime? _dueDate;
  late Set<String> _selectedAssignees;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController =
        TextEditingController(text: widget.task.description ?? '');
    _status = taskStatuses.contains(widget.task.status)
        ? widget.task.status
        : taskStatuses.first;
    _priority = taskPriorities.contains(widget.task.priority)
        ? widget.task.priority
        : taskPriorities[2];
    _startDate = DateTime.tryParse(widget.task.startDate ?? '');
    _dueDate = DateTime.tryParse(widget.task.dueDate ?? '');
    _selectedAssignees = widget.task.assigneeIds.toSet();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = context.watch<AppState>().projectMembers;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit task'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ErrorBanner(_error!),
            TextFormField(
              controller: _titleController,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Task title'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Task title is required.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: taskStatuses
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) setState(() => _status = value);
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: taskPriorities
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _priority = value);
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _dateField(
              context,
              label: 'Start date',
              value: _startDate,
              onPick: () => _pickDate(isStartDate: true),
              onClear: () => setState(() => _startDate = null),
            ),
            const SizedBox(height: 12),
            _dateField(
              context,
              label: 'Due date',
              value: _dueDate,
              onPick: () => _pickDate(isStartDate: false),
              onClear: () => setState(() => _dueDate = null),
            ),
            const SizedBox(height: 20),
            Text('Assignees', style: Theme.of(context).textTheme.titleMedium),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No project members available.',
                  style: TextStyle(color: kMuted),
                ),
              )
            else
              ...members.map(
                (member) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Row(children: [
                    AvatarChip(
                      initials: member.initials,
                      size: 28,
                      avatarUrl: member.avatarUrl,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(member.fullName)),
                  ]),
                  value: _selectedAssignees.contains(member.userId),
                  onChanged: _busy
                      ? null
                      : (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedAssignees.add(member.userId);
                            } else {
                              _selectedAssignees.remove(member.userId);
                            }
                          });
                        },
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving...' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final dateLabel = value == null
        ? 'Not set'
        : '${value.year.toString().padLeft(4, '0')}-'
            '${value.month.toString().padLeft(2, '0')}-'
            '${value.day.toString().padLeft(2, '0')}';
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Row(
        children: [
          Expanded(child: Text(dateLabel)),
          IconButton(
            tooltip: 'Choose $label',
            onPressed: _busy ? null : onPick,
            icon: const Icon(Icons.calendar_today_outlined),
          ),
          if (value != null)
            IconButton(
              tooltip: 'Clear $label',
              onPressed: _busy ? null : onClear,
              icon: const Icon(Icons.clear),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isStartDate}) async {
    final current = isStartDate ? _startDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStartDate) {
        _startDate = picked;
      } else {
        _dueDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate != null &&
        _dueDate != null &&
        _dueDate!.isBefore(_startDate!)) {
      setState(() => _error = 'Due date must be on or after the start date.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final task = widget.task;
    final updatedTask = Task(
      id: task.id,
      projectId: task.projectId,
      parentTaskId: task.parentTaskId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      status: _status,
      priority: _priority,
      startDate: _dateValue(_startDate),
      dueDate: _dateValue(_dueDate),
      createdAt: task.createdAt,
      completedAt: task.completedAt,
      assigneeIds: _selectedAssignees.toList(),
      subtaskCount: task.subtaskCount,
      completedSubtaskCount: task.completedSubtaskCount,
    );
    try {
      await context.read<AppState>().updateTask(updatedTask);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  String? _dateValue(DateTime? value) {
    if (value == null) return null;
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
