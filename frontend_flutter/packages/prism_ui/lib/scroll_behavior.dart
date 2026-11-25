import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/scroll.dart';
import 'package:prism_ui/theme_data.dart';

bool isTouchPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => true,
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => false,
};

class BaseScrollBehavior extends ScrollBehavior {
  const BaseScrollBehavior({this.scrollbarPadding = EdgeInsets.zero});

  final EdgeInsets scrollbarPadding;

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      Theme.of(context).platform;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.mouse,
    PointerDeviceKind.unknown,
  };

  bool showScrollbar(BuildContext context) =>
      !isTouchPlatform(getPlatform(context));

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal ||
        !showScrollbar(context)) {
      return child;
    }
    return Scrollbar.ambient(
      controller: details.controller,
      padding: scrollbarPadding,
      child: child,
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final platform = getPlatform(context);
    ScrollPosition? position;
    if (context is StatefulElement && context.state is ScrollableState) {
      position = (context.state as ScrollableState).position;
    }
    final wrapped =
        axisDirectionToAxis(details.direction) == Axis.vertical &&
            !isTouchPlatform(platform) &&
            position != null
        ? _SmoothWheelScroll(position: position, child: child)
        : child;
    return switch (platform) {
      TargetPlatform.android => StretchingOverscrollIndicator(
        axisDirection: details.direction,
        clipBehavior: details.decorationClipBehavior ?? Clip.hardEdge,
        child: wrapped,
      ),
      TargetPlatform.fuchsia => GlowingOverscrollIndicator(
        axisDirection: details.direction,
        color: Theme.of(context).colorScheme.secondary,
        child: wrapped,
      ),
      TargetPlatform.iOS ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => wrapped,
    };
  }

  @override
  bool shouldNotify(covariant BaseScrollBehavior oldDelegate) {
    return oldDelegate.scrollbarPadding != scrollbarPadding;
  }
}

class _SmoothWheelScroll extends StatefulWidget {
  const _SmoothWheelScroll({required this.position, required this.child});

  final ScrollPosition position;
  final Widget child;

  @override
  State<_SmoothWheelScroll> createState() => _SmoothWheelScrollState();
}

class _SmoothWheelScrollState extends State<_SmoothWheelScroll>
    with SingleTickerProviderStateMixin {
  static const double _damping = 14.0;

  late final Ticker _ticker;
  double _target = 0.0;
  double _lastApplied = 0.0;
  Duration _lastElapsed = Duration.zero;
  bool _pendingMicrotask = false;
  double _visualBefore = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant _SmoothWheelScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _stop() {
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _lastElapsed = Duration.zero;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.scrollDelta.dy == 0) return;
    final position = widget.position;
    if (!position.hasPixels) return;
    if (position.maxScrollExtent <= position.minScrollExtent) return;

    if (!_pendingMicrotask) {
      _pendingMicrotask = true;
      _visualBefore = position.pixels;
      scheduleMicrotask(_consumeResolvedScroll);
    }
  }

  void _consumeResolvedScroll() {
    _pendingMicrotask = false;
    if (!mounted) return;
    final position = widget.position;
    if (!position.hasPixels) return;

    final after = position.pixels;
    final actualDelta = after - _visualBefore;
    // Ignore if an inner nested scrollable handled the event or already at edge.
    if (actualDelta.abs() < 0.01) return;

    // Silently revert Scrollable's synchronous jump before layout/paint.
    position.correctPixels(_visualBefore);

    final dpr = View.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final reversing =
        _ticker.isActive && ((_target - _visualBefore) * actualDelta < 0);
    final base = (_ticker.isActive && !reversing) ? _target : _visualBefore;
    final rawTarget = base + actualDelta;
    final snappedTarget = (rawTarget * dpr).roundToDouble() / dpr;
    _target = snappedTarget.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _lastApplied = _visualBefore;

    if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) {
      _stop();
      return;
    }
    final position = widget.position;
    if (!position.hasPixels) {
      _stop();
      return;
    }

    final current = position.pixels;
    // Yield immediately if user drags scrollbar or something else jumps position.
    if ((current - _lastApplied).abs() > 1.0) {
      _stop();
      return;
    }

    final double dt;
    if (_lastElapsed == Duration.zero) {
      dt = 1.0 / 60.0;
    } else {
      dt = ((elapsed - _lastElapsed).inMicroseconds / 1000000.0).clamp(
        0.001,
        0.05,
      );
    }
    _lastElapsed = elapsed;

    final dpr = View.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final onePhysicalPx = 1.0 / dpr;

    _target = _target.clamp(position.minScrollExtent, position.maxScrollExtent);
    final remaining = _target - current;
    if (remaining.abs() <= onePhysicalPx * 1.5) {
      _lastApplied = _target;
      position.jumpTo(_target);
      _stop();
      return;
    }

    final factor = 1.0 - exp(-_damping * dt);
    var step = remaining * factor;
    if (step.abs() < onePhysicalPx) {
      step = remaining.sign * onePhysicalPx;
    }
    final rawNext = current + step;
    final snappedNext = ((rawNext * dpr).roundToDouble() / dpr).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // Guarantee forward progress toward _target without stalling or overshooting.
    final next =
        ((snappedNext - current) * remaining <= 0 ||
            (snappedNext - _target) * remaining > 0)
        ? _target
        : snappedNext;
    _lastApplied = next;
    position.jumpTo(next);
    if ((_target - next).abs() <= onePhysicalPx * 0.5) {
      _stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: widget.child,
    );
  }
}

class HiddenBarScrollBehavior extends BaseScrollBehavior {
  const HiddenBarScrollBehavior();

  @override
  bool showScrollbar(BuildContext context) => false;
}

class ShowBarScrollBehavior extends BaseScrollBehavior {
  const ShowBarScrollBehavior({super.scrollbarPadding});

  @override
  bool showScrollbar(BuildContext context) => true;
}

class NextClampingScrollPhysics extends ClampingScrollPhysics {
  const NextClampingScrollPhysics({super.parent});

  @override
  NextClampingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return NextClampingScrollPhysics(parent: buildParent(ancestor));
  }

  // iOS momentum is sized for its friction fling; a clamping one multiplies it.
  @override
  double carriedMomentum(double existingVelocity) => 0;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final Tolerance tolerance = toleranceFor(position);
    if (position.outOfRange) {
      double? end;
      if (position.pixels > position.maxScrollExtent) {
        end = position.maxScrollExtent;
      }
      if (position.pixels < position.minScrollExtent) {
        end = position.minScrollExtent;
      }
      assert(end != null);
      return ScrollSpringSimulation(
        spring,
        end!,
        end,
        min(0.0, velocity),
        tolerance: tolerance,
      );
    }
    if (velocity.abs() < tolerance.velocity) {
      return null;
    }
    if (velocity > 0.0 && position.pixels >= position.maxScrollExtent) {
      return null;
    }
    if (velocity < 0.0 && position.pixels <= position.minScrollExtent) {
      return null;
    }
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      tolerance: tolerance,
    );
  }
}

class FollowEndScrollPhysics extends NextClampingScrollPhysics {
  const FollowEndScrollPhysics({required this.isFollowing, super.parent});

  final ValueGetter<bool> isFollowing;

  static bool isAtEnd(ScrollMetrics metrics) =>
      metrics.pixels >= metrics.maxScrollExtent - precisionErrorTolerance;

  @override
  FollowEndScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FollowEndScrollPhysics(
      isFollowing: isFollowing,
      parent: buildParent(ancestor),
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (isFollowing() && isAtEnd(oldPosition)) {
      return newPosition.maxScrollExtent;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

mixin ScrubbableScrollPosition on ScrollPosition {
  bool isScrubbing = false;
}

/// Where a page or sheet list opens: [initialScrollOffset] down from the top
/// the reader sees, which a reversed list reaches at its maximum offset. One
/// controller serves lists that read either way, as a feed and its grouped
/// form do, so only the list knows which offset is its top.
double initialPixelsFromTop(ScrollContext context, double initialScrollOffset) {
  if (context.axisDirection != AxisDirection.up) {
    return initialScrollOffset;
  }
  assert(initialScrollOffset == 0, 'A reversed list opens at its top.');
  return double.maxFinite;
}

/// Lays a list out in its first frame at an offset given past its end, as
/// one opening at its newest item asks with double.maxFinite. Flutter keeps
/// that offset through the first layout, which builds no item, and springs
/// back to the end a frame later, the first frame a pushed page moves in.
mixin InitialPixelsInRange on ScrollPosition {
  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (!hasContentDimensions && hasPixels) {
      final inRange = clampDouble(pixels, minScrollExtent, maxScrollExtent);
      if (inRange != pixels) {
        correctPixels(inRange);
        return false;
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// Drags move the sheet until it opens fully, so a scrollbar hides till then.
mixin SheetScrollController on ScrollController {
  ValueListenable<bool> get sheetOpen;
}
