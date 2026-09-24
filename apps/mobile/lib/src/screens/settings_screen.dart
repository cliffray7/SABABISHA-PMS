import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(
      {super.key, required this.onSignedOut, required this.onToggleTheme});
  final VoidCallback onSignedOut;
  final VoidCallback onToggleTheme;

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

  Future<void> _requestPasswordReset() async {
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

  Future<void> _archiveProject(BuildContext context, AppState state) async {
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

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.logout();
      context.read<AppState>().signOut();
      widget.onSignedOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final account = state.account;
    final project = state.selectedProject;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          ErrorBanner(_error!, onDismiss: () => setState(() => _error = null)),
        if (_success != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.check_circle_outline, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_success!,
                      style: const TextStyle(color: Colors.green))),
              IconButton(
                  onPressed: () => setState(() => _success = null),
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints()),
            ]),
          ),

        // ─── Profile section ─────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your account',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstName,
                          decoration:
                              const InputDecoration(labelText: 'First name'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Required.'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lastName,
                          decoration:
                              const InputDecoration(labelText: 'Last name'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Required.'
                              : null,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (account != null)
                      TextFormField(
                        initialValue: account.email,
                        decoration:
                            const InputDecoration(labelText: 'Email address'),
                        enabled: false,
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _timezone,
                      decoration: const InputDecoration(
                          labelText: 'Timezone',
                          hintText: 'Africa/Nairobi'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Required.'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _saveProfile,
                        child: const Text('Save profile'),
                      ),
                    ),
                    const Divider(height: 32),
                    const Text('Password',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        'Request a secure reset link to change your password.',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 13)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _requestPasswordReset,
                      child: const Text('Send password reset link'),
                    ),
                  ]),
            ),
          ),
        ),

        // ─── Project settings ────────────────────────────────────────────
        if (project != null && project.isManagerOrLead) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Project settings',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text('${project.name} · ${project.status}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _showEditProjectDialog(
                                  context, state, project),
                          child: const Text('Edit project'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error),
                          onPressed:
                              _busy ? null : () => _archiveProject(context, state),
                          child: const Text('Archive project'),
                        ),
                      ),
                    ]),
                  ]),
            ),
          ),
        ],

        // ─── App preferences ─────────────────────────────────────────────
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            ListTile(
              leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              title: Text(isDark ? 'Dark mode' : 'Light mode'),
              subtitle: Text(isDark ? 'Switch to light mode' : 'Switch to dark mode'),
              trailing: Switch(
                  value: isDark,
                  onChanged: (_) => widget.onToggleTheme()),
            ),
          ]),
        ),

        // ─── Sign out ────────────────────────────────────────────────────
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: _busy ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

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
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error)),
                ),
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: status,
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
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
