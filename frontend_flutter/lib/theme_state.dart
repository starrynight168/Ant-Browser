import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

final appThemeMode = ValueNotifier<prism.ThemeMode>(prism.ThemeMode.light);
final appThemeColor = ValueNotifier<int>(0xFF426958);
final appThemeStyle = ValueNotifier<prism.ColorStyle>(prism.ColorStyle.tinted);
final appMotionIntensity = ValueNotifier<int>(100);
final appMotionEnabled = ValueNotifier<bool>(true);

const int kMinMotionIntensity = 0;
const int kDefaultMotionIntensity = 100;
const int kMaxMotionIntensity = 250;
int appLastNonZeroMotionIntensity = kDefaultMotionIntensity;

void setAppMotionIntensity(num? value) {
  final next = (value?.round() ?? kDefaultMotionIntensity).clamp(
    kMinMotionIntensity,
    kMaxMotionIntensity,
  );
  if (next > 0) {
    appLastNonZeroMotionIntensity = next;
  }
  if (appMotionIntensity.value != next) {
    appMotionIntensity.value = next;
  }
  final enabled = next > 0;
  if (appMotionEnabled.value != enabled) {
    appMotionEnabled.value = enabled;
  }
}

/// 全局动效规格快照：由 [appMotionIntensity]（0% – 250%）驱动。
/// - `0%`：完全关闭动效；
/// - `100%`：默认推荐的 1.25× 桌面甜点档位；
/// - `250%`：极限反例级夸张幅度。
class PrismMotionSpec {
  const PrismMotionSpec({
    required this.enabled,
    required this.springCurve,
    required this.liftCurve,
    required this.smoothCurve,
    required this.pageDuration,
    required this.barDuration,
    required this.staggerDuration,
    required this.staggerStepMs,
    required this.staggerMaxIndex,
    required this.staggerOffsetX,
    required this.staggerOffsetY,
    required this.staggerScaleDelta,
    required this.staggerTilt,
    required this.pageExitY,
    required this.pageExitScaleDelta,
    required this.pageExitTilt,
    required this.pageEnterY,
    required this.pageEnterScaleDelta,
    required this.pageEnterTilt,
    required this.barExitX,
    required this.barExitScaleDelta,
    required this.barEnterX,
    required this.barEnterScaleDelta,
    required this.hoverDuration,
    required this.hoverLiftY,
    required this.hoverScaleDelta,
    required this.hoverTilt,
    required this.hoverShadowBlur,
    required this.hoverShadowOffsetY,
    required this.hoverShadowDarkAlpha,
    required this.hoverShadowLightAlpha,
    required this.hoverRimWidth,
    required this.hoverRimAlpha,
    required this.railDuration,
    required this.railNudgePx,
    required this.railPaddingDuration,
    required this.hoverScaleFactor,
    required this.pressScaleFactor,
    required this.motionReleaseDuration,
    required this.badgeDuration,
    required this.badgeScaleDelta,
    required this.badgeTilt,
    required this.collapsibleDuration,
  });

  final bool enabled;
  final Curve springCurve;
  final Curve liftCurve;
  final Curve smoothCurve;
  final Duration pageDuration;
  final Duration barDuration;
  final Duration staggerDuration;
  final int staggerStepMs;
  final int staggerMaxIndex;
  final double staggerOffsetX;
  final double staggerOffsetY;
  final double staggerScaleDelta;
  final double staggerTilt;
  final double pageExitY;
  final double pageExitScaleDelta;
  final double pageExitTilt;
  final double pageEnterY;
  final double pageEnterScaleDelta;
  final double pageEnterTilt;
  final double barExitX;
  final double barExitScaleDelta;
  final double barEnterX;
  final double barEnterScaleDelta;
  final Duration hoverDuration;
  final double hoverLiftY;
  final double hoverScaleDelta;
  final double hoverTilt;
  final double hoverShadowBlur;
  final double hoverShadowOffsetY;
  final double hoverShadowDarkAlpha;
  final double hoverShadowLightAlpha;
  final double hoverRimWidth;
  final double hoverRimAlpha;
  final Duration railDuration;
  final double railNudgePx;
  final Duration railPaddingDuration;
  final double hoverScaleFactor;
  final double pressScaleFactor;
  final Duration motionReleaseDuration;
  final Duration badgeDuration;
  final double badgeScaleDelta;
  final double badgeTilt;
  final Duration collapsibleDuration;

  static PrismMotionSpec get current => of(appMotionIntensity.value);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static int _lerpInt(int a, int b, double t) => (a + (b - a) * t).round();

  static PrismMotionSpec of(int rawIntensity) {
    final intensity = rawIntensity.clamp(
      kMinMotionIntensity,
      kMaxMotionIntensity,
    );
    if (intensity <= 0) {
      return const PrismMotionSpec(
        enabled: false,
        springCurve: Curves.linear,
        liftCurve: Curves.linear,
        smoothCurve: Curves.linear,
        pageDuration: Duration.zero,
        barDuration: Duration.zero,
        staggerDuration: Duration.zero,
        staggerStepMs: 0,
        staggerMaxIndex: 0,
        staggerOffsetX: 0,
        staggerOffsetY: 0,
        staggerScaleDelta: 0,
        staggerTilt: 0,
        pageExitY: 0,
        pageExitScaleDelta: 0,
        pageExitTilt: 0,
        pageEnterY: 0,
        pageEnterScaleDelta: 0,
        pageEnterTilt: 0,
        barExitX: 0,
        barExitScaleDelta: 0,
        barEnterX: 0,
        barEnterScaleDelta: 0,
        hoverDuration: Duration.zero,
        hoverLiftY: 0,
        hoverScaleDelta: 0,
        hoverTilt: 0,
        hoverShadowBlur: 0,
        hoverShadowOffsetY: 0,
        hoverShadowDarkAlpha: 0,
        hoverShadowLightAlpha: 0,
        hoverRimWidth: 0,
        hoverRimAlpha: 0,
        railDuration: Duration.zero,
        railNudgePx: 0,
        railPaddingDuration: Duration.zero,
        hoverScaleFactor: 0,
        pressScaleFactor: 0,
        motionReleaseDuration: Duration.zero,
        badgeDuration: Duration.zero,
        badgeScaleDelta: 0,
        badgeTilt: 0,
        collapsibleDuration: Duration.zero,
      );
    }

    if (intensity <= 100) {
      final u = intensity / 100.0;
      return PrismMotionSpec(
        enabled: true,
        springCurve: Cubic(
          _lerp(0.22, 0.29, u),
          _lerp(1.0, 1.52, u),
          _lerp(0.36, 0.42, u),
          1.0,
        ),
        liftCurve: Cubic(
          _lerp(0.22, 0.23, u),
          _lerp(1.0, 1.28, u),
          0.36,
          1.0,
        ),
        smoothCurve: const Cubic(0.22, 1.0, 0.36, 1.0),
        pageDuration: Duration(milliseconds: _lerpInt(120, 540, u)),
        barDuration: Duration(milliseconds: _lerpInt(100, 440, u)),
        staggerDuration: Duration(milliseconds: _lerpInt(120, 540, u)),
        staggerStepMs: _lerpInt(0, 65, u),
        staggerMaxIndex: _lerpInt(0, 4, u),
        staggerOffsetX: _lerp(0, 13.0, u),
        staggerOffsetY: _lerp(0, 33.0, u),
        staggerScaleDelta: _lerp(0, 0.05, u),
        staggerTilt: _lerp(0, 0.012, u),
        pageExitY: _lerp(0, 22.0, u),
        pageExitScaleDelta: _lerp(0, 0.04, u),
        pageExitTilt: _lerp(0, 0.008, u),
        pageEnterY: _lerp(0, 40.0, u),
        pageEnterScaleDelta: _lerp(0, 0.05, u),
        pageEnterTilt: _lerp(0, 0.010, u),
        barExitX: _lerp(0, 17.0, u),
        barExitScaleDelta: _lerp(0, 0.05, u),
        barEnterX: _lerp(0, 42.0, u),
        barEnterScaleDelta: _lerp(0, 0.06, u),
        hoverDuration: Duration(milliseconds: _lerpInt(100, 250, u)),
        hoverLiftY: _lerp(0, 3.8, u),
        hoverScaleDelta: _lerp(0, 0.010, u),
        hoverTilt: 0.0,
        hoverShadowBlur: _lerp(0, 34.0, u),
        hoverShadowOffsetY: _lerp(0, 12.0, u),
        hoverShadowDarkAlpha: _lerp(0, 0.50, u),
        hoverShadowLightAlpha: _lerp(0, 0.16, u),
        hoverRimWidth: _lerp(0.8, 1.8, u),
        hoverRimAlpha: _lerp(0, 0.50, u),
        railDuration: Duration(milliseconds: _lerpInt(100, 440, u)),
        railNudgePx: _lerp(0, 8.0, u),
        railPaddingDuration: Duration(milliseconds: _lerpInt(80, 260, u)),
        hoverScaleFactor: u,
        pressScaleFactor: u,
        motionReleaseDuration: Duration(milliseconds: _lerpInt(80, 260, u)),
        badgeDuration: Duration(milliseconds: _lerpInt(100, 390, u)),
        badgeScaleDelta: _lerp(0, 0.35, u),
        badgeTilt: _lerp(0, 0.05, u),
        collapsibleDuration: Duration(milliseconds: _lerpInt(120, 360, u)),
      );
    }

    final u = (intensity - 100) / 150.0;
    return PrismMotionSpec(
      enabled: true,
      springCurve: Cubic(
        _lerp(0.29, 0.34, u),
        _lerp(1.52, 2.25, u),
        0.42,
        1.0,
      ),
      liftCurve: Cubic(
        _lerp(0.23, 0.28, u),
        _lerp(1.28, 1.85, u),
        _lerp(0.36, 0.38, u),
        1.0,
      ),
      smoothCurve: const Cubic(0.22, 1.0, 0.36, 1.0),
      pageDuration: Duration(milliseconds: _lerpInt(540, 1050, u)),
      barDuration: Duration(milliseconds: _lerpInt(440, 850, u)),
      staggerDuration: Duration(milliseconds: _lerpInt(540, 1100, u)),
      staggerStepMs: _lerpInt(65, 160, u),
      staggerMaxIndex: _lerpInt(4, 8, u),
      staggerOffsetX: _lerp(13.0, 42.0, u),
      staggerOffsetY: _lerp(33.0, 96.0, u),
      staggerScaleDelta: _lerp(0.05, 0.16, u),
      staggerTilt: _lerp(0.012, 0.035, u),
      pageExitY: _lerp(22.0, 90.0, u),
      pageExitScaleDelta: _lerp(0.04, 0.12, u),
      pageExitTilt: _lerp(0.008, 0.025, u),
      pageEnterY: _lerp(40.0, 130.0, u),
      pageEnterScaleDelta: _lerp(0.05, 0.14, u),
      pageEnterTilt: _lerp(0.010, 0.030, u),
      barExitX: _lerp(17.0, 48.0, u),
      barExitScaleDelta: _lerp(0.05, 0.12, u),
      barEnterX: _lerp(42.0, 140.0, u),
      barEnterScaleDelta: _lerp(0.06, 0.18, u),
      hoverDuration: Duration(milliseconds: _lerpInt(250, 360, u)),
      hoverLiftY: _lerp(3.8, 8.0, u),
      hoverScaleDelta: _lerp(0.010, 0.035, u),
      hoverTilt: _lerp(0.0, 0.006, u),
      hoverShadowBlur: _lerp(34.0, 60.0, u),
      hoverShadowOffsetY: _lerp(12.0, 20.0, u),
      hoverShadowDarkAlpha: _lerp(0.50, 0.68, u),
      hoverShadowLightAlpha: _lerp(0.16, 0.28, u),
      hoverRimWidth: _lerp(1.8, 3.2, u),
      hoverRimAlpha: _lerp(0.50, 0.92, u),
      railDuration: Duration(milliseconds: _lerpInt(440, 820, u)),
      railNudgePx: _lerp(8.0, 22.0, u),
      railPaddingDuration: Duration(milliseconds: _lerpInt(260, 420, u)),
      hoverScaleFactor: _lerp(1.0, 0.15 / 0.056, u),
      pressScaleFactor: _lerp(1.0, 0.18 / 0.075, u),
      motionReleaseDuration: Duration(milliseconds: _lerpInt(260, 420, u)),
      badgeDuration: Duration(milliseconds: _lerpInt(390, 700, u)),
      badgeScaleDelta: _lerp(0.35, 0.85, u),
      badgeTilt: _lerp(0.05, 0.18, u),
      collapsibleDuration: Duration(milliseconds: _lerpInt(360, 620, u)),
    );
  }
}

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

String get currentAppThemeModeId => switch (appThemeMode.value) {
  prism.ThemeMode.dark => 'dark',
  prism.ThemeMode.system => 'system',
  prism.ThemeMode.light => 'light',
};

String get currentAppThemeColorId {
  final hex = appThemeColor.value;
  for (final option in appThemeColorOptions) {
    if (option.hex == hex) return option.id;
  }
  return 'forest';
}

String get currentAppThemeStyleId => switch (appThemeStyle.value) {
  prism.ColorStyle.vivid => 'vivid',
  prism.ColorStyle.soft => 'soft',
  prism.ColorStyle.monochrome => 'monochrome',
  prism.ColorStyle.tinted => 'tinted',
};
