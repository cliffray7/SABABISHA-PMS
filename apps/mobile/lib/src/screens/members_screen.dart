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
    setState(() => _busy = true);
    try {
      final removed = await showDialog<bool>(
        context: context,
        builder: (_) => _MemberRemovalDialog(
          api: widget.state.api,
          member: m,
          organizationId: widget.org.id,
          onTargetMissing: () => widget.state.selectOrg(widget.org),
        ),
      );
      if (removed == true && mounted) await widget.state.selectOrg(widget.org);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = memberRemovalErrorMessage(e));
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
                initialValue: role,
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

String projectRoleErrorMessage(ApiException error) => switch (error.code) {
      'invalid_project_role' => 'Choose one of the supported project roles.',
      'self_role_change_not_allowed' =>
        'You cannot change your own project role this way.',
      'guest_project_role_must_be_viewer' =>
        'Organization guests can only have the Viewer project role.',
      'project_must_retain_manager' =>
        'This project must keep at least one active project manager.',
      'project_role_update_forbidden' =>
        'You do not have permission to change project member roles.',
      'project_manager_grant_forbidden' =>
        'Only organization admins and project managers can grant the Project Manager role.',
      'project_role_update_conflict' =>
        'The project is busy. Refresh member data, then retry.',
      _ => error.message,
    };

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

  Future<void> _updateRole(Member member, String role) async {
    final project = widget.project;
    if (project == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.api.updateProjectMemberRole(
        projectId: project.id,
        userId: member.userId,
        role: role,
      );
      await widget.state.selectProject(project);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = projectRoleErrorMessage(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update the project member role.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Member'),
              items: eligible
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Row(children: [
                          AvatarChip(
                            initials: m.initials,
                            size: 24,
                            avatarUrl: m.avatarUrl,
                          ),
                          const SizedBox(width: 8),
                          Text(m.fullName),
                        ]),
                      ))
                  .toList(),
              onChanged: (m) => set(() => selected = m),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: role,
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
    setState(() => _busy = true);
    try {
      final currentProject = widget.project!;
      final removed = await showDialog<bool>(
        context: context,
        builder: (_) => _MemberRemovalDialog(
          api: widget.state.api,
          member: m,
          organizationId: widget.org.id,
          projectId: currentProject.id,
          onTargetMissing: () => widget.state.selectProject(currentProject),
        ),
      );
      if (removed == true && mounted) {
        await widget.state.selectProject(currentProject);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = memberRemovalErrorMessage(e));
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
    final canEditProjectRoles =
        widget.org.isAdminOrOwner || project.role == 'PROJECT_MANAGER';
    final canGrantProjectManager =
        widget.org.isAdminOrOwner || project.role == 'PROJECT_MANAGER';
    final accountId = widget.state.account?.id ?? '';

    return RefreshIndicator(
      color: kViolet,
      onRefresh: () => widget.state.selectProject(project),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null)
          ErrorBanner(_error!, onDismiss: () => setState(() => _error = null)),
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
            final isGuest = widget.state.orgMembers.any(
              (organizationMember) =>
                  organizationMember.userId == m.userId &&
                  organizationMember.role == 'GUEST',
            );
            final displayedRole = isGuest ? 'VIEWER' : m.role;
            final canEditRole = canEditProjectRoles && !isGuest;
            return _MemberRow(
              member: m,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (canEditRole)
                  Semantics(
                    label: 'Project role for ${m.fullName}',
                    child: DropdownButton<String>(
                      key: ValueKey('project-role-${m.userId}'),
                      value: displayedRole,
                      isDense: true,
                      items: projectRoles
                          .where((role) =>
                              canGrantProjectManager ||
                              role != 'PROJECT_MANAGER')
                          .map((role) => DropdownMenuItem(
                                value: role,
                                child: Text(role),
                              ))
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (role) {
                              if (role != null && role != displayedRole) {
                                _updateRole(m, role);
                              }
                            },
                    ),
                  )
                else
                  RoleChip(displayedRole),
                if (canRemove) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: kDanger, size: 20),
                    onPressed: _busy ? null : () => _remove(m),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ]),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          Text(subtitle, style: const TextStyle(fontSize: 14, color: kMuted)),
        ]),
      ),
      if (actionLabel != null)
        FilledButton.icon(
          onPressed: onAction,
          style: FilledButton.styleFrom(
            backgroundColor: kViolet,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          icon: const Icon(Icons.person_add_outlined, size: 16),
          label: Text(actionLabel!,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
        AvatarChip(
          initials: member.initials,
          size: 40,
          avatarUrl: member.avatarUrl,
        ),
        const SizedBox(width: 12),
        // Name + email
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              member.fullName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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

class _MemberRemovalDialog extends StatefulWidget {
  const _MemberRemovalDialog({
    required this.api,
    required this.member,
    required this.organizationId,
    required this.onTargetMissing,
    this.projectId,
  });

  final ApiClient api;
  final Member member;
  final String organizationId;
  final Future<void> Function() onTargetMissing;
  final String? projectId;

  @override
  State<_MemberRemovalDialog> createState() => _MemberRemovalDialogState();
}

class _MemberRemovalDialogState extends State<_MemberRemovalDialog> {
  MemberRemovalPreview? _preview;
  final Map<String, MemberTaskResolution> _choices = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;
  int _generation = 0;

  bool get _organizationScope => widget.projectId == null;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview({bool stale = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _choices.clear();
      _preview = null;
      _notice = stale
          ? 'The preview changed. Review this updated information and confirm again.'
          : null;
    });
    try {
      final result = _organizationScope
          ? await widget.api.previewOrgMemberDeactivation(
              orgId: widget.organizationId, userId: widget.member.userId)
          : await widget.api.previewProjectMemberRemoval(
              projectId: widget.projectId!, userId: widget.member.userId);
      if (!mounted || generation != _generation) return;
      setState(() => _preview = result);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      final code = error is ApiException ? error.code : null;
      if (code == 'PROJECT_NOT_FOUND' || code == 'MEMBER_NOT_FOUND') {
        await widget.onTargetMissing();
        if (!mounted || generation != _generation) return;
      }
      setState(() => _error = memberRemovalErrorMessage(error));
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  List<(RemovalProjectPreview, RemovalTaskPreview)> get _tasks => [
        for (final project in _preview?.affectedProjects ?? const [])
          for (final task in project.tasks) (project, task),
      ];

  bool get _blocked => (_preview?.affectedProjects ?? const []).any(
        (project) =>
            project.ownerTransferRequired || project.managerInvariantBlocked,
      );

  bool get _canConfirm =>
      _preview != null &&
      !_loading &&
      !_busy &&
      !_blocked &&
      _preview!.affectedTaskCount <= 100 &&
      _tasks.every((entry) {
        final choice = _choices[entry.$2.taskId];
        return choice != null &&
            (choice.action != 'REASSIGN' ||
                (choice.replacementUserId?.isNotEmpty ?? false));
      });

  void _choose(RemovalTaskPreview task, String action,
      {String? replacementUserId}) {
    setState(() {
      _choices[task.taskId] = MemberTaskResolution(
        taskId: task.taskId,
        action: action,
        replacementUserId: replacementUserId,
      );
    });
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null || !_canConfirm) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    final resolutions = _tasks
        .map((entry) => _choices[entry.$2.taskId]!)
        .toList(growable: false);
    try {
      if (_organizationScope) {
        await widget.api.confirmOrgMemberDeactivation(
          orgId: widget.organizationId,
          userId: widget.member.userId,
          snapshotHash: preview.snapshotHash,
          resolutions: resolutions,
        );
      } else {
        await widget.api.confirmProjectMemberRemoval(
          projectId: widget.projectId!,
          userId: widget.member.userId,
          snapshotHash: preview.snapshotHash,
          resolutions: resolutions,
        );
      }
      if (mounted && generation == _generation) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      final code = error is ApiException ? error.code : null;
      if (code == 'MEMBER_REMOVAL_PREVIEW_STALE' ||
          code == 'MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE') {
        setState(() => _busy = false);
        await _loadPreview(stale: true);
      } else {
        if (code == 'PROJECT_NOT_FOUND' || code == 'MEMBER_NOT_FOUND') {
          await widget.onTargetMissing();
          if (!mounted || generation != _generation) return;
        }
        setState(() => _error = memberRemovalErrorMessage(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_organizationScope
            ? 'Deactivate organization member'
            : 'Remove project member'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Review assignments for ${widget.member.fullName}.'),
                if (_loading) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                  const Text('Loading removal preview…'),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  Text(_notice!, style: const TextStyle(color: kViolet)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ErrorBanner(_error!),
                  if (preview == null && !_loading)
                    TextButton(
                      onPressed: () => _loadPreview(),
                      child: const Text('Retry preview'),
                    ),
                ],
                if (preview != null) ...[
                  for (final project in preview.affectedProjects) ...[
                    const SizedBox(height: 16),
                    Text(
                        'Project ${project.projectId} · ${project.lifecycle.replaceAll('_', ' ')}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (project.ownerTransferRequired)
                      const ErrorBanner(
                          'Transfer project ownership before removal.'),
                    if (project.managerInvariantBlocked)
                      const ErrorBanner(
                          'The project must retain an eligible active manager.'),
                    if (project.tasks.isEmpty)
                      const Text(
                          'No open task assignments require a resolution.'),
                    for (final task in project.tasks)
                      _buildTaskResolution(project, task),
                  ],
                  for (final project in preview.affectedProjects)
                    if (project.historicalAttributionsToInactivate.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          '${project.historicalAttributionsToInactivate.length} completed or trashed task assignment(s) will be inactivated while preserving attribution.',
                        ),
                      ),
                  for (final project in preview.expiredTrashCleanup)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        'Expired Trash project ${project.projectId}: server-directed cleanup will process ${project.tasks.length} task assignment(s). No new assignment will be created.',
                      ),
                    ),
                  if (preview.affectedTaskCount > 100)
                    const ErrorBanner(
                        'This operation exceeds the 100-task limit and was not submitted.'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canConfirm ? _confirm : null,
            child: Text(_busy
                ? 'Processing…'
                : _organizationScope
                    ? 'Deactivate member'
                    : 'Remove member'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskResolution(
      RemovalProjectPreview project, RemovalTaskPreview task) {
    final choice = _choices[task.taskId];
    final lifecycle =
        task.requiredResolution == 'ACCEPT_LIFECYCLE_INACTIVATION';
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
                '${task.status} · Current assignees: ${task.currentAssigneeIds.isEmpty ? 'None' : task.currentAssigneeIds.join(', ')}'),
            if (lifecycle)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: choice?.action == 'ACCEPT_LIFECYCLE_INACTIVATION',
                onChanged: _busy
                    ? null
                    : (checked) => checked == true
                        ? _choose(task, 'ACCEPT_LIFECYCLE_INACTIVATION')
                        : setState(() => _choices.remove(task.taskId)),
                title: const Text(
                    'Acknowledge lifecycle inactivation; no replacement will be assigned.'),
              )
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('removal-action-${task.taskId}'),
                initialValue:
                    choice?.action == 'REASSIGN' || choice?.action == 'UNASSIGN'
                        ? choice!.action
                        : null,
                decoration: const InputDecoration(labelText: 'Resolution'),
                items: const [
                  DropdownMenuItem(value: 'REASSIGN', child: Text('Reassign')),
                  DropdownMenuItem(
                      value: 'UNASSIGN', child: Text('Leave unassigned')),
                ],
                onChanged: _busy
                    ? null
                    : (action) {
                        if (action == null) {
                          setState(() => _choices.remove(task.taskId));
                          return;
                        }
                        final resolutionAction = action;
                        setState(() {
                          if (resolutionAction == 'UNASSIGN') {
                            _choices[task.taskId] = MemberTaskResolution(
                              taskId: task.taskId,
                              action: resolutionAction,
                              replacementUserId: null,
                            );
                          } else if (resolutionAction == 'REASSIGN') {
                            _choices[task.taskId] = MemberTaskResolution(
                              taskId: task.taskId,
                              action: resolutionAction,
                              replacementUserId: '',
                            );
                          } else {
                            _choices.remove(task.taskId);
                          }
                        });
                      },
              ),
              if (choice?.action == 'REASSIGN')
                DropdownButtonFormField<String>(
                  key: ValueKey('removal-replacement-${task.taskId}'),
                  initialValue: (choice?.replacementUserId?.isNotEmpty ?? false)
                      ? choice!.replacementUserId
                      : null,
                  decoration:
                      const InputDecoration(labelText: 'Eligible replacement'),
                  items: project.eligibleReplacementMembers
                      .map((member) => DropdownMenuItem(
                            value: member.userId,
                            child: Text(member.displayName),
                          ))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (userId) => userId == null
                          ? null
                          : _choose(task, 'REASSIGN',
                              replacementUserId: userId),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String memberRemovalErrorMessage(Object error) {
  if (error is ApiException) {
    const messages = {
      'MEMBER_REMOVAL_FORBIDDEN':
          'You do not have permission to remove this member.',
      'MEMBER_RESOLUTION_REQUIRED':
          'Resolve every affected task before confirming.',
      'MEMBER_RESOLUTION_INVALID':
          'One or more task resolutions are no longer valid.',
      'MEMBER_REMOVAL_PREVIEW_STALE':
          'Project or assignment data changed. Review a fresh preview before confirming.',
      'MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE':
          'The selected replacement is no longer eligible. Review a fresh preview.',
      'PROJECT_OWNER_TRANSFER_REQUIRED':
          'Transfer project ownership before removing this member.',
      'PROJECT_MUST_RETAIN_MANAGER':
          'The project must retain at least one eligible active manager.',
      'MEMBER_REMOVAL_CONFLICT':
          'The workspace changed during removal. Review a fresh preview and retry.',
      'MEMBER_RESOLUTION_LIMIT_EXCEEDED':
          'This operation exceeds the supported task-resolution limit and was not applied.',
      'ORGANIZATION_OWNER_CANNOT_BE_REMOVED':
          'Transfer organization ownership before deactivating this member.',
      'PROJECT_NOT_FOUND':
          'The project is no longer available. Refresh the member list.',
      'MEMBER_NOT_FOUND':
          'The member is no longer available. Refresh the member list.',
    };
    return messages[error.code] ?? error.message;
  }
  return 'The request could not be completed. Check your connection and retry.';
}
