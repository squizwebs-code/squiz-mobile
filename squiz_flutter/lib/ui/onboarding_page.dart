import 'package:flutter/material.dart';
import '../core/brand.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import 'app_scope.dart';
import 'auth/auth_page.dart';
import 'matric/matric.dart';
import 'widgets/common.dart';

/// First launch: pick a grade. (Signing in is optional and can be done later.)
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingPage> {
  int? _grade;
  String? _track; // Matric stream, asked for grades 11 and 12

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              const SizedBox(height: 12),
              StaggeredIn(index: 0, child: Row(children: [
                Image.asset('assets/images/logo.png', width: 44, height: 44),
                const SizedBox(width: 12),
                Text('SQUIZ', style: context.tt.headlineSmall?.copyWith(color: context.sq.link)),
              ])),
              const SizedBox(height: 28),
              StaggeredIn(index: 1, child: Text('Learn. Practise.\nImprove.', style: context.tt.displayMedium?.copyWith(height: 1.05))),
              const SizedBox(height: 12),
              StaggeredIn(index: 2, child: Text('Matric exam preparation and practice for Grades 9–12, with timed mock exams. Works offline.', style: context.tt.bodyLarge?.copyWith(color: context.cs.onSurfaceVariant))),
              const SizedBox(height: 28),
              StaggeredIn(index: 3, child: Text('Which grade are you in?', style: context.tt.titleMedium)),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.7,
                children: [
                  for (final (i, g) in [9, 10, 11, 12].indexed)
                    StaggeredIn(
                      index: 4 + i,
                      child: _GradeCard(grade: g, selected: _grade == g, onTap: () => setState(() => _grade = g)),
                    ),
                ],
              ),
              AnimatedSize(
                duration: Motion.d(context, 250),
                alignment: Alignment.topCenter,
                child: (_grade ?? 0) >= 11 && app.bank?.hasTracks == true
                    ? Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Which Matric stream?', style: context.tt.titleMedium),
                          const SizedBox(height: 4),
                          Text('We will show the subjects for your stream. You can change this any time.', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          TrackPicker(value: _track, onChanged: (t) => setState(() => _track = t)),
                        ]),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: _grade == null
                      ? null
                      : () async {
                          await app.setTrack((_grade! >= 11) ? _track : app.track);
                          await app.setGrade(_grade!);
                        },
                  child: const Text('Continue')),
              const SizedBox(height: 8),
              TextButton(onPressed: () => pushPage(context, const AuthPage()), child: const Text('I already have an account')),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({required this.grade, required this.selected, required this.onTap});
  final int grade;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final fg = selected ? kOnBrand : context.cs.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Grade $grade',
      child: AnimatedContainer(
        duration: Motion.d(context, 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: selected ? const LinearGradient(colors: [kBrandDeep, kBrand], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          color: selected ? null : context.cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? kBrand : context.cs.outlineVariant, width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: kBrand.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))] : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Haptic.tap();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Grade', style: TextStyle(color: fg.withValues(alpha: .8), fontWeight: FontWeight.w600)),
                Text('$grade', style: TextStyle(color: fg, fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
