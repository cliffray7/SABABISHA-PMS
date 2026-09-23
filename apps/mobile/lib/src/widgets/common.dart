import 'package:flutter/material.dart';

// ─── Color helpers for statuses / priorities ────────────────────────────────

Color statusColor(String status, BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  switch (status) {
    case 'TO DO':
      return cs.outline;
    case 'IN PROGRESS':
      return Colors.blue;
    case 'REVIEW':
      return Colors.orange;
    case 'DONE':
      return Colors.green;
    default:
      return cs.outline;
  }
}

Color priorityColor(String priority) {
  switch (priority) {
    case 'URGENT':
      return Colors.red;
    case 'HIGH':
      return Colors.orange;
    case 'MEDIUM':
      return Colors.amber;
    case 'LOW':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

// ─── Avatar chip ─────────────────────────────────────────────────────────────

class AvatarChip extends StatelessWidget {
  const AvatarChip({super.key, required this.initials, this.size = 32});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.primaryContainer,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
            fontSize: size * 0.35,
            fontWeight: FontWeight.bold,
            color: cs.onPrimaryContainer),
      ),
    );
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(status,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

// ─── Priority badge ──────────────────────────────────────────────────────────

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(priority,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

// ─── Error banner ────────────────────────────────────────────────────────────

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onDismiss});
  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(color: cs.onErrorContainer))),
          if (onDismiss != null)
            IconButton(
                onPressed: onDismiss,
                icon: Icon(Icons.close, color: cs.onErrorContainer, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints()),
        ]),
      ),
    );
  }
}

// ─── Loading overlay ─────────────────────────────────────────────────────────

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, required this.loading, required this.child});
  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      if (loading)
        const Positioned.fill(
          child: ColoredBox(
            color: Colors.black26,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ]);
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String? message;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text(title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.outline),
                textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: 24),
            FilledButton(onPressed: action, child: Text(actionLabel ?? 'Action')),
          ],
        ]),
      ),
    );
  }
}

// ─── Confirmation dialog helper ──────────────────────────────────────────────

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            child: Text(confirmLabel)),
      ],
    ),
  );
  return result ?? false;
}

// ─── Date helpers ─────────────────────────────────────────────────────────────

String dateLabel(String? iso) {
  if (iso == null || iso.isEmpty) return 'No date';
  final d = DateTime.tryParse(iso);
  if (d == null) return 'No date';
  const months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String timeAgo(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return dateLabel(iso);
}

String? isoDateOnly(DateTime? dt) =>
    dt?.toIso8601String().substring(0, 10);

Future<DateTime?> pickDate(BuildContext context, {DateTime? initial}) {
  return showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2030),
  );
}

// ─── Role chip ────────────────────────────────────────────────────────────────

class RoleChip extends StatelessWidget {
  const RoleChip(this.role, {super.key});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(role,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

// ─── Section header ──────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}
