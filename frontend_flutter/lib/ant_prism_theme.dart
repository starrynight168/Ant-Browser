import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

prism.ThemeData buildAntPrismTheme(Brightness brightness, int seedColor) {
  return prism.ThemeData(
    colorScheme: prism.ColorScheme.fromSeed(
      seedColor: Color(seedColor),
      brightness: brightness,
      style: prism.ColorStyle.tinted,
    ),
    platform: TargetPlatform.windows,
  );
}
