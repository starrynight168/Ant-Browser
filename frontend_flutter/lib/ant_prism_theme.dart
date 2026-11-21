import 'package:material_ui/material_ui.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

prism.ThemeData buildAntPrismTheme(Brightness brightness) {
  return prism.ThemeData(
    colorScheme: prism.ColorScheme.fromSeed(
      seedColor: const Color(0xFF426958),
      brightness: brightness,
      style: prism.ColorStyle.tinted,
    ),
    platform: TargetPlatform.windows,
  );
}

ThemeData buildAntMaterialTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF426958),
        brightness: brightness,
        surface: isLight ? const Color(0xFFF4F7F5) : const Color(0xFF111713),
      ).copyWith(
        surfaceContainerLowest: isLight
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF151B17),
        surfaceContainerLow: isLight
            ? const Color(0xFFF0F4F1)
            : const Color(0xFF19211C),
        surfaceContainer: isLight
            ? const Color(0xFFE9EFEB)
            : const Color(0xFF1E2721),
        surfaceContainerHigh: isLight
            ? const Color(0xFFE1E9E4)
            : const Color(0xFF28322C),
        outlineVariant: isLight
            ? const Color(0xFFD8E2DC)
            : const Color(0xFF3B4840),
      );
  final cardShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.circular(24),
    side: BorderSide(color: colors.outlineVariant),
  );
  final buttonShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.circular(18),
  );
  final fieldRadius = BorderRadius.circular(16);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    dividerColor: colors.outlineVariant,
    textTheme: Typography.material2021().black.apply(
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: cardShape,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 10,
      shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(18)),
      iconColor: colors.onSurfaceVariant,
      textColor: colors.onSurface,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(30)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: fieldRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        side: BorderSide(color: colors.outlineVariant),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(56, 42),
        shape: buttonShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.onSurfaceVariant,
        shape: buttonShape,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surfaceContainer,
      side: BorderSide(color: colors.outlineVariant),
      shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(color: colors.onSurfaceVariant),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: TextStyle(color: colors.onInverseSurface),
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(99),
      thickness: const WidgetStatePropertyAll(6),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.hovered)
            ? colors.primary.withValues(alpha: 0.7)
            : colors.outline.withValues(alpha: 0.55);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
