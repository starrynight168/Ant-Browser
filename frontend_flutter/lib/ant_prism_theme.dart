import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

prism.ThemeData buildAntPrismTheme(
  Brightness brightness,
  int seedColor, [
  prism.ColorStyle style = prism.ColorStyle.tinted,
]) {
  return prism.ThemeData(
    colorScheme: prism.ColorScheme.fromSeed(
      seedColor: Color(seedColor),
      brightness: brightness,
      style: style,
    ),
    platform: TargetPlatform.windows,
  );
}
