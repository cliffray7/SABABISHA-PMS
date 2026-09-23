import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

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
          title: 'No organization selected');
    }

    return Column(children: [
      TabBar(
        controller: _tabs,
        tabs: [
          const Tab(text: 'Organization'),
          Tab(text: project?.name ?? 'Project'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _OrgMembersTab(state: state, org: org),
            _ProjectMembersTab(state: state, org: org, project: project),
          ],
        ),
      ),
    ]);
  }
}

// ─── Organization members tab ─────────────────────────────────────────────────

class _OrgMembersTab extends StatefulWidget {
  const _OrgMembersTab({required this.state, required this.org});
  final AppState state;
  final Organization org;

  @override
  State<_OrgMembersTab> createState() => _OrgMembersTabState();
}

class _OrgMembersTabState extends State<_OrgMembersTab> {
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
                Text(err!,
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error)),
              TextFormField(
                controller: emailCtrl,
                decoration:
                    const InputDecoration(labelText: 'Email address'),
                keyboardType: TextInputType.emailAddress,
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

  @override
  Widget build(BuildContext context) {
    final members = widget.state.orgMembers;
    final invitations = widget.state.invitations;
    final isAdmin = widget.org.isAdminOrOwner;
    final accountId = widget.state.account?.id ?? '';

    return RefreshIndicator(
      onRefresh: () => widget.state.selectOrg(widget.org),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null)
          ErrorBanner(_error!, onDismiss: () => setState(() => _error = null)),

        SectionHeader(
          'Members (${members.length})',
          trailing: isAdmin
              ? IconButton(
                  icon: const Icon(Icons.person_add_outlined),
                  onPressed: _busy ? null : _showInviteDialog,
                  tooltip: 'Invite teammate',
                )
              : null,
        ),
        const SizedBox(height: 8),

        ...members.map((m) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: AvatarChip(initials: m.initials),
                title: Text(m.fullName),
                subtitle: Text(m.email),
                trailing: isAdmin && m.role != 'OWNER' && m.userId != accountId
                    ? PopupMenuButton<String>(
                        initialValue: m.role,
                        itemBuilder: (_) => [
                          ...orgRoles.map((r) => PopupMenuItem(
                                value: r,
                                child: Text(r),
                              )),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                              value: '__remove__',
                              child: Text('Remove',
                                  style: TextStyle(color: Colors.red))),
                        ],
                        onSelected: (v) {
                          if (v == '__remove__') {
                            _remove(m);
                          } else {
                            _updateRole(m, v);
                          }
                        },
                        child: Chip(
                          label: Text(m.role,
                              style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      )
                    : Chip(
                        label: Text(m.role,
                            style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
              ),
            )),

        if (isAdmin && invitations.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader('Pending invitations (${invitations.length})'),
          const SizedBox(height: 8),
          ...invitations.map((inv) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(inv.email),
                  subtitle: Text(
                      '${inv.role} · Expires ${dateLabel(inv.expiresAt)}'),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await widget.state.api.cancelInvitation(
                                  orgId: widget.org.id,
                                  invitationId: inv.id);
                              await widget.state.selectOrg(widget.org);
                            } on ApiException catch (e) {
                              setState(() => _error = e.message);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    child: const Text('Cancel'),
                  ),
                ),
              )),
        ],
      ]),
    );
  }
}

// ─── Project members tab ──────────────────────────────────────────────────────

class _ProjectMembersTab extends StatefulWidget {
  const _ProjectMembersTab(
      {required this.state, required this.org, this.project});
  final AppState state;
  final Organization org;
  final Project? project;

  @override
  State<_ProjectMembersTab> createState() => _ProjectMembersTabState();
}

class _ProjectMembersTabState extends State<_ProjectMembersTab> {
  bool _busy = false;
  String? _error;

  Future<void> _showAddMemberDialog() async {
    final existing = widget.state.projectMembers.map((m) => m.userId).toSet();
    final eligible = widget.state.orgMembers
        .where((m) => !existing.contains(m.userId))
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All organization members are already in this project.')));
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
              Text(err!,
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error)),
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
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
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
          message: 'Select a project to manage its members.');
    }

    final members = widget.state.projectMembers;
    final isManager = project.isManagerOrLead;
    final accountId = widget.state.account?.id ?? '';

    return RefreshIndicator(
      onRefresh: () => widget.state.selectProject(project),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null)
          ErrorBanner(_error!, onDismiss: () => setState(() => _error = null)),

        SectionHeader(
          '${project.name} members (${members.length})',
          trailing: isManager
              ? IconButton(
                  icon: const Icon(Icons.person_add_outlined),
                  onPressed: _busy ? null : _showAddMemberDialog,
                  tooltip: 'Add member',
                )
              : null,
        ),
        const SizedBox(height: 8),

        ...members.map((m) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: AvatarChip(initials: m.initials),
                title: Text(m.fullName),
                subtitle: Text(m.email),
                trailing: isManager && m.userId != accountId
                    ? IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: _busy ? null : () => _remove(m),
                      )
                    : Chip(
                        label: Text(m.role,
                            style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
              ),
            )),

        if (members.isEmpty)
          const EmptyState(
              icon: Icons.group_outlined,
              title: 'No project members yet'),
      ]),
    );
  }
}
