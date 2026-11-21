import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

class PrismCard extends StatelessWidget {
  const PrismCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.all(4),
    this.padding = EdgeInsets.zero,
    this.radius,
    this.onPressed,
    this.elevation = 0,
    this.shape,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsets? padding;
  final double? radius;
  final VoidCallback? onPressed;
  final double elevation;
  final ShapeBorder? shape;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: prism.Card(
        radius: radius,
        padding: padding,
        onPressed: onPressed,
        inert: onPressed == null,
        child: child,
      ),
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
      padding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 16),
      minHeight: isThreeLine
          ? 72
          : dense
          ? 44
          : 56,
      minVerticalPadding: dense ? 6 : 10,
    );
    final content = prism.Surface(
      color: selected
          ? selectedTileColor ?? const Color(0x00000000)
          : const Color(0x00000000),
      shape: shape,
      child: row,
    );
    if (onTap == null) return content;
    return prism.PressRegion(onTap: onTap, shape: shape, child: content);
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
