import 'package:flutter/material.dart';
import 'brand.dart';

/// Extra colours that do not exist in Material's ColorScheme.
@immutable
class SquizColors extends ThemeExtension<SquizColors> {
  const SquizColors({required this.link, required this.good, required this.bad, required this.warn, required this.soft});
  final Color link; // small text/links in brand blue that stays readable on this background
  final Color good, bad, warn;
  final Color soft; // very light brand wash for chips and highlights

  @override
  SquizColors copyWith({Color? link, Color? good, Color? bad, Color? warn, Color? soft}) =>
      SquizColors(link: link ?? this.link, good: good ?? this.good, bad: bad ?? this.bad, warn: warn ?? this.warn, soft: soft ?? this.soft);

  @override
  SquizColors lerp(ThemeExtension<SquizColors>? other, double t) {
    if (other is! SquizColors) return this;
    return SquizColors(
        link: Color.lerp(link, other.link, t)!, good: Color.lerp(good, other.good, t)!, bad: Color.lerp(bad, other.bad, t)!, warn: Color.lerp(warn, other.warn, t)!, soft: Color.lerp(soft, other.soft, t)!);
  }
}

extension SquizTheme on BuildContext {
  SquizColors get sq => Theme.of(this).extension<SquizColors>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: kBrand, brightness: brightness);
  // Primary is pinned to the brand colour in BOTH themes; everything else is derived/tuned around it.
  final scheme = base.copyWith(
    primary: kBrand,
    onPrimary: kOnBrand,
    primaryContainer: dark ? const Color(0xFF173A5B) : const Color(0xFFD7E8F7),
    onPrimaryContainer: dark ? const Color(0xFFCFE4F8) : const Color(0xFF0E3150),
    surface: dark ? const Color(0xFF121A23) : const Color(0xFFFFFFFF),
    onSurface: dark ? const Color(0xFFE7EEF5) : const Color(0xFF14202B),
    onSurfaceVariant: dark ? const Color(0xFFA6B4C2) : const Color(0xFF52606D),
    surfaceContainerLowest: dark ? const Color(0xFF0D141B) : const Color(0xFFFFFFFF),
    surfaceContainerLow: dark ? const Color(0xFF151E28) : const Color(0xFFF6F9FC),
    surfaceContainer: dark ? const Color(0xFF1A2530) : const Color(0xFFEFF4F9),
    surfaceContainerHigh: dark ? const Color(0xFF202D3A) : const Color(0xFFE7EEF5),
    outline: dark ? const Color(0xFF5E7184) : const Color(0xFF8A99A8),
    outlineVariant: dark ? const Color(0xFF263544) : const Color(0xFFDCE5EE),
    error: dark ? const Color(0xFFFF8A8A) : kBad,
  );
  final bg = dark ? const Color(0xFF0D141B) : const Color(0xFFF3F7FB);
  final text = Typography.material2021(platform: TargetPlatform.android).black.apply(fontFamily: null);
  final tt = text.copyWith(
    displayMedium: text.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5),
    headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.4),
    headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.3),
    titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.2),
    titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: .1),
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  final shape14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    textTheme: tt,
    splashFactory: InkSparkle.splashFactory,
    extensions: [
      SquizColors(
        link: dark ? kBrand : kBrandInkLight,
        good: dark ? const Color(0xFF52C58C) : kGood,
        bad: dark ? const Color(0xFFFF8A8A) : kBad,
        warn: kWarn,
        soft: dark ? const Color(0xFF173A5B) : const Color(0xFFE6F0FA),
      ),
    ],
    appBarTheme: AppBarTheme(backgroundColor: bg, surfaceTintColor: Colors.transparent, foregroundColor: scheme.onSurface, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: scheme.outlineVariant)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: dark ? .30 : .16),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? (dark ? kBrandBright : kBrandInkLight) : scheme.onSurfaceVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(64, 52),
        shape: shape14,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? kBrandBright : kBrandInkLight,
        minimumSize: const Size(64, 52),
        shape: shape14,
        side: BorderSide(color: scheme.outlineVariant, width: 1.4),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: dark ? kBrandBright : kBrandInkLight, shape: shape14, textStyle: const TextStyle(fontWeight: FontWeight.w700))),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      selectedColor: scheme.primary.withValues(alpha: dark ? .32 : .18),
      backgroundColor: scheme.surface,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: shape14,
        side: BorderSide(color: scheme.outlineVariant),
        selectedBackgroundColor: scheme.primary.withValues(alpha: dark ? .32 : .16),
        selectedForegroundColor: dark ? Colors.white : kBrandInkLight,
        foregroundColor: scheme.onSurfaceVariant,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.error)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.error, width: 2)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape14, backgroundColor: dark ? const Color(0xFF2A3A4A) : const Color(0xFF1B2A38), contentTextStyle: const TextStyle(color: Colors.white)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: scheme.outlineVariant),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: ZoomPageTransitionsBuilder(), TargetPlatform.iOS: CupertinoPageTransitionsBuilder()}),
  );
}
