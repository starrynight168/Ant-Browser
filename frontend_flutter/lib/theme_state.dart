import 'package:flutter/foundation.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

final appThemeMode = ValueNotifier<prism.ThemeMode>(prism.ThemeMode.light);
final appThemeColor = ValueNotifier<int>(0xFF426958);

void setAppThemeMode(String value) {
  appThemeMode.value = switch (value) {
    'dark' => prism.ThemeMode.dark,
    'system' => prism.ThemeMode.system,
    _ => prism.ThemeMode.light,
  };
}

void setAppThemeColor(String value) {
  appThemeColor.value = switch (value) {
    'ocean' => 0xFF2563EB,
    'violet' => 0xFF7C3AED,
    'rose' => 0xFFDB2777,
    'amber' => 0xFFD97706,
    'teal' => 0xFF0F766E,
    'slate' => 0xFF475569,
    'red' => 0xFFDC2626,
    _ => 0xFF426958,
  };
}
