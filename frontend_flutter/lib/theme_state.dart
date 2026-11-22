import 'package:flutter/foundation.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

final appThemeMode = ValueNotifier<prism.ThemeMode>(prism.ThemeMode.light);

void setAppThemeMode(String value) {
  appThemeMode.value = switch (value) {
    'dark' => prism.ThemeMode.dark,
    'system' => prism.ThemeMode.system,
    _ => prism.ThemeMode.light,
  };
}
