import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';

/// Card-like tap target: ripple + a small press-in scale, with proper semantics.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.radius = 20, this.semanticLabel, this.color});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final String? semanticLabel;
  final Color? color;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: _down && enabled && !Motion.reduced(context) ? .975 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Material(
          color: widget.color ?? context.cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.radius), side: BorderSide(color: context.cs.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap == null
                ? null
                : () {
                    Haptic.tap();
                    widget.onTap!();
                  },
            onLongPress: widget.onLongPress,
            onHighlightChanged: (v) => setState(() => _down = v),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a child in once. Later items (higher [index]) take a little longer, which reads as a stagger.
class StaggeredIn extends StatelessWidget {
  const StaggeredIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + math.min(index, 8) * 70),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: c)),
      child: child,
    );
  }
}

/// Counts up to [value] (and from the previous value when it changes).
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, this.style, this.suffix = ''});
  final int value;
  final TextStyle? style;
  final String suffix;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: Motion.d(context, 800),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('${v.round()}$suffix', style: style),
      );
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 96, this.stroke = 10, this.color, this.trackColor, this.child});
  final double value; // 0..1
  final double size, stroke;
  final Color? color, trackColor;
  final Widget? child;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1)),
          duration: Motion.d(context, 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => CustomPaint(painter: _RingPainter(v, stroke, color ?? context.cs.primary, trackColor ?? context.cs.outlineVariant), child: Center(child: child)),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.color, this.track);
  final double v, stroke;
  final Color color, track;
  @override
  void paint(Canvas c, Size s) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(s.width - stroke, s.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    c.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    if (v > 0) c.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track || o.stroke != stroke;
}

class SubjectBadge extends StatelessWidget {
  const SubjectBadge(this.subjectId, {super.key, this.size = 44});
  final String subjectId;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = subjectColor(subjectId);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: dark ? .22 : .14), borderRadius: BorderRadius.circular(size * .32)),
      child: Icon(subjectIcon(subjectId), color: dark ? Color.lerp(c, Colors.white, .35) : c, size: size * .54),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action, this.onAction});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: context.tt.titleLarge)),
            if (subtitle != null) Text(subtitle!, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ])),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.text, this.action});
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 84, height: 84, decoration: BoxDecoration(color: context.sq.soft, shape: BoxShape.circle), child: Icon(icon, size: 40, color: context.cs.primary)),
            const SizedBox(height: 18),
            Text(title, style: context.tt.titleMedium, textAlign: TextAlign.center),
            if (text != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(text!, textAlign: TextAlign.center, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant))),
            if (action != null) Padding(padding: const EdgeInsets.only(top: 18), child: action),
          ]),
        ),
      );
}

/// Large collapsing title (Material 3) + content slivers, with optional pull-to-refresh.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.title, this.subtitle, this.actions = const [], required this.slivers, this.onRefresh, this.leading, this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 32)});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final Widget? leading;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar.large(title: Text(title), actions: actions, leading: leading, backgroundColor: Theme.of(context).scaffoldBackgroundColor),
        if (subtitle != null) SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), sliver: SliverToBoxAdapter(child: Text(subtitle!, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)))),
        SliverPadding(padding: padding, sliver: SliverMainAxisGroup(slivers: slivers)),
      ],
    );
    return onRefresh == null ? scroll : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
}

void showSnack(BuildContext c, String message) {
  final m = ScaffoldMessenger.of(c);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(BuildContext c, {required String title, required String body, String ok = 'Confirm', bool danger = false}) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(style: danger ? FilledButton.styleFrom(backgroundColor: d.cs.error, foregroundColor: Colors.white, minimumSize: const Size(64, 44)) : FilledButton.styleFrom(minimumSize: const Size(64, 44)), onPressed: () => Navigator.pop(d, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

/// Small filled pill used for status ("Exam", "Grade 11", ...).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.cs.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Color.lerp(c, Colors.white, .4)! : Color.lerp(c, Colors.black, .35)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: dark ? .22 : .13), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

String relativeTime(int ms, int nowMs) {
  final m = ((nowMs - ms) / 60000).round();
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  final h = (m / 60).round();
  if (h < 24) return '$h h ago';
  final d = (h / 24).round();
  return d == 1 ? 'yesterday' : '$d days ago';
}

String mmss(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final r = s % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}' : '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}
