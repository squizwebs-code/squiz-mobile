import 'package:flutter/material.dart';

/// The one brand colour. Used as `primary` in BOTH the light and the dark theme.
const Color kBrand = Color(0xFF428BCA);

/// Text/icon colour on top of [kBrand] fills (buttons, hero card).
/// White on #428bca has a 3.6:1 contrast ratio: fine for the bold 16sp+ labels used here (WCAG "large text" needs 3:1)
/// but below 4.5:1 for small body text, so [kBrand] is never used for small text on white.
/// If you need AA for every label, switch this to `Color(0xFF04182B)` (4.9:1) - one line, whole app follows.
const Color kOnBrand = Colors.white;

/// A darker blue of the same hue for small text/links on the LIGHT background (6.3:1 on white).
const Color kBrandInkLight = Color(0xFF2A6496);

/// Depth variants for gradients.
const Color kBrandDeep = Color(0xFF2E6AA3);
const Color kBrandBright = Color(0xFF6FA8DC);

/// Semantic colours (not brand): correct / wrong / warning.
const Color kGood = Color(0xFF2E9E6B);
const Color kBad = Color(0xFFD64545);
const Color kWarn = Color(0xFFE0A030);

/// Subject accents. Kept inside a cool, blue-leaning range so the UI reads as one brand.
const Map<String, Color> kSubjectColor = {
  'math': Color(0xFF428BCA),
  'physics': Color(0xFF5B6FD6),
  'chemistry': Color(0xFF2FA4A9),
  'biology': Color(0xFF3FA66B),
  'english': Color(0xFF8A63D2),
  'geography': Color(0xFF2E93C9),
  'history': Color(0xFFC0803A),
  'economics': Color(0xFF3C7DB5),
  'agriculture': Color(0xFF6BA03A),
  'it': Color(0xFF4F6BA8),
};

const Map<String, IconData> kSubjectIcon = {
  'math': Icons.calculate_rounded,
  'physics': Icons.bolt_rounded,
  'chemistry': Icons.science_rounded,
  'biology': Icons.biotech_rounded,
  'english': Icons.menu_book_rounded,
  'geography': Icons.public_rounded,
  'history': Icons.account_balance_rounded,
  'economics': Icons.trending_up_rounded,
  'agriculture': Icons.grass_rounded,
  'it': Icons.computer_rounded,
};

Color subjectColor(String id) => kSubjectColor[id] ?? kBrand;
IconData subjectIcon(String id) => kSubjectIcon[id] ?? Icons.menu_book_rounded;
