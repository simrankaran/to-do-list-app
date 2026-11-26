import 'package:material_ui/material_ui.dart';

/// Brand color the whole palette is generated from.
const brandSeed = Color(0xFF5B5BD6);

RoundedRectangleBorder _rounded(double radius) =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandSeed,
    brightness: brightness,
  );
  final base = ThemeData(colorScheme: scheme);
  final text = base.textTheme;

  OutlineInputBorder border([
    Color color = Colors.transparent,
    double width = 0,
  ]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: width == 0
        ? BorderSide.none
        : BorderSide(color: color, width: width),
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: text.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: _rounded(18).copyWith(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error, 1),
      focusedErrorBorder: border(scheme.error, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 4,
      highlightElevation: 8,
      shape: _rounded(20),
      extendedTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      visualDensity: VisualDensity.comfortable,
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      showCheckmark: false,
    ),
    listTileTheme: ListTileThemeData(
      shape: _rounded(14),
      selectedColor: scheme.onSecondaryContainer,
      selectedTileColor: scheme.secondaryContainer,
    ),
    dialogTheme: DialogThemeData(shape: _rounded(28)),
    popupMenuTheme: PopupMenuThemeData(shape: _rounded(14)),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: _rounded(14),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 8,
      borderRadius: BorderRadius.circular(8),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
    ),
  );
}
