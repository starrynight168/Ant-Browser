import 'package:material_ui/material_ui.dart';

final appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

void setAppThemeMode(String value) {
  appThemeMode.value = switch (value) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };
}
