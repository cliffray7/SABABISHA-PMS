import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../widgets/common.dart';

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

    return RefreshIndicator(
      onRefresh: () => state.loadNotifications(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(children: [
                const Expanded(
                    child: Text('Notifications',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold))),
                if (hasUnread)
                  TextButton(
                    onPressed: () => state.markAllRead(),
                    child: const Text('Mark all read'),
                  ),
              ]),
            ),
          ),
          if (state.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorBanner(state.error!,
                    onDismiss: state.clearError),
              ),
            ),
          if (state.loadingNotifications && notices.isEmpty)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()))
          else if (notices.isEmpty)
            const SliverFillRemaining(
              child: EmptyState(
                icon: Icons.notifications_none_outlined,
                title: "You're all caught up",
                message:
                    'Task assignments, comments, and mentions will appear here.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final n = notices[i];
                  return Dismissible(
                    key: Key(n.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      color: Colors.blue,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.done, color: Colors.white),
                    ),
                    onDismissed: (_) => state.markRead(n.id),
                    child: ListTile(
                      tileColor: n.isRead
                          ? null
                          : Theme.of(ctx)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.2),
                      leading: CircleAvatar(
                        backgroundColor: n.isRead
                            ? Theme.of(ctx)
                                .colorScheme
                                .surfaceContainerHighest
                            : Theme.of(ctx).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.notifications_outlined,
                          size: 20,
                          color: n.isRead
                              ? Theme.of(ctx).colorScheme.outline
                              : Theme.of(ctx)
                                  .colorScheme
                                  .onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        n.message,
                        style: TextStyle(
                            fontWeight: n.isRead
                                ? FontWeight.normal
                                : FontWeight.w600),
                      ),
                      subtitle: Row(children: [
                        Text(timeAgo(n.createdAt),
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    Theme.of(ctx).colorScheme.outline)),
                        if (!n.isRead) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Theme.of(ctx).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ]),
                      onTap: () async {
                        await state.markRead(n.id);
                        if (n.projectId != null &&
                            n.relatedId != null &&
                            widget.onNavigateToTask != null) {
                          widget.onNavigateToTask!(
                              n.projectId!, n.relatedId!);
                        }
                      },
                    ),
                  );
                },
                childCount: notices.length,
              ),
            ),
        ],
      ),
    );
  }
}
