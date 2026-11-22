import 'package:flutter/widgets.dart';
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
