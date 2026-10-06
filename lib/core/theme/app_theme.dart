import 'package:flutter/material.dart';

/// Layout constants, ported 1:1 from the Swift app's `FishLogMetrics`.
abstract final class Metrics {
  static const double cardCornerRadius = 20;
  static const double controlCornerRadius = 14;
  static const double cardSpacing = 12;
  static const double sectionSpacing = 16;
  static const double heroHeight = 320;
  static const double thumbnailSize = 64;

  /// Content stops growing past this on wide screens (web/tablet); the page centers instead
  /// of stretching a phone layout across a 2000px window.
  static const double maxContentWidth = 720;

  /// Width of a row inside a list that already has 16 px side padding, so rows line up with
  /// the [ContentColumn] above them (which is `maxContentWidth` including that padding).
  static const double listItemMaxWidth = maxContentWidth - 32;
}

/// The app's own palette, carried over from the Swift asset catalog.
///
/// `currentWater`'s dark value is deliberately lighter than the original's: the Swift
/// asset used a *darker* teal in dark mode (≈#123C42), which on the dark surfaces it sits
/// on measures roughly 1.2:1 — icons and chart bars were effectively invisible. This keeps
/// the hue and lifts the lightness so it reads on dark (≈7:1).
@immutable
class FishLogColors extends ThemeExtension<FishLogColors> {
  const FishLogColors({
    required this.shallows,
    required this.lureAccent,
    required this.abyss,
    required this.currentWater,
    required this.trophy,
  });

  final Color shallows;
  final Color lureAccent;
  final Color abyss;
  final Color currentWater;
  final Color trophy;

  static const light = FishLogColors(
    shallows: Color(0xFFD9F2EF),
    lureAccent: Color(0xFFFF7A30),
    abyss: Color(0xFF0F2E36),
    currentWater: Color(0xFF1E6E77),
    trophy: Color(0xFFE0A400),
  );

  static const dark = FishLogColors(
    shallows: Color(0xFF102A2C),
    lureAccent: Color(0xFFFF9457),
    abyss: Color(0xFF04141A),
    currentWater: Color(0xFF5BBEC9),
    trophy: Color(0xFFFFC53D),
  );

  @override
  FishLogColors copyWith({Color? shallows, Color? lureAccent, Color? abyss, Color? currentWater, Color? trophy}) =>
      FishLogColors(
        shallows: shallows ?? this.shallows,
        lureAccent: lureAccent ?? this.lureAccent,
        abyss: abyss ?? this.abyss,
        currentWater: currentWater ?? this.currentWater,
        trophy: trophy ?? this.trophy,
      );

  @override
  FishLogColors lerp(ThemeExtension<FishLogColors>? other, double t) {
    if (other is! FishLogColors) return this;
    return FishLogColors(
      shallows: Color.lerp(shallows, other.shallows, t)!,
      lureAccent: Color.lerp(lureAccent, other.lureAccent, t)!,
      abyss: Color.lerp(abyss, other.abyss, t)!,
      currentWater: Color.lerp(currentWater, other.currentWater, t)!,
      trophy: Color.lerp(trophy, other.trophy, t)!,
    );
  }
}

extension FishLogThemeContext on BuildContext {
  FishLogColors get fish => Theme.of(this).extension<FishLogColors>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

/// Type roles, mapped from the Swift `fishLog*` fonts onto Material text styles.
extension FishLogText on TextTheme {
  TextStyle get fishHero => headlineSmall!.copyWith(fontWeight: FontWeight.w800);
  TextStyle get fishTitle => titleLarge!.copyWith(fontWeight: FontWeight.w700);
  TextStyle get fishHeadline => titleMedium!.copyWith(fontWeight: FontWeight.w600);
  TextStyle get fishBody => bodyLarge!;
  TextStyle get fishCaption => bodySmall!.copyWith(fontWeight: FontWeight.w500);
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final fish = isDark ? FishLogColors.dark : FishLogColors.light;

    final seeded = ColorScheme.fromSeed(
      seedColor: FishLogColors.light.currentWater,
      brightness: brightness,
    );

    final scheme = seeded.copyWith(
      primary: fish.currentWater,
      onPrimary: isDark ? fish.abyss : Colors.white,
      primaryContainer: fish.shallows,
      onPrimaryContainer: isDark ? const Color(0xFFD9F2EF) : fish.abyss,
      secondary: fish.currentWater,
      tertiary: fish.lureAccent,
      onTertiary: fish.abyss,
      tertiaryContainer: fish.lureAccent.withValues(alpha: isDark ? 0.25 : 0.18),
      onTertiaryContainer: isDark ? const Color(0xFFFFE0CC) : const Color(0xFF5A2200),
      surface: isDark ? const Color(0xFF0A1A1E) : const Color(0xFFF4F9F9),
      onSurface: isDark ? const Color(0xFFE3EFF0) : const Color(0xFF0E2328),
      surfaceContainerLowest: isDark ? const Color(0xFF071317) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF0F2429) : const Color(0xFFFFFFFF),
      surfaceContainer: isDark ? const Color(0xFF13292E) : const Color(0xFFEAF3F3),
      surfaceContainerHigh: isDark ? const Color(0xFF193137) : const Color(0xFFE2EDED),
      onSurfaceVariant: isDark ? const Color(0xFFA9C0C3) : const Color(0xFF45595D),
      outlineVariant: isDark ? const Color(0xFF2A4247) : const Color(0xFFCADADB),
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Metrics.controlCornerRadius));

    return base.copyWith(
      extensions: [fish],
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge!.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Metrics.cardCornerRadius)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: fish.lureAccent,
        foregroundColor: fish.abyss,
        extendedTextStyle: base.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: fish.lureAccent,
          foregroundColor: fish.abyss,
          shape: shape,
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape, minimumSize: const Size(48, 44))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Metrics.controlCornerRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Metrics.controlCornerRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Metrics.controlCornerRadius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: fish.shallows,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: fish.shallows,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Metrics.controlCornerRadius)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: fish.shallows,
          selectedForegroundColor: scheme.onPrimaryContainer,
          visualDensity: VisualDensity.compact,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 4)),
    );
  }
}
