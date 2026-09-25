import 'package:flutter/material.dart';

// ─── Web design-system tokens ─────────────────────────────────────────────────
// --violet: #4D40ED   --ink: #1F212B   --muted: #737887
// --line:   #D9DBDE   --soft: #F0EFF9  --page: #F7F8FC
// --panel:  #FFFFFF   (dark: #1C1E28)

const kViolet       = Color(0xFF4D40ED);
const kVioletLight  = Color(0xFFEFEDFF); // nav active bg / avatar bg tint
const kVioletBg     = Color(0xFFDCD5FF); // avatar circle bg
const kInk          = Color(0xFF1F212B);
const kMuted        = Color(0xFF737887);
const kLine         = Color(0xFFD9DBDE);
const kPage         = Color(0xFFF7F8FC);
const kPanel        = Color(0xFFFFFFFF);
const kPanelDark    = Color(0xFF1C1E28);
const kSoftBg       = Color(0xFFF0EFF9);
const kPageDark     = Color(0xFF12131A);

// Priority colors — web .priority.urgent / .high / .medium / .low
const kUrgent  = Color(0xFFE13030);
const kHigh    = Color(0xFFE97C21);
const kMedium  = Color(0xFFC8A80D);
const kLow     = Color(0xFF42986E);
const kDanger  = Color(0xFFDA3038);
const kSuccess = Color(0xFF3F996B);

Color priorityColor(String priority) {
  switch (priority.toUpperCase()) {
    case 'URGENT': return kUrgent;
    case 'HIGH':   return kHigh;
    case 'MEDIUM': return kMedium;
    case 'LOW':    return kLow;
    default:       return kMuted;
  }
}

Color statusColor(String status, BuildContext context) {
  switch (status) {
    case 'TO DO':       return kMuted;
    case 'IN PROGRESS': return const Color(0xFF1E6DB5);
    case 'REVIEW':      return const Color(0xFFD07020);
    case 'DONE':        return kSuccess;
    default:            return kMuted;
  }
}

// ─── AvatarChip ──────────────────────────────────────────────────────────────
// Matches web .task-assignee and .avatar: #DCD5FF bg, #4D40ED text, circular

class AvatarChip extends StatelessWidget {
  const AvatarChip({super.key, required this.initials, this.size = 32});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fontSize = (size * 0.375).clamp(9.0, 14.0);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: kVioletBg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: kViolet,
          height: 1,
        ),
      ),
    );
  }
}

// ─── StatusBadge ─────────────────────────────────────────────────────────────
// Matches web .status-tag: violet bg (#EEEBFF), pill shape, bold 13px

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.small = false});
  final String status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status, context);
    final fs = small ? 10.0 : 11.0;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 7 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

// ─── PriorityBadge ───────────────────────────────────────────────────────────
// Matches web .priority pill: solid color bg, white text, 10px/11px, rounded-full

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key, this.small = false});
  final String priority;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    final fs = small ? 9.0 : 10.0;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─── SectionHeader ────────────────────────────────────────────────────────────
// Matches web .list-panel h2 / .panel-heading: 16-17px bold

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: kInk,
          ),
        ),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

// ─── ErrorBanner ─────────────────────────────────────────────────────────────
// Matches web .form-error: light red bg, border, dismissible

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onDismiss});
  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F1),
        border: Border.all(color: const Color(0xFFF4C7CC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline,
            color: Color(0xFFC93643), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFC93643),
            ),
          ),
        ),
        if (onDismiss != null)
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close,
                color: Color(0xFFC93643), size: 16),
          ),
      ]),
    );
  }
}

// ─── SuccessBanner ───────────────────────────────────────────────────────────
// Matches web .success-message

class SuccessBanner extends StatelessWidget {
  const SuccessBanner(this.message, {super.key, this.onDismiss});
  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF3),
        border: Border.all(color: const Color(0xFFB8DFC9)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_outline,
            color: kSuccess, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 13, color: kSuccess),
          ),
        ),
        if (onDismiss != null)
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: kSuccess, size: 16),
          ),
      ]),
    );
  }
}

// ─── EmptyState ───────────────────────────────────────────────────────────────
// Matches web .empty-state: dashed border, centered, 48px padding

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: isDark ? kPanelDark : kPanel,
          border: Border.all(
            color: kLine,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: kMuted),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: kInk,
            ),
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: const TextStyle(
                fontSize: 14,
                color: kMuted,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 24),
            _PrimaryButton(
              onPressed: action!,
              child: Text(actionLabel ?? 'Action'),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── LoadingOverlay ──────────────────────────────────────────────────────────

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay(
      {super.key, required this.loading, required this.child});
  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      if (loading)
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0x33000000),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(kViolet),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ─── _PrimaryButton ── shared styled button matching web .primary ─────────────

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.onPressed, required this.child});
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: kViolet,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 14),
      ),
      child: child,
    );
  }
}

// ─── RoleChip ────────────────────────────────────────────────────────────────
// Matches web member-row span: #F0F0F6 bg, #777987 text, pill

class RoleChip extends StatelessWidget {
  const RoleChip(this.role, {super.key});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F6),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        role,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF777987),
        ),
      ),
    );
  }
}

// ─── Confirmation dialog ──────────────────────────────────────────────────────

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: Text(message, style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel',
              style: TextStyle(color: kMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            foregroundColor: destructive ? kDanger : kViolet,
          ),
          child: Text(confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ─── Date / time helpers ──────────────────────────────────────────────────────

String dateLabel(String? iso) {
  if (iso == null || iso.isEmpty) return 'No date';
  final d = DateTime.tryParse(iso);
  if (d == null) return 'No date';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
    lastDate: DateTime(2035),
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: Theme.of(ctx).colorScheme.copyWith(
          primary: kViolet,
          onPrimary: Colors.white,
        ),
      ),
      child: child!,
    ),
  );
}

// ─── WebCard ─────────────────────────────────────────────────────────────────
// The exact card style from web: 0 elevation, 1px border #E1E1E6, radius 8

class WebCard extends StatelessWidget {
  const WebCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );
  }
}

// ─── Eyebrow text ─────────────────────────────────────────────────────────────
// Matches web .eyebrow: 10-11px, bold, violet, uppercase, letter-spacing

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: kViolet,
        letterSpacing: 1.2,
      ),
    );
  }
}
