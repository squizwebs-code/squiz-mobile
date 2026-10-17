import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Motion helpers. Every animation respects the system "remove animations" setting.
class Motion {
  static bool reduced(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;
  static Duration d(BuildContext c, int ms) => reduced(c) ? Duration.zero : Duration(milliseconds: ms);
  static const Curve out = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;
}

/// Haptics in one place (so they can be switched off later).
class Haptic {
  static void tap() => HapticFeedback.selectionClick();
  static void good() => HapticFeedback.lightImpact();
  static void bad() => HapticFeedback.mediumImpact();
}

/// Slide + fade page route used for every pushed screen.
Future<T?> pushPage<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(PageRouteBuilder<T>(
      transitionDuration: Motion.d(context, 320),
      reverseTransitionDuration: Motion.d(context, 240),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(opacity: curved, child: SlideTransition(position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(curved), child: child));
      },
    ));

Future<T?> replacePage<T>(BuildContext context, Widget page) => Navigator.of(context).pushReplacement<T, void>(PageRouteBuilder<T>(
      transitionDuration: Motion.d(context, 360),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: ScaleTransition(scale: Tween(begin: .97, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)), child: child)),
    ));
