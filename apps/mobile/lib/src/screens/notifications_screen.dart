import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../widgets/common.dart';

/// Matches the web notifications page:
/// - Page heading "Notifications" + "Mark all read" button
/// - List of notification rows: bell icon circle + message + timestamp + unread dot
/// - Unread rows: violet-tinted background (#F5F3FF / dark #302D57)
/// - Swipe-to-read gesture
/// - Empty state when all caught up
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.onNavigateToTask});
  final void Function(String projectId, String taskId)? onNavigateToTask;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notices = state.notifications;
    final hasUnread = notices.any((n) => !n.isRead);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      color: kViolet,
      onRefresh: () => state.loadNotifications(),
      child: CustomScrollView(
        slivers: [
          // ── Page heading ────────────────────────────────────────────────
          // Web: .page-heading: h1 + "Mark all read" button
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      'Notifications',
                      style: GoogleFonts.dmSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                        color: isDark
                            ? const Color(0xFFEEF0F8)
                            : kInk,
                      ),
                    ),
                  ]),
                ),
                if (hasUnread)
                  OutlinedButton(
                    onPressed: () => state.markAllRead(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                    ),
                    child: const Text('Mark all read',
                        style: TextStyle(fontSize: 13)),
                  ),
              ]),
            ),
          ),

          // ── Error banner ───────────────────────────────────────────────
          if (state.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: ErrorBanner(state.error!,
                    onDismiss: state.clearError),
              ),
            ),

          // ── Loading ────────────────────────────────────────────────────
          if (state.loadingNotifications && notices.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation(kViolet)),
              ),
            )

          // ── Empty state ────────────────────────────────────────────────
          else if (notices.isEmpty)
            const SliverFillRemaining(
              child: EmptyState(
                icon: Icons.notifications_none_outlined,
                title: "You're all caught up",
                message:
                    'Task assignments, comments, and mentions will appear here.',
              ),
            )

          // ── Notification list ──────────────────────────────────────────
          // Web .notifications-page .notification-row
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final n = notices[i];
                    final unreadBg = isDark
                        ? const Color(0xFF302D57)
                        : const Color(0xFFF5F3FF);
                    final iconBg = isDark
                        ? const Color(0xFF2A2738)
                        : const Color(0xFFEEEBFF);

                    return Dismissible(
                      key: Key(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(
                          color: kViolet,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.done,
                            color: Colors.white),
                      ),
                      onDismissed: (_) => state.markRead(n.id),
                      child: GestureDetector(
                        onTap: () async {
                          await state.markRead(n.id);
                          if (n.projectId != null &&
                              n.relatedId != null &&
                              widget.onNavigateToTask != null) {
                            widget.onNavigateToTask!(
                                n.projectId!, n.relatedId!);
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.fromLTRB(
                              16, 14, 16, 14),
                          decoration: BoxDecoration(
                            color: n.isRead
                                ? (isDark ? kPanelDark : kPanel)
                                : unreadBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF343845)
                                  : kLine,
                            ),
                          ),
                          child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            // Bell icon circle — web .notification-icon
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: iconBg,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.notifications_outlined,
                                size: 16,
                                color: n.isRead ? kMuted : kViolet,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Message + timestamp + unread dot
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                Text(
                                  n.message,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: n.isRead
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Text(
                                    timeAgo(n.createdAt),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: kMuted),
                                  ),
                                  if (!n.isRead) ...[
                                    const Text(' · ',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: kMuted)),
                                    const Text('Unread',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: kViolet,
                                            fontWeight:
                                                FontWeight.w600)),
                                    const SizedBox(width: 6),
                                    // Unread dot
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: kViolet,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ]),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                  childCount: notices.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
