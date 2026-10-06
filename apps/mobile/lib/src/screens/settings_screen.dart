import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

/// Matches the web SettingsPage:
/// - "Your account" card: two-col name fields, email (disabled), timezone, Save
/// - Password section: "Send password reset link" button
/// - Project settings card (if manager/lead): edit + archive buttons
/// - App preferences: dark mode toggle
/// - Sign out button (red outlined)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onSignedOut,
    required this.onToggleTheme,
    required this.themeMode,
  });
  final VoidCallback onSignedOut;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _timezone;
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    final account = context.read<AppState>().account;
    _firstName = TextEditingController(text: account?.firstName ?? '');
    _lastName = TextEditingController(text: account?.lastName ?? '');
    _timezone = TextEditingController(text: account?.timezone ?? 'UTC');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final state = context.read<AppState>();
      await state.api.updateAccount(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        timezone: _timezone.text.trim(),
      );
      await state.loadAccount();
      setState(() => _success = 'Profile saved.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final email = context.read<AppState>().account?.email ?? '';
      await context.read<AppState>().api.forgotPassword(email);
      setState(() => _success =
          'Password reset link sent. Check your email or the development inbox.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveProject(AppState state) async {
    final project = state.selectedProject;
    if (project == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Archive project',
      message:
          'Archive ${project.name}? Its data will be preserved, but it will leave the active project list.',
      confirmLabel: 'Archive',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await state.api.archiveProject(project.id);
      await state.loadOrganizations();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _trashProject(AppState state) async {
    final project = state.selectedProject;
    if (project == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Move project to Trash',
      message:
          'Move ${project.name} to Trash? You can restore it for 30 days. Archiving remains separate.',
      confirmLabel: 'Move to Trash',
      destructive: true,
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await state.api.trashProject(project.id);
      await state.loadOrganizations();
      if (mounted) setState(() => _success = 'Project moved to Trash.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseAvatar() async {
    final state = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 88,
      );
      if (image == null) return;
      if (!mounted) return;
      await state.api.uploadAvatar(File(image.path));
      await state.loadAccount();
      if (mounted) setState(() => _success = 'Profile picture updated.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    final state = context.read<AppState>();
    try {
      await state.api.logout();
      state.signOut();
      // Schedule the navigation callback after the current async gap so that
      // the parent setState is not called from within an async suspension.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onSignedOut());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final account = state.account;
    final project = state.selectedProject;
    final isDark = widget.themeMode == ThemeMode.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Feedback banners ───────────────────────────────────────────────
        if (_error != null)
          ErrorBanner(_error!, onDismiss: () => setState(() => _error = null)),
        if (_success != null)
          SuccessBanner(_success!,
              onDismiss: () => setState(() => _success = null)),

        // ── Page heading ──────────────────────────────────────────────────
        Text(
          'Settings',
          style: GoogleFonts.dmSans(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 20),

        if (account != null) ...[
          _SettingsCard(
            title: 'Profile picture',
            child: Row(children: [
              AvatarChip(
                initials:
                    account.firstName.isNotEmpty && account.lastName.isNotEmpty
                        ? '${account.firstName[0]}${account.lastName[0]}'
                        : account.firstName,
                size: 72,
                avatarUrl: account.avatarUrl,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('JPEG, PNG, WebP, or GIF · up to 5 MB',
                          style: TextStyle(fontSize: 12, color: kMuted)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        OutlinedButton(
                          onPressed: _busy ? null : _chooseAvatar,
                          child: const Text('Choose picture'),
                        ),
                      ]),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // ── Your account card ─────────────────────────────────────────────
        // Web .settings-panel: .list-panel with h2 "Your account"
        _SettingsCard(
          title: 'Your account',
          child: Form(
            key: _formKey,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Two-col name row — web .two-col
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstName,
                    decoration: const InputDecoration(labelText: 'First name'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required.' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastName,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required.' : null,
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // Email (disabled)
              if (account != null)
                TextFormField(
                  initialValue: account.email,
                  decoration: const InputDecoration(labelText: 'Email address'),
                  enabled: false,
                  style: const TextStyle(color: kMuted),
                ),
              const SizedBox(height: 12),

              // Timezone
              TextFormField(
                controller: _timezone,
                decoration: const InputDecoration(
                    labelText: 'Timezone', hintText: 'Africa/Nairobi'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required.' : null,
              ),
              const SizedBox(height: 16),

              // Save profile button — full width matching web
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _saveProfile,
                  child: const Text('Save profile'),
                ),
              ),

              // Password section
              const SizedBox(height: 4),
              const Divider(height: 32),
              Text(
                'Password',
                style: GoogleFonts.dmSans(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Request a secure reset link to change your password.',
                style: TextStyle(fontSize: 13, color: kMuted, height: 1.45),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _resetPassword,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 36),
                ),
                child: const Text('Send password reset link'),
              ),
            ]),
          ),
        ),

        if (state.selectedOrg != null) ...[
          const SizedBox(height: 16),
          _TrashSection(organizationId: state.selectedOrg!.id),
        ],

        // ── Project settings card ─────────────────────────────────────────
        if (project != null && project.isManagerOrLead) ...[
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Project settings',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${project.name} · ${project.status}',
                style: const TextStyle(fontSize: 14, color: kMuted),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _showEditProjectDialog(context, state, project),
                    child: const Text('Edit project'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: kDanger,
                        side: const BorderSide(color: kDanger)),
                    onPressed: _busy ? null : () => _archiveProject(state),
                    child: const Text('Archive project'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kDanger,
                      side: const BorderSide(color: kDanger)),
                  onPressed: _busy ? null : () => _trashProject(state),
                  child: const Text('Move project to Trash'),
                ),
              ),
            ]),
          ),
        ],

        // ── App preferences ───────────────────────────────────────────────
        const SizedBox(height: 16),
        _SettingsCard(
          title: 'Preferences',
          child: Row(children: [
            Icon(
              isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: kMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDark ? 'Dark mode' : 'Light mode',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      isDark ? 'Switch to light mode' : 'Switch to dark mode',
                      style: const TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ]),
            ),
            Switch(
              value: isDark,
              activeThumbColor: kViolet,
              onChanged: (_) => widget.onToggleTheme(),
            ),
          ]),
        ),

        // ── Sign out ──────────────────────────────────────────────────────
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: kDanger,
              side: const BorderSide(color: kDanger),
              minimumSize: const Size(double.infinity, 42),
            ),
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _TrashSection extends StatefulWidget {
  const _TrashSection({required this.organizationId});
  final String organizationId;

  @override
  State<_TrashSection> createState() => _TrashSectionState();
}

class _TrashSectionState extends State<_TrashSection> {
  List<TrashItem> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items =
          await context.read<AppState>().api.trash(widget.organizationId);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(TrashItem item) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = context.read<AppState>();
      await state.api.restoreTrashItem(item);
      await state.loadOrganizations();
      await state.refreshTasks();
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsCard(
        title: 'Recently deleted',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Items are permanently removed after 30 days.',
              style: TextStyle(fontSize: 12, color: kMuted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              ErrorBanner(_error!),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Trash is empty.',
                    style: TextStyle(fontSize: 13, color: kMuted)),
              )
            else
              ..._items.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${item.kind[0].toUpperCase()}${item.kind.substring(1)} · ${item.name.length > 72 ? '${item.name.substring(0, 72)}…' : item.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Deleted ${dateLabel(item.deletedAt.toIso8601String())}',
                    ),
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _restore(item),
                      child: const Text('Restore'),
                    ),
                  )),
          ],
        ),
      );
}

// ─── Settings card ────────────────────────────────────────────────────────────
// Web .list-panel.settings-panel: white card, h2 heading, content

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFEEF0F8) : kInk,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

// ─── Edit project dialog ──────────────────────────────────────────────────────

Future<void> _showEditProjectDialog(
    BuildContext context, AppState state, Project project) async {
  final nameCtrl = TextEditingController(text: project.name);
  final descCtrl = TextEditingController(text: project.description ?? '');
  String status = project.status;
  final formKey = GlobalKey<FormState>();
  String? error;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Edit project'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (error != null)
                ErrorBanner(error!, onDismiss: () => set(() => error = null)),
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: projectStatuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => set(() => status = v!),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                await state.api.updateProject(
                  projectId: project.id,
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  status: status,
                );
                await state.loadOrganizations();
                if (ctx.mounted) Navigator.pop(ctx);
              } on ApiException catch (e) {
                set(() => error = e.message);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  nameCtrl.dispose();
  descCtrl.dispose();
}
