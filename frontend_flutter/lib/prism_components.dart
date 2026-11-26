import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart' as prism_icons;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'prism_glyphs.dart';
import 'theme_state.dart';

/// 全站等宽字体 token：代码块、ID、路径、日志等 mono 文本统一引用，
/// 避免各页面散落硬编码 fontFamily。
const String prismMonoFontFamily = 'Consolas';

/// mono 文本基础样式（12.5/1.5 与 PrismCodeSurface 一致），颜色可选。
TextStyle prismMonoTextStyle({
  double? fontSize,
  double? height,
  Color? color,
}) => TextStyle(
  fontFamily: prismMonoFontFamily,
  fontSize: fontSize ?? 12.5,
  height: height ?? 1.5,
  color: color,
);

enum PrismTone { neutral, primary, success, warning, danger, info }

/// 滚动视口默认留白，避免卡片悬停浮起与高光描边被边缘裁切。
const EdgeInsets kPrismScrollPadding = EdgeInsets.fromLTRB(6, 6, 6, 24);
const EdgeInsets kPrismListPadding = EdgeInsets.fromLTRB(6, 6, 6, 20);

class PrismToneColors {
  const PrismToneColors({
    required this.bg,
    required this.fg,
    required this.border,
  });

  final Color bg;
  final Color fg;
  final Color border;

  static PrismToneColors of(BuildContext context, PrismTone tone) {
    final theme = prism.Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return switch (tone) {
      PrismTone.neutral => PrismToneColors(
        bg: colors.surfaceContainerHighest,
        fg: colors.onSurfaceVariant,
        border: colors.outlineVariant.withValues(alpha: 0.45),
      ),
      PrismTone.primary => PrismToneColors(
        bg: colors.primaryContainer,
        fg: colors.onPrimaryContainer,
        border: colors.primary.withValues(alpha: 0.28),
      ),
      PrismTone.success => PrismToneColors(
        bg: dark ? const Color(0xFF143526) : const Color(0xFFE3F7EC),
        fg: dark ? const Color(0xFF6EE7B7) : const Color(0xFF0E6B42),
        border: (dark ? const Color(0xFF34D399) : const Color(0xFF10B981))
            .withValues(alpha: 0.30),
      ),
      PrismTone.warning => PrismToneColors(
        bg: dark ? const Color(0xFF3B2B11) : const Color(0xFFFEF3DC),
        fg: dark ? const Color(0xFFFCD34D) : const Color(0xFF9A5B06),
        border: (dark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B))
            .withValues(alpha: 0.32),
      ),
      PrismTone.danger => PrismToneColors(
        bg: colors.errorContainer,
        fg: colors.onErrorContainer,
        border: colors.error.withValues(alpha: 0.32),
      ),
      PrismTone.info => PrismToneColors(
        bg: colors.secondaryContainer,
        fg: colors.onSecondaryContainer,
        border: colors.secondary.withValues(alpha: 0.28),
      ),
    };
  }
}

class PrismBadge extends StatelessWidget {
  const PrismBadge({
    super.key,
    required this.label,
    this.tone = PrismTone.neutral,
    this.glyph,
    this.dot = false,
    this.onPressed,
  });

  final String label;
  final PrismTone tone;
  final prism_icons.Glyph? glyph;
  final bool dot;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = PrismToneColors.of(context, tone);
    final content = prism.Surface(
      color: palette.bg,
      shape: prism.AppShape.full,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            if (dot)
              SizedBox(
                width: 7,
                height: 7,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: palette.fg,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
            if (glyph != null)
              prism_icons.GlyphIcon(glyph!, size: 13, color: palette.fg),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: prism.AppTextStyle.caption1
                    .of(context, emphasized: true)
                    .copyWith(color: palette.fg),
              ),
            ),
          ],
        ),
      ),
    );
    if (onPressed == null) return content;
    return PrismHoverMotion(
      hoverScale: 1.04,
      pressScale: 0.95,
      child: prism.PressRegion(
        onTap: onPressed,
        shape: prism.AppShape.full,
        child: content,
      ),
    );
  }
}

class PrismBanner extends StatelessWidget {
  const PrismBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = PrismTone.info,
    this.glyph,
    this.trailing,
  });

  final String? title;
  final String message;
  final PrismTone tone;
  final prism_icons.Glyph? glyph;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = PrismToneColors.of(context, tone);
    final effectiveGlyph =
        glyph ??
        switch (tone) {
          PrismTone.success => AntGlyphs.checkCircle,
          PrismTone.warning => AntGlyphs.warning,
          PrismTone.danger => AntGlyphs.error,
          _ => AntGlyphs.info,
        };
    return prism.Surface(
      color: palette.bg,
      shape: prism.AppShape.lg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            prism_icons.GlyphIcon(effectiveGlyph, size: 18, color: palette.fg),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null && title!.isNotEmpty)
                    Text(
                      title!,
                      style: prism.AppTextStyle.footnote
                          .of(context, emphasized: true)
                          .copyWith(color: palette.fg),
                    ),
                  if (title != null && title!.isNotEmpty)
                    const SizedBox(height: 6),
                  Text(
                    message,
                    style: prism.AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: palette.fg),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 全局页面顶栏（外壳层）：70px 布局条，标题经 PrismBarTransition 弹簧切换，
/// 动作区（快捷启动触发器等）由调用方传入 [trailing]。
/// 页面主体配合页面级 PrismPageContextBar 使用，避免标题重复渲染。
class PrismPageHeader extends StatelessWidget {
  const PrismPageHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: appMotionIntensity,
              builder: (context, child) => AnimatedSwitcher(
                duration: PrismMotionSpec.current.barDuration,
                transitionBuilder: PrismBarTransition.switcherBuilder,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: child!,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                key: ValueKey(title),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: prism.AppTextStyle.pageTitle.of(
                    context,
                    emphasized: true,
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// 页面顶部上下文栏（settings_page 样板）：
/// 左侧 Surface 图标块 + 标题 + 副标题，右侧为页面操作按钮组。
/// 页面主体配合 `EdgeInsets.fromLTRB(24, 6, 24, 24)` 外边距使用，
/// 标题不再重复渲染页面大标题（外壳 PrismPageHeader 已展示）。
class PrismPageContextBar extends StatelessWidget {
  const PrismPageContextBar({
    super.key,
    required this.glyph,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final prism_icons.Glyph glyph;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return PrismStaggerIn(
      index: 0,
      initialDelay: const Duration(milliseconds: 30),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          children: [
            prism.Surface(
              color: colors.primaryContainer,
              shape: prism.AppShape.md,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: prism_icons.GlyphIcon(
                  glyph,
                  size: 20,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: prism.AppTextStyle.title3.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// iOS 弹簧曲线：52% 弹性过冲回弹（1.25× 甜点基线），用于分类胶囊、顶栏滑入、数值徽章、按钮按压。
const Cubic kPrismSpring = Cubic(0.29, 1.52, 0.42, 1.0);

/// iOS 临界阻尼平滑曲线：零过冲减速，用于高度展开与阴影渐变。
const Cubic kPrismSmooth = Cubic(0.22, 1.0, 0.36, 1.0);

/// 轻盈浮起曲线：28% 柔和落位过冲（1.25× 甜点基线），用于整页/卡片纵向位移。
const Cubic kPrismLift = Cubic(0.23, 1.28, 0.36, 1.0);

/// 进场 stagger：受全局 `appMotionIntensity` 实时驱动，支持从 0%（关闭）到 250%（极限）。
class PrismStaggerIn extends StatefulWidget {
  const PrismStaggerIn({
    super.key,
    required this.child,
    this.index = 0,
    this.initialDelay = Duration.zero,
    this.enabled = true,
  });

  final Widget child;
  final int index;
  final Duration initialDelay;
  final bool enabled;

  @override
  State<PrismStaggerIn> createState() => _PrismStaggerInState();
}

class _PrismStaggerInState extends State<PrismStaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PrismMotionSpec.current.staggerDuration,
  );

  @override
  void initState() {
    super.initState();
    final spec = PrismMotionSpec.current;
    if (!widget.enabled || !spec.enabled) {
      _controller.value = 1;
      return;
    }
    _controller.duration = spec.staggerDuration;
    final delay =
        widget.initialDelay +
        Duration(
          milliseconds:
              widget.index.clamp(0, spec.staggerMaxIndex) * spec.staggerStepMs,
        );
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final spec = PrismMotionSpec.current;
        if (!spec.enabled || _controller.value >= 1.0) {
          return child!;
        }
        final v = _controller.value;
        final lift = spec.liftCurve.transform(v);
        final opacity = Curves.easeOut.transform((v / 0.62).clamp(0.0, 1.0));
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(
              (1 - lift) * spec.staggerOffsetX,
              (1 - lift) * spec.staggerOffsetY,
            ),
            child: Transform.scale(
              scale:
                  (1.0 - spec.staggerScaleDelta) +
                  spec.staggerScaleDelta * lift,
              child: Transform.rotate(
                angle: (1 - lift) * spec.staggerTilt,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 悬停高光：统一提供静止细边框；开启 [enabled] 与 [lift] 时叠加悬停高光、抬升与弹簧微缩放。
class PrismHoverGlow extends StatefulWidget {
  const PrismHoverGlow({
    super.key,
    required this.child,
    this.radius = 18,
    this.enabled = true,
    this.lift = true,
  });

  final Widget child;
  final double radius;
  final bool enabled;
  final bool lift;

  @override
  State<PrismHoverGlow> createState() => _PrismHoverGlowState();
}

class _PrismHoverGlowState extends State<PrismHoverGlow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = prism.Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final restingBorderColor = scheme.outlineVariant.withValues(
      alpha: dark ? 0.30 : 0.45,
    );
    final restingShadow = BoxShadow(
      color: dark
          ? const Color(0xFF000000).withValues(alpha: 0.22)
          : const Color(0xFF101828).withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 2),
    );
    final cardShape = RoundedSuperellipseBorder(
      borderRadius: prism.AppRadius.all(widget.radius),
    );
    if (!widget.enabled) {
      return DecoratedBox(
        decoration: ShapeDecoration(shape: cardShape, shadows: [restingShadow]),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(
              borderRadius: prism.AppRadius.all(widget.radius),
              side: BorderSide(color: restingBorderColor, width: 1.0),
            ),
          ),
          child: widget.child,
        ),
      );
    }
    return ListenableBuilder(
      listenable: appMotionIntensity,
      child: widget.child,
      builder: (context, child) {
        final spec = PrismMotionSpec.current;
        final activeHover = spec.enabled && _hover;
        final activeLift = widget.lift && activeHover;
        // 保持子树结构恒定，避免开关动效瞬间卸载重建子组件导致拖动中断。
        final decorated = AnimatedContainer(
          duration: spec.enabled ? spec.hoverDuration : Duration.zero,
          curve: spec.enabled ? spec.smoothCurve : Curves.linear,
          decoration: ShapeDecoration(
            shape: cardShape,
            shadows: [
              BoxShadow(
                color: dark
                    ? const Color(0xFF000000).withValues(
                        alpha: activeLift ? spec.hoverShadowDarkAlpha : 0.22,
                      )
                    : const Color(0xFF101828).withValues(
                        alpha: activeLift ? spec.hoverShadowLightAlpha : 0.05,
                      ),
                blurRadius: activeLift ? spec.hoverShadowBlur : 10,
                offset: activeLift
                    ? Offset(0, spec.hoverShadowOffsetY)
                    : const Offset(0, 2),
              ),
            ],
          ),
          foregroundDecoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(
              borderRadius: prism.AppRadius.all(widget.radius),
              side: BorderSide(
                color: activeHover
                    ? scheme.primary.withValues(alpha: spec.hoverRimAlpha)
                    : restingBorderColor,
                width: activeHover ? spec.hoverRimWidth : 1.0,
              ),
            ),
          ),
          child: child,
        );
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: activeLift ? 1.0 : 0.0),
            duration: spec.enabled ? spec.hoverDuration : Duration.zero,
            curve: spec.enabled ? spec.springCurve : Curves.linear,
            builder: (context, t, inner) => Transform.translate(
              offset: Offset(0, -spec.hoverLiftY * t),
              child: Transform.rotate(
                angle: spec.hoverTilt * t,
                child: Transform.scale(
                  scale: 1.0 + spec.hoverScaleDelta * t,
                  child: inner,
                ),
              ),
            ),
            child: decorated,
          ),
        );
      },
    );
  }
}

/// 值变化弹跳徽章：受全局 `appMotionIntensity` 实时驱动。
class PrismValueBadge extends StatefulWidget {
  const PrismValueBadge({
    super.key,
    required this.value,
    required this.unit,
    this.tone = PrismTone.primary,
  });

  final Object value;
  final String unit;
  final PrismTone tone;

  @override
  State<PrismValueBadge> createState() => _PrismValueBadgeState();
}

class _PrismValueBadgeState extends State<PrismValueBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PrismMotionSpec.current.badgeDuration,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant PrismValueBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final spec = PrismMotionSpec.current;
      if (!spec.enabled) {
        _controller.value = 1;
        return;
      }
      _controller.duration = spec.badgeDuration;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = PrismBadge(
      label: '${widget.value} ${widget.unit}',
      tone: widget.tone,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, appMotionIntensity]),
      child: badge,
      builder: (context, child) {
        final spec = PrismMotionSpec.current;
        if (!spec.enabled || _controller.value >= 1.0) return child!;
        final spring = spec.springCurve.transform(_controller.value);
        return Transform.rotate(
          angle: (1 - spring) * spec.badgeTilt,
          child: Transform.scale(
            scale: (1.0 + spec.badgeScaleDelta) - spec.badgeScaleDelta * spring,
            child: child,
          ),
        );
      },
    );
  }
}

/// 页面/分区切换过渡：受全局 `appMotionIntensity` 实时驱动。
class PrismSlideThroughTransition extends StatelessWidget {
  const PrismSlideThroughTransition({
    super.key,
    required this.primary,
    required this.secondary,
    required this.child,
  });

  final Animation<double> primary;
  final Animation<double> secondary;
  final Widget child;

  /// PageTransitionSwitcher.transitionBuilder 直接可用。
  static Widget builder(
    Widget child,
    Animation<double> primary,
    Animation<double> secondary,
  ) {
    return PrismSlideThroughTransition(
      primary: primary,
      secondary: secondary,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([primary, secondary, appMotionIntensity]),
      child: child,
      builder: (context, child) {
        final spec = PrismMotionSpec.current;
        if (!spec.enabled) {
          return secondary.value > 0 ? const SizedBox.shrink() : child!;
        }
        if (secondary.value > 0) {
          final p = Curves.easeOutCubic
              .transform((secondary.value / 0.25).clamp(0.0, 1.0))
              .clamp(0.0, 1.0);
          return Opacity(
            opacity: 1 - p,
            child: Transform.rotate(
              angle: -spec.pageExitTilt * p,
              child: Transform.scale(
                scale: 1 - spec.pageExitScaleDelta * p,
                child: Transform.translate(
                  offset: Offset(0, -spec.pageExitY * p),
                  child: child,
                ),
              ),
            ),
          );
        }
        final t = ((primary.value - 0.16) / 0.84).clamp(0.0, 1.0);
        final lift = spec.liftCurve.transform(t);
        final fade = Curves.easeOut.transform((t / 0.55).clamp(0.0, 1.0));
        return Opacity(
          opacity: fade,
          child: Transform.rotate(
            angle: (1 - lift) * spec.pageEnterTilt,
            child: Transform.scale(
              scale:
                  (1.0 - spec.pageEnterScaleDelta) +
                  spec.pageEnterScaleDelta * lift,
              child: Transform.translate(
                offset: Offset(0, (1 - lift) * spec.pageEnterY),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 上下文栏切换过渡：受全局 `appMotionIntensity` 实时驱动。
class PrismBarTransition extends StatelessWidget {
  const PrismBarTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  /// PageTransitionSwitcher.transitionBuilder 直接可用。
  static Widget builder(
    Widget child,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return PrismBarTransition(animation: animation, child: child);
  }

  /// AnimatedSwitcher.transitionBuilder（两参签名）直接可用。
  static Widget switcherBuilder(Widget child, Animation<double> animation) {
    return PrismBarTransition(animation: animation, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, appMotionIntensity]),
      child: child,
      builder: (context, child) {
        final spec = PrismMotionSpec.current;
        if (!spec.enabled) {
          return animation.status == AnimationStatus.reverse
              ? const SizedBox.shrink()
              : child!;
        }
        final v = animation.value.clamp(0.0, 1.0);
        if (animation.status == AnimationStatus.reverse) {
          final p = Curves.easeOut
              .transform(((1 - v) / 0.26).clamp(0.0, 1.0))
              .clamp(0.0, 1.0);
          return Opacity(
            opacity: 1 - p,
            child: Transform.scale(
              scale: 1 - spec.barExitScaleDelta * p,
              child: Transform.translate(
                offset: Offset(-spec.barExitX * p, 0),
                child: child,
              ),
            ),
          );
        }
        final t = ((v - 0.16) / 0.84).clamp(0.0, 1.0);
        final spring = spec.springCurve.transform(t);
        final fade = Curves.easeOut.transform((t / 0.51).clamp(0.0, 1.0));
        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale:
                (1.0 - spec.barEnterScaleDelta) +
                spec.barEnterScaleDelta * spring,
            child: Transform.translate(
              offset: Offset((1 - spring) * spec.barEnterX, 0),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// 平滑折叠容器：按 [expanded] 展开或收起子组件（受全局动效强度驱动）。
class PrismCollapsible extends StatelessWidget {
  const PrismCollapsible({
    super.key,
    required this.expanded,
    required this.child,
    this.duration,
    this.curve = kPrismSmooth,
    this.alignment = Alignment.topCenter,
  });

  final bool expanded;
  final Widget child;
  final Duration? duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appMotionIntensity,
      builder: (context, _) {
        final spec = PrismMotionSpec.current;
        return AnimatedSize(
          duration: duration ?? spec.collapsibleDuration,
          curve: spec.enabled ? curve : Curves.linear,
          alignment: alignment,
          child: expanded ? child : const SizedBox.shrink(),
        );
      },
    );
  }
}

/// 滑动胶囊导航栏的数据项定义。
class PrismSlidingRailItem<T> {
  const PrismSlidingRailItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.glyph,
    this.statusTone,
    this.trailing,
    this.sectionHeader,
    this.sectionTrailing,
  });

  final T value;
  final String title;
  final String? subtitle;
  final prism_icons.Glyph? glyph;
  final PrismTone? statusTone;
  final Widget? trailing;
  final String? sectionHeader;
  final String? sectionTrailing;
}

/// 滑动弹簧胶囊导航栏：选中背景与左侧竖向指示条以弹簧轨迹在条目与分组间联动滑动，悬停附带水平微推与下划线分隔。
class PrismSlidingRail<T> extends StatelessWidget {
  const PrismSlidingRail({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    this.itemHeight = 54.0,
    this.gap = 4.0,
    this.showDividers = true,
    this.showSelectionBadge = false,
    this.showSubtitle = false,
    this.sectionHeaderHeight = 34.0,
  });

  final List<PrismSlidingRailItem<T>> items;
  final T selectedValue;
  final ValueChanged<T> onSelected;
  final double itemHeight;
  final double gap;
  final bool showDividers;
  final bool showSelectionBadge;
  final bool showSubtitle;
  final double sectionHeaderHeight;

  double _topOf(int index) {
    var headers = 0;
    for (var i = 0; i <= index && i < items.length; i++) {
      if (items[i].sectionHeader != null) headers++;
    }
    return index * (itemHeight + gap) + headers * sectionHeaderHeight;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = prism.Theme.of(context).colorScheme;
    final rawIndex = items.indexWhere((item) => item.value == selectedValue);
    final activeIndex = rawIndex < 0 ? 0 : rawIndex;
    final indicatorHeight = (itemHeight * 0.42).clamp(16.0, 22.0);

    return ListenableBuilder(
      listenable: appMotionIntensity,
      builder: (context, _) {
        final spec = PrismMotionSpec.current;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: spec.railDuration,
              curve: spec.springCurve,
              left: 0,
              right: 0,
              top: _topOf(activeIndex),
              height: itemHeight,
              child: IgnorePointer(
                child: prism.Surface(
                  color: colors.primaryContainer,
                  shape: prism.AppShape.lg,
                  child: Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [
                      const SizedBox.expand(),
                      PositionedDirectional(
                        start: 4,
                        child: SizedBox(
                          width: 3,
                          height: indicatorHeight,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: colors.primary,
                              shape: prism.AppShape.full,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  if (items[i].sectionHeader != null)
                    SizedBox(
                      height: sectionHeaderHeight,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: PrismSectionDividerHeader(
                          label: items[i].sectionHeader!,
                          trailing: items[i].sectionTrailing,
                          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: itemHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _PrismSlidingRailTile<T>(
                            item: items[i],
                            selected: items[i].value == selectedValue,
                            showSelectionBadge: showSelectionBadge,
                            showSubtitle: showSubtitle,
                            onTap: () => onSelected(items[i].value),
                          ),
                        ),
                        if (showDividers &&
                            i < items.length - 1 &&
                            items[i + 1].sectionHeader == null &&
                            i != activeIndex &&
                            i + 1 != activeIndex)
                          const Positioned(
                            left: 42,
                            right: 10,
                            bottom: 0,
                            child: IgnorePointer(
                              child: prism.Divider(height: 1),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PrismSlidingRailTile<T> extends StatefulWidget {
  const _PrismSlidingRailTile({
    required this.item,
    required this.selected,
    required this.showSelectionBadge,
    required this.showSubtitle,
    required this.onTap,
  });

  final PrismSlidingRailItem<T> item;
  final bool selected;
  final bool showSelectionBadge;
  final bool showSubtitle;
  final VoidCallback onTap;

  @override
  State<_PrismSlidingRailTile<T>> createState() =>
      _PrismSlidingRailTileState<T>();
}

class _PrismSlidingRailTileState<T> extends State<_PrismSlidingRailTile<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final item = widget.item;
    final hasSubtitle = item.subtitle != null && item.subtitle!.isNotEmpty;
    final dotColor = item.statusTone == null
        ? null
        : PrismToneColors.of(context, item.statusTone!).fg;
    final titleColor = widget.selected
        ? colors.onPrimaryContainer
        : colors.onSurface;
    final subtitleColor = widget.selected
        ? colors.onPrimaryContainer.withValues(alpha: 0.78)
        : colors.onSurfaceVariant;

    final spec = PrismMotionSpec.current;
    // 背景与左竖条由外层 Stack 滑动胶囊承担；保留水平轻推，不缩放点击热区以确保命中稳固。
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: prism.PressRegion(
        onTap: widget.onTap,
        shape: prism.AppShape.lg,
        overlay: prism.PressRegion.pressOverlay,
        mouseCursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: spec.enabled
              ? const Duration(milliseconds: 160)
              : Duration.zero,
          curve: Curves.easeOut,
          decoration: ShapeDecoration(
            color: !widget.selected && _hovered
                ? colors.primary.withValues(alpha: 0.06)
                : const Color(0x00000000),
            shape: prism.AppShape.lg,
          ),
          child: AnimatedPadding(
            duration: spec.railPaddingDuration,
            curve: spec.springCurve,
            padding: EdgeInsets.fromLTRB(
              (_hovered || widget.selected)
                  ? 14.0 + spec.railNudgePx * 0.65
                  : 14.0,
              6,
              10,
              6,
            ),
            child: Row(
              children: [
                if (item.glyph != null) ...[
                  PrismGlyph(
                    item.glyph!,
                    size: 18,
                    color: widget.selected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: spec.enabled
                            ? const Duration(milliseconds: 220)
                            : Duration.zero,
                        curve: Curves.easeOut,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.subheadline
                            .of(context, emphasized: widget.selected)
                            .copyWith(color: titleColor),
                        child: Text(item.title),
                      ),
                      if (widget.showSubtitle && hasSubtitle) ...[
                        AnimatedDefaultTextStyle(
                          duration: spec.enabled
                              ? const Duration(milliseconds: 220)
                              : Duration.zero,
                          curve: Curves.easeOut,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: prism.AppTextStyle.caption2
                              .of(context)
                              .copyWith(color: subtitleColor),
                          child: Text(item.subtitle!),
                        ),
                      ],
                    ],
                  ),
                ),
                if (item.trailing != null) ...[
                  const SizedBox(width: 12),
                  item.trailing!,
                ] else if (dotColor != null) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 7,
                    height: 7,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: dotColor,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ),
                ] else if (widget.showSelectionBadge) ...[
                  const SizedBox(width: 8),
                  if (widget.selected)
                    const prism.SelectionBadge(size: 18, tonal: true)
                  else
                    PrismGlyph(
                      AntGlyphs.chevronForward,
                      size: 14,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.45),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!widget.showSubtitle && hasSubtitle) {
      return prism.Tooltip(message: item.subtitle!, child: tile);
    }
    return tile;
  }
}

class PrismSectionCard extends StatelessWidget {
  const PrismSectionCard({
    super.key,
    this.title,
    this.glyph,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.radius = prism.AppCorner.xl,
    this.staggerIndex = 0,
    this.staggerDelay = Duration.zero,
  });

  final String? title;
  final prism_icons.Glyph? glyph;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final int staggerIndex;
  final Duration staggerDelay;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: margin,
        // 悬停高光描边 + 进场 stagger（文字完全静止，不随卡片位移）。
        child: PrismStaggerIn(
          index: staggerIndex,
          initialDelay: staggerDelay,
          child: PrismHoverGlow(
            radius: radius,
            child: prism.Card(
              radius: radius,
              inert: true,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null && title!.isNotEmpty) ...[
                    prism.InfoHeader(
                      info: prism.Info(label: title!, glyph: glyph),
                      actions: actions,
                      padding: const EdgeInsets.fromLTRB(20, 16, 18, 12),
                    ),
                    const prism.Divider(height: 1),
                  ],
                  Padding(padding: padding, child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 具备悬停高光与可选入场编排的通用 Prism 卡片容器。
class PrismHoverCard extends StatelessWidget {
  const PrismHoverCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.radius = prism.AppCorner.xl,
    this.onPressed,
    this.inert,
    this.staggerIndex,
    this.staggerDelay = Duration.zero,
    this.hoverGlow = true,
    this.lift = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final VoidCallback? onPressed;
  final bool? inert;
  final int? staggerIndex;
  final Duration staggerDelay;
  final bool hoverGlow;
  final bool lift;

  @override
  Widget build(BuildContext context) {
    final card = PrismHoverGlow(
      radius: radius,
      enabled: hoverGlow,
      lift: lift,
      child: prism.Card(
        radius: radius,
        onPressed: onPressed,
        inert: inert ?? (onPressed == null),
        padding: padding,
        child: child,
      ),
    );
    return RepaintBoundary(
      child: Padding(
        padding: margin,
        child: staggerIndex != null
            ? PrismStaggerIn(
                index: staggerIndex!,
                initialDelay: staggerDelay,
                child: card,
              )
            : card,
      ),
    );
  }
}

/// 多行分组设置/详情卡片：行间自动插入细分隔线并统一接入悬停与编排动效。
class PrismGroupedCard extends StatelessWidget {
  const PrismGroupedCard({
    super.key,
    required this.children,
    this.radius = prism.AppCorner.xl,
    this.staggerIndex = 0,
    this.staggerDelay = Duration.zero,
    this.hoverGlow = true,
    this.dividerIndent = const EdgeInsets.symmetric(horizontal: 18),
  });

  final List<Widget> children;
  final double radius;
  final int staggerIndex;
  final Duration staggerDelay;
  final bool hoverGlow;
  final EdgeInsetsGeometry dividerIndent;

  @override
  Widget build(BuildContext context) {
    return PrismHoverCard(
      radius: radius,
      padding: EdgeInsets.zero,
      staggerIndex: staggerIndex,
      staggerDelay: staggerDelay,
      hoverGlow: hoverGlow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: dividerIndent,
                child: const prism.Divider(height: 1),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// iOS 分组小标题，带可选项数标注与底部分割线。
class PrismSectionDividerHeader extends StatelessWidget {
  const PrismSectionDividerHeader({
    super.key,
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(10, 12, 10, 6),
  });

  final String label;
  final String? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: prism.AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              if (trailing != null && trailing!.isNotEmpty)
                Text(
                  trailing!,
                  style: prism.AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 5),
          const prism.Divider(height: 1),
        ],
      ),
    );
  }
}

/// iOS 风格目录导航项：左侧主题胶囊选中条、内缩下划线分隔线、原生 SelectionBadge 与平滑弹簧推挤动效。
class PrismNavItem extends StatefulWidget {
  const PrismNavItem({
    super.key,
    required this.label,
    required this.glyph,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.showDivider = false,
    this.showSelectionBadge = false,
  });

  final String label;
  final prism_icons.Glyph glyph;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showDivider;
  final bool showSelectionBadge;

  @override
  State<PrismNavItem> createState() => _PrismNavItemState();
}

class _PrismNavItemState extends State<PrismNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final selected = widget.selected;
    return ListenableBuilder(
      listenable: appMotionIntensity,
      builder: (context, _) {
        final spec = PrismMotionSpec.current;
        final indicatorDuration = spec.enabled
            ? const Duration(milliseconds: 220)
            : Duration.zero;
        final rowStyle = selected
            ? prism.AppTextStyle.subheadline
                  .of(context, emphasized: true)
                  .copyWith(color: colors.onPrimaryContainer)
            : prism.AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colors.onSurface);
        final nudge = (_hovered || selected)
            ? 12.0 + spec.railNudgePx * 0.65
            : 12.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: prism.PressRegion(
                onTap: widget.onTap,
                shape: prism.AppShape.md,
                overlay: prism.PressRegion.pressOverlay,
                mouseCursor: SystemMouseCursors.click,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: AnimatedContainer(
                    duration: spec.enabled
                        ? const Duration(milliseconds: 160)
                        : Duration.zero,
                    curve: Curves.easeOut,
                    decoration: ShapeDecoration(
                      color: selected
                          ? colors.primaryContainer
                          : _hovered
                          ? colors.primary.withValues(alpha: 0.06)
                          : const Color(0x00000000),
                      shape: prism.AppShape.md,
                    ),
                    child: Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [
                        AnimatedPadding(
                          duration: spec.railPaddingDuration,
                          curve: spec.springCurve,
                          padding: EdgeInsets.fromLTRB(nudge, 9, 10, 9),
                          child: Row(
                            children: [
                              PrismGlyph(
                                widget.glyph,
                                size: 17,
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: spec.enabled
                                      ? const Duration(milliseconds: 180)
                                      : Duration.zero,
                                  style: rowStyle,
                                  child: Text(
                                    widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              if (widget.trailing != null) ...[
                                const SizedBox(width: 12),
                                widget.trailing!,
                              ] else if (widget.showSelectionBadge) ...[
                                const SizedBox(width: 12),
                                if (selected)
                                  const prism.SelectionBadge(
                                    size: 18,
                                    tonal: true,
                                  )
                                else
                                  PrismGlyph(
                                    AntGlyphs.chevronForward,
                                    size: 14,
                                    color: colors.onSurfaceVariant.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        PositionedDirectional(
                          start: 3,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: AnimatedOpacity(
                                opacity: selected ? 1.0 : 0.0,
                                duration: indicatorDuration,
                                curve: spec.springCurve,
                                child: AnimatedScale(
                                  scale: selected ? 1.0 : 0.4,
                                  duration: indicatorDuration,
                                  curve: spec.springCurve,
                                  child: SizedBox(
                                    width: 3,
                                    height: 18,
                                    child: DecoratedBox(
                                      decoration: ShapeDecoration(
                                        color: colors.primary,
                                        shape: prism.AppShape.full,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showDivider && !selected)
              const Padding(
                padding: EdgeInsets.only(left: 40, right: 10),
                child: prism.Divider(height: 1),
              ),
          ],
        );
      },
    );
  }
}

class PrismMetricTile extends StatelessWidget {
  const PrismMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.glyph,
    this.tone = PrismTone.primary,
    this.onPressed,
    this.staggerIndex,
    this.staggerDelay = Duration.zero,
    this.showSubtitle = false,
  });

  final String label;
  final String value;
  final String? subtitle;
  final prism_icons.Glyph? glyph;
  final PrismTone tone;
  final VoidCallback? onPressed;
  final int? staggerIndex;
  final Duration staggerDelay;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final palette = PrismToneColors.of(context, tone);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: prism.AppTextStyle.footnote
              .of(context)
              .copyWith(color: colors.onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: prism.AppTextStyle.title3
              .of(context, emphasized: true)
              .copyWith(fontWeight: FontWeight.w700, height: 1.25),
        ),
        if (showSubtitle && hasSubtitle) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: prism.AppTextStyle.caption2
                .of(context)
                .copyWith(color: colors.onSurfaceVariant, height: 1.35),
          ),
        ],
      ],
    );
    final iconBadge = glyph == null
        ? null
        : SizedBox.square(
            dimension: 48,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: palette.bg,
                shape: RoundedSuperellipseBorder(
                  borderRadius: prism.AppRadius.all(prism.AppCorner.md),
                  side: BorderSide(color: palette.border, width: 1.0),
                ),
              ),
              child: Center(
                child: prism_icons.GlyphIcon(
                  glyph!,
                  size: 22,
                  color: palette.fg,
                ),
              ),
            ),
          );

    final baseCard = PrismHoverGlow(
      radius: prism.AppCorner.xl,
      child: prism.Card(
        radius: prism.AppCorner.xl,
        onPressed: onPressed,
        inert: onPressed == null,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bounded = constraints.hasBoundedWidth;
              return Row(
                mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (iconBadge != null) ...[
                    iconBadge,
                    const SizedBox(width: 16),
                  ],
                  if (bounded)
                    Expanded(child: textColumn)
                  else
                    Flexible(child: textColumn),
                  if (bounded && onPressed != null) ...[
                    const SizedBox(width: 8),
                    PrismGlyph(
                      AntGlyphs.chevronForward,
                      size: 14,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.45),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
    final card = !showSubtitle && hasSubtitle
        ? prism.Tooltip(message: subtitle!, child: baseCard)
        : baseCard;
    final result = onPressed == null
        ? card
        : PrismHoverMotion(hoverScale: 1.02, pressScale: 0.98, child: card);
    if (staggerIndex == null) return result;
    return PrismStaggerIn(
      index: staggerIndex!,
      initialDelay: staggerDelay,
      child: result,
    );
  }
}

class PrismEmptyState extends StatelessWidget {
  const PrismEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.glyph = AntGlyphs.search,
    this.action,
  });

  final String title;
  final String? subtitle;
  final prism_icons.Glyph glyph;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            prism.Surface(
              color: colors.surfaceContainerLow,
              shape: prism.AppShape.xl,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: prism_icons.GlyphIcon(
                  glyph,
                  size: 32,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: prism.AppTextStyle.headline.of(context),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: prism.AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class PrismSearchBar extends StatelessWidget {
  const PrismSearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = '搜索...',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.height = 44,
    this.trailing,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final bool autofocus;
  final double height;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return prism.SearchField(
      controller: controller,
      focusNode: focusNode,
      hintText: hintText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      height: height,
      fill: colors.surfaceContainerLow,
      trailing: trailing,
    );
  }
}

class PrismCodeSurface extends StatelessWidget {
  const PrismCodeSurface({
    super.key,
    required this.code,
    this.language,
    this.maxHeight,
    this.showCopy = true,
  });

  final String code;
  final String? language;
  final double? maxHeight;
  final bool showCopy;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final body = prism.SelectableText(
      code,
      style: prismMonoTextStyle(color: colors.onSurface),
    );
    return prism.Surface(
      color: colors.surfaceContainerLow,
      shape: prism.AppShape.lg,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounded = constraints.hasBoundedHeight;
          final codeChild = bounded
              ? Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: body,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: maxHeight == null
                      ? body
                      : ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxHeight!),
                          child: SingleChildScrollView(child: body),
                        ),
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showCopy || (language != null && language!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 4),
                  child: Row(
                    children: [
                      if (language != null && language!.isNotEmpty)
                        Text(
                          language!.toUpperCase(),
                          style: prism.AppTextStyle.caption2
                              .of(context, emphasized: true)
                              .copyWith(color: colors.onSurfaceVariant),
                        ),
                      const Spacer(),
                      if (showCopy)
                        prism.IconButton(
                          tooltip: '复制代码',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            showPrismNotice(context, '已复制到剪贴板');
                          },
                          icon: const PrismGlyph(AntGlyphs.copy, size: 15),
                        ),
                    ],
                  ),
                ),
              codeChild,
            ],
          );
        },
      ),
    );
  }
}

class PrismProgressPanel extends StatelessWidget {
  const PrismProgressPanel({
    super.key,
    required this.title,
    this.subtitle,
    this.progress,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final double? progress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final pct = progress == null
        ? null
        : '${(progress!.clamp(0.0, 1.0) * 100).round()}%';
    return PrismHoverGlow(
      radius: prism.AppCorner.lg,
      child: prism.Card(
        radius: prism.AppCorner.lg,
        inert: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: prism.AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                ),
                if (pct != null)
                  Text(
                    pct,
                    style: prism.AppTextStyle.footnote
                        .of(context, emphasized: true)
                        .copyWith(color: colors.primary),
                  ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: 8),
            prism.LinearProgressIndicator(value: progress, minHeight: 6),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: prism.AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PrismInputDecoration {
  const PrismInputDecoration({
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixText,
    this.suffixText,
    this.prefixIcon,
    this.suffixIcon,
    this.contentPadding,
    this.isDense,
    this.filled,
    this.fillColor,
    this.enabled = true,
  });

  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final String? prefixText;
  final String? suffixText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final EdgeInsetsGeometry? contentPadding;
  final bool? isDense;
  final bool? filled;
  final Color? fillColor;
  final bool enabled;

  prism.InputDecoration resolve(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return prism.InputDecoration(
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      prefixText: prefixText,
      suffixText: suffixText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: isDense,
      filled: filled ?? true,
      fillColor: fillColor ?? colors.surfaceContainerLow,
      enabled: enabled,
    );
  }
}

class PrismTextField extends StatelessWidget {
  const PrismTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const PrismInputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.style,
    this.textAlign = TextAlign.start,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.enabled = true,
    this.onTap,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final PrismInputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool readOnly;
  final bool autofocus;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final field = prism.TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: decoration.resolve(context),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: style,
      textAlign: textAlign,
      readOnly: readOnly,
      autofocus: autofocus,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      maxLength: maxLength,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      enabled: enabled,
      onTap: onTap,
    );
    final label = decoration.labelText;
    if (label == null || label.isEmpty) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 10),
          child: Text(
            label,
            style: prism.AppTextStyle.footnote
                .of(context, emphasized: true)
                .copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        field,
      ],
    );
  }
}

class PrismTextFormField extends StatelessWidget {
  const PrismTextFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.decoration = const PrismInputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
    this.autovalidateMode,
    this.inputFormatters,
    this.readOnly = false,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;
  final PrismInputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final field = prism.TextFormField(
      controller: controller,
      initialValue: initialValue,
      focusNode: focusNode,
      decoration: decoration.resolve(context),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autofocus: autofocus,
      readOnly: readOnly,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      autovalidateMode: autovalidateMode,
      inputFormatters: inputFormatters,
    );
    final label = decoration.labelText;
    if (label == null || label.isEmpty) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 10),
          child: Text(
            label,
            style: prism.AppTextStyle.footnote
                .of(context, emphasized: true)
                .copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        field,
      ],
    );
  }
}

class PrismDropdownItem<T> {
  const PrismDropdownItem({required this.value, required this.child});

  final T? value;
  final Widget child;

  String get label => switch (child) {
    Text(:final data) => data ?? value?.toString() ?? '',
    _ => value?.toString() ?? '',
  };
}

class PrismDropdownField<T> extends StatefulWidget {
  const PrismDropdownField({
    super.key,
    this.value,
    this.initialValue,
    required this.items,
    this.decoration = const PrismInputDecoration(),
    this.onChanged,
    this.isExpanded = true,
  });

  final T? value;
  final T? initialValue;
  final List<PrismDropdownItem<T>> items;
  final PrismInputDecoration decoration;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;

  @override
  State<PrismDropdownField<T>> createState() => _PrismDropdownFieldState<T>();
}

class PrismMenuItem<T> {
  const PrismMenuItem({
    required this.value,
    required this.child,
    this.danger = false,
    this.enabled = true,
  });

  final T value;
  final Widget child;
  final bool danger;
  final bool enabled;

  String get label => switch (child) {
    Text(:final data) => data ?? value.toString(),
    _ => value.toString(),
  };
}

class PrismPopupMenuButton<T> extends StatelessWidget {
  const PrismPopupMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.icon,
    this.tooltip,
    this.enabled = true,
  });

  final List<PrismMenuItem<T>> Function(BuildContext) itemBuilder;
  final ValueChanged<T> onSelected;
  final Widget? icon;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) => prism.PopupAnchor(
    targetBuilder: (open) => prism.IconButton(
      onPressed: enabled ? open : null,
      tooltip: tooltip,
      icon: icon ?? const PrismGlyph(AntGlyphs.more, size: 18),
    ),
    popupBuilder: (context) => prism.PopupMenu(
      items: [
        for (final item in itemBuilder(context))
          prism.PopupMenuItem(
            label: item.label,
            danger: item.danger,
            onPressed: item.enabled ? () => onSelected(item.value) : null,
          ),
      ],
    ),
  );
}

class PrismChip extends StatelessWidget {
  const PrismChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onPressed,
    this.onSelected,
    this.onDeleted,
  });

  final Widget label;
  final bool selected;
  final VoidCallback? onPressed;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed =
        onPressed ?? (onSelected == null ? null : () => onSelected!(!selected));
    final chip = prism.Chip(
      label: switch (label) {
        Text(:final data) => data ?? '',
        _ => '',
      },
      selected: selected,
      onPressed: effectiveOnPressed,
      onDeleted: onDeleted,
    );
    if (effectiveOnPressed == null && onDeleted == null) return chip;
    return PrismHoverMotion(hoverScale: 1.03, pressScale: 0.96, child: chip);
  }
}

class _PrismDropdownFieldState<T> extends State<PrismDropdownField<T>> {
  T? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value ?? widget.initialValue;
  }

  @override
  void didUpdateWidget(PrismDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.initialValue != widget.initialValue) {
      _value = widget.value ?? widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.where((item) => item.value == _value);
    final label = selected.isEmpty ? '' : selected.first.label;
    final enabled = widget.onChanged != null && widget.items.isNotEmpty;
    final colors = prism.Theme.of(context).colorScheme;
    final field = prism.PopupAnchor(
      placement: prism.PopupPlacement.overAnchorEnd,
      targetBuilder: (open) => prism.Card(
        radius: prism.AppCorner.md,
        onPressed: enabled ? open : null,
        inert: !enabled,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.isEmpty ? (widget.decoration.hintText ?? '') : label,
                overflow: TextOverflow.ellipsis,
                style: prism.AppTextStyle.subheadline
                    .of(context)
                    .copyWith(
                      color: label.isEmpty
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            prism_icons.GlyphIcon(
              prism_icons.Glyphs.picker,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
      popupBuilder: (context) => prism.PopupMenu(
        maxVisibleItems: 8,
        items: [
          for (final item in widget.items)
            prism.PopupMenuItem(
              label: item.label,
              checked: item.value == _value,
              onPressed: enabled
                  ? () {
                      setState(() => _value = item.value);
                      widget.onChanged?.call(item.value);
                    }
                  : null,
            ),
        ],
      ),
    );
    final labelText = widget.decoration.labelText;
    if (labelText == null || labelText.isEmpty) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 10),
          child: Text(
            labelText,
            style: prism.AppTextStyle.footnote
                .of(context, emphasized: true)
                .copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        field,
      ],
    );
  }
}

class PrismDialog extends StatelessWidget {
  const PrismDialog({
    super.key,
    this.title = '',
    this.content,
    this.actions,
    this.hasFields = false,
    this.destructive = false,
    this.padding,
  });

  final Object title;
  final Widget? content;
  final List<Widget>? actions;
  final bool hasFields;
  final bool destructive;
  final EdgeInsets? padding;

  String get _titleText => switch (title) {
    String text => text,
    Text(:final data) => data ?? '',
    _ => '',
  };

  List<Widget> _normalizeAlertActions(List<Widget>? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final action in raw)
        if (action is prism.FilledButton)
          action.icon == null
              ? prism.TextButton(
                  onPressed: action.onPressed,
                  child: action.child,
                )
              : prism.TextButton.icon(
                  onPressed: action.onPressed,
                  icon: action.icon!,
                  label: action.child,
                )
        else if (action is prism.OutlinedButton)
          action.icon == null
              ? prism.TextButton(
                  onPressed: action.onPressed,
                  child: action.child,
                )
              : prism.TextButton.icon(
                  onPressed: action.onPressed,
                  icon: action.icon!,
                  label: action.child,
                )
        else
          action,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final wideBox = content is SizedBox ? content as SizedBox : null;
    final requestedWidth = wideBox?.width;
    if (requestedWidth != null && requestedWidth >= 420) {
      final colors = prism.Theme.of(context).colorScheme;
      final screen = MediaQuery.sizeOf(context);
      final maxW = (requestedWidth + 48).clamp(440.0, screen.width - 72);
      final maxH = (screen.height - 72).clamp(320.0, 820.0);
      final innerChild = wideBox?.child ?? content;
      final requestedHeight = wideBox?.height;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
            child: prism.Surface(
              color: colors.surface,
              shape: prism.AppShape.all(prism.AppCorner.xxl),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_titleText.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 22, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _titleText,
                              style: prism.AppTextStyle.title3.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                          ),
                          prism.IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const PrismGlyph(AntGlyphs.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                    const prism.Divider(height: 1),
                  ],
                  if (innerChild != null)
                    Flexible(
                      child: Padding(
                        padding:
                            padding ??
                            const EdgeInsets.fromLTRB(28, 22, 28, 22),
                        child: requestedHeight != null
                            ? ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: requestedHeight,
                                ),
                                child: innerChild,
                              )
                            : innerChild,
                      ),
                    ),
                  if (actions != null && actions!.isNotEmpty) ...[
                    const prism.Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        runSpacing: 10,
                        children: actions!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return prism.AlertDialog(
      title: _titleText,
      child: content,
      actions: _normalizeAlertActions(actions),
      hasFields: hasFields,
      destructive: destructive,
      padding: padding,
    );
  }
}

Future<T?> showPrismDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = false,
}) {
  final routeContext = useRootNavigator
      ? Navigator.of(context, rootNavigator: true).context
      : context;
  return prism.showFloatingDialog<T>(
    context: routeContext,
    dismissible: barrierDismissible,
    child: Builder(builder: builder),
  );
}

void showPrismNotice(
  BuildContext context,
  String message, {
  prism.BannerLevel level = prism.BannerLevel.info,
}) {
  prism.BannerHost.maybeOf(context)?.show(message, level: level);
}

class PrismProgressIndicator extends StatelessWidget {
  const PrismProgressIndicator({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => prism.ActivityIndicator(size: size);
}

class PrismHoverMotion extends StatefulWidget {
  const PrismHoverMotion({
    super.key,
    required this.child,
    this.enabled = true,
    this.hoverScale = 1.056,
    this.pressScale = 0.925,
    this.scaleByIntensity = true,
  });

  final Widget child;
  final bool enabled;
  final double hoverScale;
  final double pressScale;
  final bool scaleByIntensity;

  @override
  State<PrismHoverMotion> createState() => _PrismHoverMotionState();
}

class _PrismHoverMotionState extends State<PrismHoverMotion> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return ListenableBuilder(
      listenable: appMotionIntensity,
      child: widget.child,
      builder: (context, child) {
        final spec = PrismMotionSpec.current;
        final effectiveHover = widget.scaleByIntensity
            ? 1.0 + (widget.hoverScale - 1.0) * spec.hoverScaleFactor
            : widget.hoverScale;
        final effectivePress = widget.scaleByIntensity
            ? (1.0 - (1.0 - widget.pressScale) * spec.pressScaleFactor).clamp(
                0.75,
                1.0,
              )
            : widget.pressScale;
        final scale = !spec.enabled
            ? 1.0
            : _pressed
            ? effectivePress
            : _hovered
            ? effectiveHover
            : 1.0;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: Listener(
            onPointerDown: (_) => setState(() => _pressed = true),
            onPointerUp: (_) => setState(() => _pressed = false),
            onPointerCancel: (_) => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: scale,
              duration: !spec.enabled
                  ? Duration.zero
                  : _pressed
                  ? const Duration(milliseconds: 90)
                  : spec.motionReleaseDuration,
              curve: !spec.enabled
                  ? Curves.linear
                  : _pressed
                  ? Curves.easeOutCubic
                  : spec.springCurve,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class PrismTonalButton extends StatelessWidget {
  const PrismTonalButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : icon = null;

  const PrismTonalButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.child,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final prism.ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = prism.Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseTint = cs.primary.withValues(alpha: isDark ? 0.18 : 0.10);
    final hoverTint = cs.primary.withValues(alpha: isDark ? 0.28 : 0.17);
    final tonalStyle = prism.ButtonStyle(
      backgroundColor: WidgetStateProperty.fromMap({
        WidgetState.disabled: cs.onSurface.withValues(alpha: 0.04),
        WidgetState.hovered: hoverTint,
        WidgetState.any: baseTint,
      }),
      foregroundColor: WidgetStateProperty.fromMap({
        WidgetState.disabled: cs.onSurface.withValues(alpha: 0.36),
        WidgetState.any: cs.primary,
      }),
      overlayColor: WidgetStateProperty.fromMap({
        WidgetState.hovered: cs.primary.withValues(alpha: 0.06),
        WidgetState.pressed: cs.primary.withValues(alpha: 0.12),
        WidgetState.any: const Color(0x00000000),
      }),
      shape: prism.AppShape.full,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
    ).merge(style);
    return icon == null
        ? prism.FilledButton(
            onPressed: onPressed,
            style: tonalStyle,
            child: child,
          )
        : prism.FilledButton.icon(
            onPressed: onPressed,
            style: tonalStyle,
            icon: icon!,
            label: child,
          );
  }
}

class PrismSwitchTile extends StatelessWidget {
  const PrismSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) => PrismListTile(
    title: title,
    subtitle: subtitle,
    contentPadding: contentPadding,
    trailing: prism.Switch(value: value, onChanged: onChanged),
    onTap: onChanged == null ? null : () => onChanged!(!value),
  );
}

class PrismCheckboxTile extends StatelessWidget {
  const PrismCheckboxTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) => PrismListTile(
    title: title,
    subtitle: subtitle,
    contentPadding: contentPadding,
    trailing: prism.Checkbox(value: value, onChanged: onChanged),
    onTap: onChanged == null ? null : () => onChanged!(value != true),
  );
}

class PrismCard extends StatelessWidget {
  const PrismCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.all(4),
    this.padding = EdgeInsets.zero,
    this.radius,
    this.onPressed,
    this.shape,
    this.clipBehavior = Clip.none,
    this.hoverGlow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsets? padding;
  final double? radius;
  final VoidCallback? onPressed;
  final ShapeBorder? shape;
  final Clip clipBehavior;
  final bool hoverGlow;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = radius ?? prism.AppCorner.xl;
    final card = Padding(
      padding: margin,
      child: PrismHoverGlow(
        radius: effectiveRadius,
        enabled: hoverGlow,
        child: prism.Card(
          radius: effectiveRadius,
          shape: shape is OutlinedBorder ? shape as OutlinedBorder : null,
          padding: padding,
          onPressed: onPressed,
          inert: onPressed == null,
          child: child,
        ),
      ),
    );
    if (clipBehavior == Clip.none || shape == null) return card;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape!),
      clipBehavior: clipBehavior,
      child: card,
    );
  }
}

class PrismListTile extends StatelessWidget {
  const PrismListTile({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.contentPadding,
    this.dense = false,
    this.isThreeLine = false,
    this.selected = false,
    this.selectedTileColor,
    this.selectedColor,
    this.shape,
    this.onTap,
  });

  final Widget title;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;
  final bool dense;
  final bool isThreeLine;
  final bool selected;
  final Color? selectedTileColor;
  final Color? selectedColor;
  final ShapeBorder? shape;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveLeading =
        selected && selectedColor != null && leading != null
        ? IconTheme.merge(
            data: IconThemeData(color: selectedColor),
            child: leading!,
          )
        : leading;
    final effectiveTitle = selected && selectedColor != null && title is Text
        ? _textWithColor(title as Text, selectedColor!)
        : title;
    final row = prism.ListRow(
      leading: effectiveLeading,
      title: effectiveTitle,
      subtitle: subtitle,
      trailing: trailing,
      padding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 20),
      minHeight: isThreeLine
          ? 84
          : dense
          ? 54
          : 68,
      minVerticalPadding: dense ? 10 : 14,
    );
    final content = prism.Surface(
      color: selected
          ? selectedTileColor ?? const Color(0x00000000)
          : const Color(0x00000000),
      shape: shape ?? prism.AppShape.lg,
      child: row,
    );
    if (onTap == null) return content;
    return prism.PressRegion(
      onTap: onTap,
      shape: shape ?? prism.AppShape.lg,
      child: content,
    );
  }

  Widget _textWithColor(Text text, Color color) => Text(
    text.data ?? '',
    key: text.key,
    style: text.style?.copyWith(color: color) ?? TextStyle(color: color),
    strutStyle: text.strutStyle,
    textAlign: text.textAlign,
    textDirection: text.textDirection,
    locale: text.locale,
    softWrap: text.softWrap,
    overflow: text.overflow,
    textScaler: text.textScaler,
    maxLines: text.maxLines,
    semanticsLabel: text.semanticsLabel,
    selectionColor: text.selectionColor,
  );
}
