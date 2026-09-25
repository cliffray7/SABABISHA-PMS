import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

/// Matches the web MembersPage:
/// - Two tabs: Organization | Project (named after project)
/// - Member rows: avatar + name/email + role chip
/// - Admin: role selector dropdown + Remove button
/// - Pending invitations section (org admin only)
/// - Invite / Add member dialogs
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final org = state.selectedOrg;
    final project = state.selectedProject;

    if (org == null) {
      return const EmptyState(
        icon: Icons.group_outlined,
        title: 'No organization selected',
        message: 'Create or select an organization to manage members.',
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(children: [
      // ── Tab strip — matches web .view-tabs ──────────────────────────────
      Container(
        decoration: BoxDecoration(
          color: isDark ? kPanelDark : kPanel,
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF343845) : kLine,
            ),
          ),
        ),
        child: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Organization'),
            Tab(text: project?.name ?? 'Project'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _OrgTab(state: state, org: org),
            _ProjectTab(state: state, org: org, project: project),
          ],
        ),
      ),
    ]);
  }
}

// ─── Organization members tab ─────────────────────────────────────────────────

class _OrgTab extends StatefulWidget {
  const _OrgTab({required this.state, required this.org});
  final AppState state;
  final Organization org;

  @override
  State<_OrgTab> createState() => _OrgTabState();
}

class _OrgTabState extends State<_OrgTab> {
  bool _busy = false;
  String? _error;

  Future<void> _updateRole(Member m, String role) async {
    setState(() => _busy = true);
    try {
      await widget.state.api.updateMemberRole(
          orgId: widget.org.id, userId: m.userId, role: role);
      await widget.state.selectOrg(widget.org);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Member m) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove member',
      message:
          'Remove ${m.fullName} from this workspace? Their tasks and comments will be kept.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await widget.state.api
          .removeOrgMember(orgId: widget.org.id, userId: m.userId);
      await widget.state.selectOrg(widget.org);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showInviteDialog() async {
    final emailCtrl = TextEditingController();
    String role = 'MEMBER';
    final formKey = GlobalKey<FormState>();
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Invite teammate'),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (err != null)
                ErrorBanner(err!,
                    onDismiss: () => set(() => err = null)),
              TextFormField(
                controller: emailCtrl,
                decoration:
                    const InputDecoration(labelText: 'Email address'),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                validator: (v) =>
                    v != null &&
                            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(v)
                        ? null
                        : 'Enter a valid email.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: orgRoles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => set(() => role = v!),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  await widget.state.api.inviteMember(
                      orgId: widget.org.id,
                      email: emailCtrl.text.trim(),
                      role: role);
                  await widget.state.selectOrg(widget.org);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on ApiException catch (e) {
                  set(() => err = e.message);
                }
              },
              child: const Text('Send invitation'),
            ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }

  Future<void> _cancelInvitation(Invitation inv) async {
    setState(() => _busy = true);
    try {
      await widget.state.api.cancelInvitation(
          orgId: widget.org.id, invitationId: inv.id);
      await widget.state.selectOrg(widget.org);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.state.orgMembers;
    final invitations = widget.state.invitations;
    final isAdmin = widget.org.isAdminOrOwner;
    final accountId = widget.state.account?.id ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      color: kViolet,
      onRefresh: () => widget.state.selectOrg(widget.org),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null)
          ErrorBanner(_error!,
              onDismiss: () => setState(() => _error = null)),

        // ── Section header ────────────────────────────────────────────────
        // Web .page-heading: eyebrow + h1 + member count + invite button
        _SectionHeading(
          eyebrow: widget.org.name,
          title: 'Organization',
          subtitle: '${members.length} members',
          actionLabel: isAdmin ? 'Invite teammate' : null,
          onAction: isAdmin ? _showInviteDialog : null,
        ),
        const SizedBox(height: 16),

        // ── Member rows ───────────────────────────────────────────────────
        // Web .members-panel .member-row
        ...members.map((m) {
          final canManage =
              isAdmin && m.role != 'OWNER' && m.userId != accountId;
          return _MemberRow(
            member: m,
            trailing: canManage
                ? PopupMenuButton<String>(
                    initialValue: m.role,
                    itemBuilder: (_) => [
                      ...orgRoles.map((r) =>
                          PopupMenuItem(value: r, child: Text(r))),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: '__remove__',
                        child: Text('Remove',
                            style: TextStyle(color: kDanger)),
                      ),
                    ],
                    onSelected: (v) {
                      if (v == '__remove__') {
                        _remove(m);
                      } else {
                        _updateRole(m, v);
                      }
                    },
                    child: RoleChip(m.role),
                  )
                : RoleChip(m.role),
          );
        }),

        // ── Pending invitations ───────────────────────────────────────────
        if (isAdmin && invitations.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(children: [
            Text(
              'Pending invitations',
              style: GoogleFonts.dmSans(
                  fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: isDark ? kPanelDark : kPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF343845) : kLine,
              ),
            ),
            child: Column(
              children: invitations.asMap().entries.map((entry) {
                final inv = entry.value;
                final isLast = entry.key == invitations.length - 1;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(children: [
                      const Icon(Icons.mail_outline,
                          size: 20, color: kMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(inv.email,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Text(
                            '${inv.role} · Expires ${dateLabel(inv.expiresAt)}',
                            style: const TextStyle(
                                fontSize: 12, color: kMuted),
                          ),
                        ]),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _cancelInvitation(inv),
                        style: TextButton.styleFrom(
                          foregroundColor: kMuted,
                          textStyle:
                              const TextStyle(fontSize: 13),
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ]),
                  ),
                  if (!isLast)
                    const Divider(height: 1, color: kLine),
                ]);
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

// ─── Project members tab ──────────────────────────────────────────────────────

class _ProjectTab extends StatefulWidget {
  const _ProjectTab(
      {required this.state, required this.org, this.project});
  final AppState state;
  final Organization org;
  final Project? project;

  @override
  State<_ProjectTab> createState() => _ProjectTabState();
}

class _ProjectTabState extends State<_ProjectTab> {
  bool _busy = false;
  String? _error;

  Future<void> _showAddMemberDialog() async {
    final existing =
        widget.state.projectMembers.map((m) => m.userId).toSet();
    final eligible = widget.state.orgMembers
        .where((m) => !existing.contains(m.userId))
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'All organization members are already in this project.'),
        ),
      );
      return;
    }

    Member? selected = eligible.first;
    String role = 'CONTRIBUTOR';
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add project member'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (err != null)
              ErrorBanner(err!,
                  onDismiss: () => set(() => err = null)),
            DropdownButtonFormField<Member>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Member'),
              items: eligible
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.fullName),
                      ))
                  .toList(),
              onChanged: (m) => set(() => selected = m),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: projectRoles
                  .map((r) =>
                      DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => set(() => role = v!),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (selected == null) return;
                try {
                  await widget.state.api.addProjectMember(
                      projectId: widget.project!.id,
                      userId: selected!.userId,
                      role: role);
                  await widget.state.selectProject(widget.project!);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on ApiException catch (e) {
                  set(() => err = e.message);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(Member m) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove from project',
      message:
          'Remove ${m.fullName} from this project? Their past work will be kept.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await widget.state.api.removeProjectMember(
          projectId: widget.project!.id, userId: m.userId);
      await widget.state.selectProject(widget.project!);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    if (project == null) {
      return const EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No project selected',
        message: 'Select a project to manage its members.',
      );
    }

    final members = widget.state.projectMembers;
    final isManager = project.isManagerOrLead;
    final accountId = widget.state.account?.id ?? '';

    return RefreshIndicator(
      color: kViolet,
      onRefresh: () => widget.state.selectProject(project),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null)
          ErrorBanner(_error!,
              onDismiss: () => setState(() => _error = null)),

        _SectionHeading(
          eyebrow: project.name,
          title: 'Project',
          subtitle: '${members.length} members',
          actionLabel: isManager ? 'Add member' : null,
          onAction: isManager ? _showAddMemberDialog : null,
        ),
        const SizedBox(height: 16),

        if (members.isEmpty)
          const EmptyState(
            icon: Icons.group_outlined,
            title: 'No project members yet',
          )
        else
          ...members.map((m) {
            final canRemove = isManager && m.userId != accountId;
            return _MemberRow(
              member: m,
              trailing: canRemove
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: kDanger, size: 20),
                      onPressed:
                          _busy ? null : () => _remove(m),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  : RoleChip(m.role),
            );
          }),
        const SizedBox(height: 24),
      ]),
    );
  }
}

// ─── Section heading (web .page-heading style) ────────────────────────────────

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Eyebrow('$eyebrow / PEOPLE'),
          const SizedBox(height: 4),
          Text(
            '$title members',
            style: GoogleFonts.dmSans(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          Text(subtitle,
              style: const TextStyle(fontSize: 14, color: kMuted)),
        ]),
      ),
      if (actionLabel != null)
        FilledButton.icon(
          onPressed: onAction,
          style: FilledButton.styleFrom(
            backgroundColor: kViolet,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
          ),
          icon: const Icon(Icons.person_add_outlined, size: 16),
          label: Text(actionLabel!,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
    ]);
  }
}

// ─── Member row ──────────────────────────────────────────────────────────────
// Web .member-row: 16px gap, avatar (44px), name+email, role chip

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.trailing});
  final Member member;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? kPanelDark : kPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF343845) : kLine,
        ),
      ),
      child: Row(children: [
        // Avatar
        AvatarChip(initials: member.initials, size: 40),
        const SizedBox(width: 12),
        // Name + email
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              member.fullName,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Text(
              member.email,
              style: const TextStyle(fontSize: 13, color: kMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: 12),
        trailing,
      ]),
    );
  }
}
