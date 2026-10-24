import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

/// Shown after an administrator signs in. Students never see this page: they go straight to the student app.
class ModeChoicePage extends StatelessWidget {
  const ModeChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final u = app.user;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
              StaggeredIn(index: 0, child: Row(children: [
                Image.asset('assets/images/logo.png', width: 44, height: 44),
                const SizedBox(width: 12),
                Text('SQUIZ', style: context.tt.headlineSmall?.copyWith(color: context.sq.link)),
              ])),
              const SizedBox(height: 28),
              StaggeredIn(index: 1, child: Text('Welcome, ${u?.fullName.split(' ').first ?? 'administrator'}', style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800))),
              const SizedBox(height: 6),
              StaggeredIn(index: 2, child: Text('How would you like to continue?', style: context.tt.bodyLarge?.copyWith(color: context.cs.onSurfaceVariant))),
              const SizedBox(height: 24),
              StaggeredIn(
                index: 3,
                child: _Choice(
                  icon: Icons.admin_panel_settings_rounded,
                  title: 'Continue as administrator',
                  sub: 'Users, content, Excel import, statistics and announcements.',
                  filled: true,
                  onTap: () => app.chooseMode(AppMode.admin),
                ),
              ),
              const SizedBox(height: 12),
              StaggeredIn(
                index: 4,
                child: _Choice(
                  icon: Icons.school_rounded,
                  title: 'Continue as student',
                  sub: 'Practise and take exams like any student. You can switch back from your profile.',
                  onTap: () => app.chooseMode(AppMode.student),
                ),
              ),
              const SizedBox(height: 20),
              Center(child: TextButton(onPressed: () => app.signOut(), child: const Text('Sign out'))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.sub, required this.onTap, this.filled = false});
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final fg = filled ? kOnBrand : context.cs.onSurface;
    return Pressable(
      onTap: () {
        Haptic.tap();
        onTap();
      },
      radius: 22,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: filled ? const LinearGradient(colors: [kBrandDeep, kBrand], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          color: filled ? null : context.cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: filled ? kBrand : context.cs.outlineVariant),
        ),
        child: Row(children: [
          CircleAvatar(radius: 24, backgroundColor: filled ? Colors.white.withValues(alpha: .2) : kBrand.withValues(alpha: .15), child: Icon(icon, color: filled ? Colors.white : context.sq.link)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.tt.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(sub, style: context.tt.bodySmall?.copyWith(color: filled ? Colors.white70 : context.cs.onSurfaceVariant)),
          ])),
          Icon(Icons.arrow_forward_rounded, color: fg),
        ]),
      ),
    );
  }
}
