import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LauncherScreen extends StatelessWidget {
  const LauncherScreen({
    super.key,
    required this.onLogin,
    required this.onGetStarted,
  });

  final VoidCallback onLogin;
  final VoidCallback onGetStarted;

  static const _ink = Color(0xFF1E2944);
  static const _violet = Color(0xFF4D40ED);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = dark ? const Color(0xFF12131A) : const Color(0xFFF7F8FC);
    final card = dark ? const Color(0xFF1C1E28) : Colors.white;
    final foreground = dark ? const Color(0xFFEEF0F8) : _ink;
    final muted = dark ? const Color(0xFFB0B4C1) : const Color(0xFF737887);

    return Scaffold(
      backgroundColor: page,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SvgPicture.asset('assets/logos/taskflow-mark.svg', width: 42, height: 42),
                      const SizedBox(width: 10),
                      Text('TaskFlow', style: TextStyle(color: foreground, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
                      const Spacer(),
                      TextButton(onPressed: onLogin, child: const Text('Log in')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: dark ? const Color(0xFF343845) : const Color(0xFFE5E7EF)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.12 : 0.045), blurRadius: 28, offset: const Offset(0, 12))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(color: const Color(0xFFEFEDFF), borderRadius: BorderRadius.circular(30)),
                          child: const Text('PROJECTS, TASKS, TEAMWORK', style: TextStyle(color: _violet, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.05)),
                        ),
                        const SizedBox(height: 18),
                        Text('Turn team plans into finished work.', style: TextStyle(color: foreground, fontSize: 31, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -1.15)),
                        const SizedBox(height: 12),
                        Text('Plan projects, assign tasks, and see progress together in one simple workspace.', style: TextStyle(color: muted, fontSize: 15, height: 1.5)),
                        const SizedBox(height: 22),
                        _PreviewBoard(dark: dark),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: onGetStarted,
                            style: FilledButton.styleFrom(backgroundColor: _violet, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: const Text('Create your workspace', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Center(child: TextButton(onPressed: onLogin, child: const Text('I already have an account'))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: _Benefit(icon: Icons.view_kanban_outlined, title: 'See the work', subtitle: 'Projects and tasks', card: card, foreground: foreground, muted: muted)),
                      const SizedBox(width: 10),
                      Expanded(child: _Benefit(icon: Icons.people_outline, title: 'Work together', subtitle: 'One shared team', card: card, foreground: foreground, muted: muted)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(child: Text('Simple planning for work that moves forward.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewBoard extends StatelessWidget {
  const _PreviewBoard({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final surface = dark ? const Color(0xFF252834) : const Color(0xFFF6F7FB);
    final line = dark ? const Color(0xFF3A3E4D) : const Color(0xFFE5E7EF);
    final text = dark ? const Color(0xFFEEF0F8) : const Color(0xFF1E2944);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.dashboard_outlined, color: LauncherScreen._violet, size: 17), const SizedBox(width: 7), Text('Website refresh', style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 12)), const Spacer(), const Icon(Icons.more_horiz, size: 18)]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _MiniColumn(title: 'TO DO', color: const Color(0xFF9298A7), tasks: const ['Write project brief', 'Plan first milestone'], dark: dark)),
            const SizedBox(width: 8),
            Expanded(child: _MiniColumn(title: 'IN PROGRESS', color: LauncherScreen._violet, tasks: const ['Design landing page'], dark: dark)),
          ]),
        ],
      ),
    );
  }
}

class _MiniColumn extends StatelessWidget {
  const _MiniColumn({required this.title, required this.color, required this.tasks, required this.dark});
  final String title;
  final Color color;
  final List<String> tasks;
  final bool dark;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 5), Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.45)))]),
    const SizedBox(height: 7),
    ...tasks.map((task) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(9), width: double.infinity, decoration: BoxDecoration(color: dark ? const Color(0xFF1C1E28) : Colors.white, borderRadius: BorderRadius.circular(9), border: Border.all(color: dark ? const Color(0xFF3A3E4D) : const Color(0xFFE8EAF0))), child: Text(task, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: dark ? const Color(0xFFEEF0F8) : const Color(0xFF34394B), fontSize: 10, height: 1.3, fontWeight: FontWeight.w600)))),
  ]);
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.subtitle, required this.card, required this.foreground, required this.muted});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color card;
  final Color foreground;
  final Color muted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(15), border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF343845) : const Color(0xFFE5E7EF))),
    child: Row(children: [Icon(icon, size: 19, color: _LauncherColors.violet), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text(subtitle, style: TextStyle(color: muted, fontSize: 10))]))]),
  );
}

class _LauncherColors {
  static const violet = Color(0xFF4D40ED);
}
