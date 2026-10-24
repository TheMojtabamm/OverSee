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

  // "Harbor": calm teal on soft blue-grey. Same names as before so every screen follows.
  static const dark = AppColors(
    brand: Color(0xFF3BC4B6),
    brandSoft: Color(0x213BC4B6),
    good: Color(0xFF4CC98A),
    warn: Color(0xFFE3A13B),
    bad: Color(0xFFF06A60),
    surfaceHigh: Color(0xFF1C2A35),
    outline: Color(0xFF22323E),
    muted: Color(0xFF8A9EAC),
    heroGlow: LinearGradient(colors: [Color(0x00000000), Color(0x00000000)]),
  );

  static const light = AppColors(
    brand: Color(0xFF0B7A75),
    brandSoft: Color(0x210B7A75),
    good: Color(0xFF1B8A4D),
    warn: Color(0xFFAE6800),
    bad: Color(0xFFC2362F),
    surfaceHigh: Color(0xFFE8EEF2),
    outline: Color(0xFFDCE4EA),
    muted: Color(0xFF5C6F7E),
    heroGlow: LinearGradient(colors: [Color(0x00FFFFFF), Color(0x00FFFFFF)]),
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

  static const _radius = 18.0;
  static const font = "Sora";

  static ThemeData dark() => _build(Brightness.dark, AppColors.dark,
      bg: const Color(0xFF0B141B),
      surface: const Color(0xFF131F29),
      text: const Color(0xFFE4EDF2));

  static ThemeData light() => _build(Brightness.light, AppColors.light,
      bg: const Color(0xFFF2F5F7),
      surface: Colors.white,
      text: const Color(0xFF0F2230));

  static ThemeData _build(Brightness b, AppColors c,
      {required Color bg, required Color surface, required Color text}) {
    final scheme =
        ColorScheme.fromSeed(seedColor: c.brand, brightness: b).copyWith(
      primary: c.brand,
      onPrimary: b == Brightness.dark ? const Color(0xFF032220) : Colors.white,
      surface: surface,
      onSurface: text,
      error: c.bad,
      outline: c.outline,
      surfaceContainerHighest: c.surfaceHigh,
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final base = ThemeData(brightness: b, useMaterial3: true, fontFamily: font);
    // A button's textStyle REPLACES the default label style (it does not inherit the
    // ambient font), so derive ours from the platform text theme instead of from nothing.
    final label = base.textTheme.labelLarge!;
    return ThemeData(
      useMaterial3: true,
      fontFamily: font,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontFamily: font,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: text),
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
          minimumSize: const Size.fromHeight(48),
          shape: shape,
          textStyle: label.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
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
        height: 66,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
            fontFamily: font,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: st.contains(WidgetState.selected) ? c.brand : c.muted)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? c.brand : c.muted,
            size: 24)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
            fontFamily: font,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: text),
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
        contentTextStyle: TextStyle(fontFamily: font, color: text),
        shape: shape,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? c.brand : c.surfaceHigh),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? c.brand : c.outline),
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
