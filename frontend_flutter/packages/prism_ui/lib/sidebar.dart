import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/divider.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/l10n.dart';
import 'package:prism_ui/press_region.dart';
import 'package:prism_ui/scroll_behavior.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/tooltip.dart';
import 'package:prism_ui/typography.dart';

const _compactWidth = 48.0;
const _expandedWidth = 220.0;
const _itemSize = 40.0;
const _itemGap = 4.0;
const _sectionDividerHeight = 13.0;
const _toggleGap = 8.0;
const _verticalInset = 4.0;
const _maxSideInset = 12.0;
const _iconSize = 24.0;
const _labelGap = 12.0;
const _indicatorWidth = 3.0;
const _indicatorHeight = 16.0;
const _expandDuration = Duration(milliseconds: 250);
const _indicatorDuration = Duration(milliseconds: 320);
final _itemShape = AppShape.all(10);

class SidebarDestination {
  const SidebarDestination({
    required this.glyph,
    required this.label,
    this.dividerBefore = false,
  });

  final Glyph glyph;
  final String label;
  final bool dividerBefore;
}

/// Where the sidebar cannot widen in place, [onToggle] is null and the toggle
/// opens the expanded pane over the content instead.
///
/// [windowControls] is the area native window buttons cover at the top start
/// corner; the pane keeps it clear and never gets narrower than it.
class NavigationSidebar extends StatefulWidget {
  const NavigationSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.expanded,
    required this.onSelected,
    this.onToggle,
    this.windowControls = Size.zero,
  });

  final List<SidebarDestination> destinations;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelected;
  final VoidCallback? onToggle;
  final Size windowControls;

  @override
  State<NavigationSidebar> createState() => _NavigationSidebarState();
}

class _NavigationSidebarState extends State<NavigationSidebar>
    with SingleTickerProviderStateMixin {
  final _overlayController = OverlayPortalController();
  late final AnimationController _overlayExpansion = AnimationController(
    vsync: this,
    duration: _expandDuration,
  );
  late final CurvedAnimation _overlayProgress = CurvedAnimation(
    parent: _overlayExpansion,
    curve: Easing.standard,
  );

  @override
  void didUpdateWidget(covariant NavigationSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onToggle != null && _overlayController.isShowing) {
      _overlayExpansion.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _hideIfDismissed());
    }
  }

  void _handleToggle() {
    final onToggle = widget.onToggle;
    if (onToggle != null) {
      onToggle();
    } else if (_overlayExpansion.isForwardOrCompleted) {
      _closeOverlay();
    } else {
      _overlayController.show();
      _overlayExpansion.forward();
    }
  }

  void _closeOverlay() {
    _overlayExpansion.reverse().whenCompleteOrCancel(_hideIfDismissed);
  }

  void _hideIfDismissed() {
    if (mounted && _overlayExpansion.isDismissed) {
      _overlayController.hide();
    }
  }

  @override
  void dispose() {
    _overlayProgress.dispose();
    _overlayExpansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlayController,
      overlayChildBuilder: (context, info) {
        return _SidebarOverlay(
          anchor: MatrixUtils.transformRect(
            info.childPaintTransform,
            Offset.zero & info.childSize,
          ),
          overlayWidth: info.overlaySize.width,
          progress: _overlayProgress,
          onDismiss: _closeOverlay,
          builder: (progress) => Padding(
            padding: safePadding,
            child: _SidebarPane(
              progress: progress,
              windowControls: widget.windowControls,
              expanded: true,
              destinations: widget.destinations,
              selectedIndex: widget.selectedIndex,
              onSelected: (index) {
                widget.onSelected(index);
                _closeOverlay();
              },
              onToggle: _closeOverlay,
            ),
          ),
        );
      },
      child: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.expanded ? 1.0 : 0.0),
          duration: context.motionDuration(_expandDuration),
          curve: Easing.standard,
          builder: (context, progress, _) => _SidebarPane(
            progress: progress,
            windowControls: widget.windowControls,
            expanded: widget.expanded,
            destinations: widget.destinations,
            selectedIndex: widget.selectedIndex,
            onSelected: widget.onSelected,
            onToggle: _handleToggle,
          ),
        ),
      ),
    );
  }
}

class _SidebarOverlay extends StatelessWidget {
  const _SidebarOverlay({
    required this.anchor,
    required this.overlayWidth,
    required this.progress,
    required this.onDismiss,
    required this.builder,
  });

  final Rect anchor;
  final double overlayWidth;
  final Animation<double> progress;
  final VoidCallback onDismiss;
  final Widget Function(double progress) builder;

  @override
  Widget build(BuildContext context) {
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    final colorScheme = context.colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: isLtr ? anchor.left : null,
          right: isLtr ? null : overlayWidth - anchor.right,
          top: anchor.top,
          height: anchor.height,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    onDismiss();
                    return null;
                  },
                ),
              },
              child: FocusScope(
                autofocus: true,
                child: Surface(
                  color: colorScheme.chromeSurface,
                  shape: BorderDirectional(
                    end: Divider.createBorderSide(context),
                  ),
                  elevation: 8,
                  shadowColor: colorScheme.shadow,
                  child: AnimatedBuilder(
                    animation: progress,
                    builder: (_, _) => builder(progress.value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarColors {
  _SidebarColors(ColorScheme scheme)
    : selectedFill = scheme.primaryContainer,
      label = scheme.onSurface,
      selectedLabel = scheme.onPrimaryContainer,
      icon = scheme.onSurfaceVariant,
      selectedIcon = scheme.onPrimaryContainer,
      indicator = scheme.primary,
      overlay = WidgetStateProperty.fromMap({
        WidgetState.pressed: scheme.primary.withValues(alpha: 0.11),
        WidgetState.focused: scheme.primary.withValues(alpha: 0.12),
        WidgetState.hovered: scheme.primary.withValues(alpha: 0.06),
        WidgetState.any: Colors.transparent,
      });

  final Color selectedFill;
  final Color label;
  final Color selectedLabel;
  final Color icon;
  final Color selectedIcon;
  final Color indicator;
  final WidgetStateProperty<Color> overlay;
}

class _SidebarPane extends StatelessWidget {
  const _SidebarPane({
    required this.progress,
    required this.windowControls,
    required this.expanded,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onToggle,
  });

  final double progress;
  final Size windowControls;
  final bool expanded;
  final List<SidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = _SidebarColors(context.colorScheme);
    final fontSize = AppTextStyle.subheadline.size;
    final labelOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    final compactWidth = math.max(_compactWidth, windowControls.width);
    final sideInset = math.min(_maxSideInset, (compactWidth - _itemSize) / 2);
    final itemWidth = compactWidth - sideInset * 2;
    final iconInset = (itemWidth - _iconSize) / 2;
    final itemHeight =
        _itemSize + MediaQuery.textScalerOf(context).scale(fontSize) - fontSize;
    final rowWidth = _expandedWidth - sideInset * 2;
    final labelStyle = AppTextStyle.subheadline
        .of(context)
        .copyWith(color: colors.label);
    final selectedLabelStyle = labelStyle.copyWith(
      color: colors.selectedLabel,
      fontWeight: FontWeight.w600,
    );
    final labelWidth = rowWidth - iconInset - _iconSize - _labelGap * 2;
    String rowTooltip(String label) =>
        expanded &&
            progress == 1 &&
            _fitsOneLine(context, label, labelStyle, labelWidth)
        ? ''
        : label;
    return SizedBox(
      width: lerpDouble(compactWidth, _expandedWidth, progress),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: windowControls.height + _verticalInset),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _SidebarButton(
              colors: colors,
              height: itemHeight,
              sideInset: sideInset,
              tooltip: expanded
                  ? UiLocalizations.of(context).showLess
                  : UiLocalizations.of(context).showMore,
              tooltipIsLabel: true,
              onTap: onToggle,
              child: SizedBox(
                width: itemWidth,
                child: Center(child: GlyphIcon(Glyphs.sidebar(progress))),
              ),
            ),
          ),
          const SizedBox(height: _toggleGap),
          Expanded(
            child: ScrollConfiguration(
              behavior: const HiddenBarScrollBehavior(),
              child: SingleChildScrollView(
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, destination) in destinations.indexed) ...[
                          if (destination.dividerBefore)
                            SizedBox(
                              height: _sectionDividerHeight,
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: sideInset + 6,
                                  ),
                                  child: const Divider(height: 1),
                                ),
                              ),
                            ),
                          _SidebarButton(
                            key: ValueKey(destination.label),
                            colors: colors,
                            height: itemHeight,
                            sideInset: sideInset,
                            selected: index == selectedIndex,
                            tooltip: rowTooltip(destination.label),
                            onTap: () => onSelected(index),
                            hoverBuilder: (context, hovered) => _DestinationRow(
                              destination: destination,
                              selected: index == selectedIndex,
                              hovered: hovered,
                              width: rowWidth,
                              iconInset: iconInset,
                              style: index == selectedIndex
                                  ? selectedLabelStyle
                                  : labelStyle,
                              labelOpacity: labelOpacity,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (selectedIndex < destinations.length)
                      _SelectionIndicator(
                        color: colors.indicator,
                        index: selectedIndex,
                        start: sideInset,
                        stride: itemHeight + _itemGap,
                        dividerBeforeFlags: [
                          for (final d in destinations) d.dividerBefore,
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: _verticalInset),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  const _SidebarButton({
    super.key,
    required this.colors,
    required this.height,
    required this.sideInset,
    required this.tooltip,
    required this.onTap,
    this.child,
    this.hoverBuilder,
    this.selected,
    this.tooltipIsLabel = false,
  });

  final _SidebarColors colors;
  final double height;
  final double sideInset;
  final bool? selected;
  final String tooltip;
  final bool tooltipIsLabel;
  final VoidCallback onTap;
  final Widget? child;
  final Widget Function(BuildContext context, bool hovered)? hoverBuilder;

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final content =
        widget.hoverBuilder?.call(context, _hovered) ?? widget.child!;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.sideInset,
        vertical: _itemGap / 2,
      ),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        child: FocusRing(
          shape: _itemShape,
          child: PressRegion(
            onTap: widget.onTap,
            onHover: (hovered) {
              if (_hovered != hovered) {
                setState(() => _hovered = hovered);
              }
            },
            shape: _itemShape,
            fill: selected == true ? widget.colors.selectedFill : null,
            overlay: widget.colors.overlay,
            mouseCursor: SystemMouseCursors.click,
            child: Tooltip(
              message: widget.tooltip,
              excludeFromSemantics: !widget.tooltipIsLabel,
              child: IconTheme.merge(
                data: IconThemeData(
                  size: _iconSize,
                  color: selected == true
                      ? widget.colors.selectedIcon
                      : widget.colors.icon,
                ),
                child: SizedBox(height: widget.height, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _fitsOneLine(
  BuildContext context,
  String text,
  TextStyle? style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout(maxWidth: width);
  final fits = !painter.didExceedMaxLines;
  painter.dispose();
  return fits;
}

/// The row lays out at the expanded width whatever the pane's current width,
/// so the label is clipped rather than reflowed while the pane animates.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.selected,
    this.hovered = false,
    required this.width,
    required this.iconInset,
    required this.style,
    required this.labelOpacity,
  });

  final SidebarDestination destination;
  final bool selected;
  final bool hovered;
  final double width;
  final double iconInset;
  final TextStyle? style;
  final double labelOpacity;

  @override
  Widget build(BuildContext context) {
    final nudge = (hovered || selected) && labelOpacity > 0.5 ? 5.0 : 0.0;
    return ClipRect(
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: width,
        maxWidth: width,
        child: AnimatedPadding(
          duration: context.motionDuration(const Duration(milliseconds: 220)),
          curve: Curves.easeOutCubic,
          padding: EdgeInsetsDirectional.only(start: nudge),
          child: Row(
            children: [
              SizedBox(width: iconInset),
              AnimatedGlyph(glyph: destination.glyph, filled: selected),
              const SizedBox(width: _labelGap),
              Expanded(
                child: Opacity(
                  opacity: labelOpacity,
                  alwaysIncludeSemantics: true,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ),
              const SizedBox(width: _labelGap),
            ],
          ),
        ),
      ),
    );
  }
}

/// The indicator moves by stretching toward the new row before its trailing
/// edge catches up, rather than sliding at a fixed size.
class _SelectionIndicator extends StatefulWidget {
  const _SelectionIndicator({
    required this.color,
    required this.index,
    required this.start,
    required this.stride,
    required this.dividerBeforeFlags,
  });

  final Color color;
  final int index;
  final double start;
  final double stride;
  final List<bool> dividerBeforeFlags;

  @override
  State<_SelectionIndicator> createState() => _SelectionIndicatorState();
}

class _SelectionIndicatorState extends State<_SelectionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _indicatorDuration,
    value: 1,
  );
  late int _from = widget.index;

  @override
  void didUpdateWidget(covariant _SelectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final duration = context.motionDuration(_indicatorDuration);
    _controller.duration = duration;
    if (oldWidget.index != widget.index) {
      _from = oldWidget.index;
      if (duration == Duration.zero) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _topOf(int index) {
    var dividers = 0;
    final flags = widget.dividerBeforeFlags;
    final upper = math.min(index, flags.length - 1);
    for (var i = 0; i <= upper; i++) {
      if (flags[i]) dividers++;
    }
    return index * widget.stride +
        dividers * _sectionDividerHeight +
        (widget.stride - _indicatorHeight) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final from = _topOf(_from);
        final to = _topOf(widget.index);
        final lead = Curves.easeOutCubic.transform(math.min(1, t / 0.6));
        final trail = Curves.easeInOutCubic.transform(
          math.max(0, (t - 0.35) / 0.65),
        );
        final (top, bottom) = to >= from
            ? (lerpDouble(from, to, trail)!, lerpDouble(from, to, lead)!)
            : (lerpDouble(from, to, lead)!, lerpDouble(from, to, trail)!);
        return PositionedDirectional(
          start: widget.start,
          top: top,
          width: _indicatorWidth,
          height: bottom - top + _indicatorHeight,
          child: child!,
        );
      },
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: widget.color,
            shape: AppShape.full,
          ),
        ),
      ),
    );
  }
}
