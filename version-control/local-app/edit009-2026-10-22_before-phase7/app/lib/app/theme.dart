import 'package:flutter/material.dart';

/// Extra colours from the approved mockups (project-mockups/styles.css) that
/// Material's ColorScheme has no slot for.
@immutable
class PjColors extends ThemeExtension<PjColors> {
  const PjColors({
    required this.muted,
    required this.border,
    required this.surface2,
    required this.accentSoft,
    required this.dangerSoft,
    required this.warn,
    required this.warnSoft,
    required this.ok,
  });

  static const light = PjColors(
    muted: Color(0xFF5F6873),
    border: Color(0xFFE2E5EA),
    surface2: Color(0xFFF0F2F5),
    accentSoft: Color(0xFFECEAFD),
    dangerSoft: Color(0xFFFDECEA),
    warn: Color(0xFF9A5B00),
    warnSoft: Color(0xFFFFF4DC),
    ok: Color(0xFF1F8A4C),
  );

  static const dark = PjColors(
    muted: Color(0xFF9AA4B0),
    border: Color(0xFF2A313A),
    surface2: Color(0xFF1F242C),
    accentSoft: Color(0xFF25224A),
    dangerSoft: Color(0xFF3A1F1C),
    warn: Color(0xFFF2B84B),
    warnSoft: Color(0xFF3A2D12),
    ok: Color(0xFF4CC785),
  );

  final Color muted;
  final Color border;
  final Color surface2;
  final Color accentSoft;
  final Color dangerSoft;
  final Color warn;
  final Color warnSoft;
  final Color ok;

  static PjColors of(BuildContext context) => Theme.of(context).extension<PjColors>()!;

  @override
  PjColors copyWith() => this;

  @override
  PjColors lerp(PjColors? other, double t) => t < 0.5 || other == null ? this : other;
}

/// The cover gradients used when a project has no cover image (`.c1`–`.c5`).
const List<List<Color>> coverGradients = [
  [Color(0xFFFCD34D), Color(0xFFF97316)],
  [Color(0xFFA5B4FC), Color(0xFFF0ABFC)],
  [Color(0xFF6EE7B7), Color(0xFF3B82F6)],
  [Color(0xFFFDA4AF), Color(0xFFC084FC)],
  [Color(0xFFCBD5E1), Color(0xFF64748B)],
];

const double _radius = 12;

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final extra = dark ? PjColors.dark : PjColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? const Color(0xFF8B83FF) : const Color(0xFF4F46E5),
    onPrimary: dark ? const Color(0xFF0F1216) : Colors.white,
    secondary: dark ? const Color(0xFF8B83FF) : const Color(0xFF4F46E5),
    onSecondary: dark ? const Color(0xFF0F1216) : Colors.white,
    error: dark ? const Color(0xFFFF7B6E) : const Color(0xFFC2362B),
    onError: Colors.white,
    surface: dark ? const Color(0xFF171B21) : Colors.white,
    onSurface: dark ? const Color(0xFFE8ECF1) : const Color(0xFF1B1F24),
    surfaceContainerHighest: extra.surface2,
    outline: extra.border,
    outlineVariant: extra.border,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0F1216) : const Color(0xFFF6F7F9),
    extensions: [extra],
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0, // The mockups use a border; a flat card also keeps screenshots faithful.
      shape: shape.copyWith(side: BorderSide(color: extra.border)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surface, shape: shape),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: extra.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: buttonShape)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: buttonShape, side: BorderSide(color: extra.border), foregroundColor: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: extra.border)),
      isDense: true,
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: extra.border),
      selectedColor: extra.accentSoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}

/// A red button for destructive actions ("Delete project", "Delete both").
ButtonStyle dangerButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError);
}
