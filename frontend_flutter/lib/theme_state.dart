import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

final appThemeMode = ValueNotifier<prism.ThemeMode>(prism.ThemeMode.light);
final appThemeColor = ValueNotifier<int>(0xFF426958);
final appThemeStyle = ValueNotifier<prism.ColorStyle>(prism.ColorStyle.tinted);

const appThemeColorOptions = <({String id, String label, int hex})>[
  (id: 'forest', label: '森林绿', hex: 0xFF426958),
  (id: 'ocean', label: '海洋蓝', hex: 0xFF2563EB),
  (id: 'violet', label: '薰衣草紫', hex: 0xFF7C3AED),
  (id: 'rose', label: '玫瑰粉', hex: 0xFFDB2777),
  (id: 'amber', label: '琥珀橙', hex: 0xFFD97706),
  (id: 'teal', label: '青碧色', hex: 0xFF0F766E),
  (id: 'slate', label: '石墨灰', hex: 0xFF475569),
  (id: 'red', label: '中国红', hex: 0xFFDC2626),
];

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

void setAppThemeStyle(String value) {
  appThemeStyle.value = switch (value) {
    'vivid' => prism.ColorStyle.vivid,
    'soft' => prism.ColorStyle.soft,
    'monochrome' => prism.ColorStyle.monochrome,
    _ => prism.ColorStyle.tinted,
  };
}
