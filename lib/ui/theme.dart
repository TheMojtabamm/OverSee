import "package:flutter/material.dart";

/// Brand + status colours that Material's ColorScheme has no slot for.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color brand;
  final Color brandSoft;
  final Color good;
  final Color warn;
  final Color bad;
  final Color surfaceHigh;
  final Color outline;
  final Color muted;
  final Gradient heroGlow;

  const AppColors({
    required this.brand,
    required this.brandSoft,
    required this.good,
    required this.warn,
    required this.bad,
    required this.surfaceHigh,
    required this.outline,
    required this.muted,
    required this.heroGlow,
  });

  static const _teal = Color(0xFF2DD4BF);

  static const dark = AppColors(
    brand: _teal,
    brandSoft: Color(0x262DD4BF),
    good: Color(0xFF34D399),
    warn: Color(0xFFFBBF24),
    bad: Color(0xFFF87171),
    surfaceHigh: Color(0xFF18232D),
    outline: Color(0xFF243241),
    muted: Color(0xFF8A9BAA),
    heroGlow: RadialGradient(
      center: Alignment(0, -0.4),
      radius: 0.9,
      colors: [Color(0x332DD4BF), Color(0x00000000)],
    ),
  );

  static const light = AppColors(
    brand: Color(0xFF0D9488),
    brandSoft: Color(0x1A0D9488),
    good: Color(0xFF059669),
    warn: Color(0xFFD97706),
    bad: Color(0xFFDC2626),
    surfaceHigh: Color(0xFFEAF0F5),
    outline: Color(0xFFD5DEE7),
    muted: Color(0xFF5D6F80),
    heroGlow: RadialGradient(
      center: Alignment(0, -0.4),
      radius: 0.9,
      colors: [Color(0x260D9488), Color(0x00FFFFFF)],
    ),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < 0.5 ? this : (other as AppColors? ?? this);
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

class AppTheme {
  AppTheme._();

  static const _radius = 20.0;

  static ThemeData dark() => _build(Brightness.dark, AppColors.dark,
      bg: const Color(0xFF0B1117),
      surface: const Color(0xFF121A22),
      text: const Color(0xFFE6EEF5));

  static ThemeData light() => _build(Brightness.light, AppColors.light,
      bg: const Color(0xFFF4F7FA),
      surface: Colors.white,
      text: const Color(0xFF0F1B26));

  static ThemeData _build(Brightness b, AppColors c,
      {required Color bg, required Color surface, required Color text}) {
    final scheme =
        ColorScheme.fromSeed(seedColor: c.brand, brightness: b).copyWith(
      primary: c.brand,
      onPrimary: b == Brightness.dark ? const Color(0xFF04201C) : Colors.white,
      surface: surface,
      onSurface: text,
      error: c.bad,
      outline: c.outline,
      surfaceContainerHighest: c.surfaceHigh,
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    // A button's textStyle REPLACES the default label style (it does not inherit the
    // ambient font), so derive ours from the platform text theme instead of from nothing.
    final label =
        ThemeData(brightness: b, useMaterial3: true).textTheme.labelLarge!;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle:
            TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: c.outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.outline, space: 1, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          textStyle: label.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          side: BorderSide(color: c.outline),
          textStyle: label.copyWith(fontWeight: FontWeight.w500, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            shape: shape,
            textStyle: label.copyWith(fontWeight: FontWeight.w500)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c.brand, width: 1.5)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 68,
        indicatorColor: c.brandSoft,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: c.muted)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? c.brand : c.muted,
            size: 24)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle:
            TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceHigh,
        contentTextStyle: TextStyle(color: text),
        shape: shape,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.onPrimary : c.muted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.brand : c.surfaceHigh),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.brand : c.outline),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStatePropertyAll(BorderSide(color: c.outline)),
          backgroundColor: WidgetStateProperty.resolveWith((st) =>
              st.contains(WidgetState.selected)
                  ? c.brandSoft
                  : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
              (st) => st.contains(WidgetState.selected) ? c.brand : c.muted),
        ),
      ),
      listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    );
  }
}
