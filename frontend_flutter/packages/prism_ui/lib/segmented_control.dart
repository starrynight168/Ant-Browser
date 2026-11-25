import 'package:flutter/widgets.dart';
import 'package:prism_ui/card_surface.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/press_surface.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/typography.dart';

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  static const double _height = 44;
  static const double _inset = 4;

  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final count = segments.length;
    final index = segments.indexWhere((segment) => segment.$1 == value);
    return Container(
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.full,
      ),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              duration: context.motionDuration(
                const Duration(milliseconds: 250),
              ),
              curve: Curves.easeOutCubic,
              alignment: AlignmentDirectional(
                count == 1 ? 0 : index * 2 / (count - 1) - 1,
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colorScheme.primary,
                    shape: AppShape.full,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final (option, label) in segments)
                Expanded(
                  child: _SegmentButton(
                    label: label,
                    selected: option == value,
                    onPressed: option == value
                        ? () {}
                        : () => onChanged(option),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatefulWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final noMotion = context.disableAnimations;
    final scale = noMotion
        ? 1.0
        : _pressed
        ? 0.94
        : _hovered
        ? 1.05
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
        child: PressSurface(
          fill: const Color(0x00000000),
          shape: AppShape.full,
          look: widget.selected ? PressLook.none : PressLook.ink,
          ringStandsOff: widget.selected,
          selected: widget.selected,
          childFills: true,
          onPressed: widget.onPressed,
          child: Center(
            child: AnimatedScale(
              scale: scale,
              duration: noMotion
                  ? Duration.zero
                  : Duration(milliseconds: _pressed ? 85 : 165),
              curve: Curves.easeOutCubic,
              child: AnimatedDefaultTextStyle(
                duration: context.motionDuration(
                  const Duration(milliseconds: 200),
                ),
                style: AppTextStyle.subheadline
                    .of(context, emphasized: widget.selected || _hovered)
                    .copyWith(
                      color: widget.selected
                          ? colorScheme.onPrimary
                          : _hovered
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
