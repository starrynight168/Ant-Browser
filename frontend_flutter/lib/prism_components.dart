import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

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
      contentPadding: contentPadding,
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
          padding: const EdgeInsets.only(left: 12, bottom: 5),
          child: Text(
            label,
            style: prism.AppTextStyle.footnote
                .of(context)
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
          padding: const EdgeInsets.only(left: 12, bottom: 5),
          child: Text(
            label,
            style: prism.AppTextStyle.footnote
                .of(context)
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
      icon: icon ?? const Text('⋯'),
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
  Widget build(BuildContext context) => prism.Chip(
    label: switch (label) {
      Text(:final data) => data ?? '',
      _ => '',
    },
    selected: selected,
    onPressed:
        onPressed ?? (onSelected == null ? null : () => onSelected!(!selected)),
    onDeleted: onDeleted,
  );
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
        radius: 16,
        onPressed: enabled ? open : null,
        inert: !enabled,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.isEmpty ? (widget.decoration.hintText ?? '') : label,
                overflow: TextOverflow.ellipsis,
                style: prism.AppTextStyle.body
                    .of(context)
                    .copyWith(color: colors.onSurface),
              ),
            ),
            const SizedBox(width: 12),
            Text('⌄', style: prism.AppTextStyle.body.of(context)),
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
          padding: const EdgeInsets.only(left: 12, bottom: 5),
          child: Text(
            labelText,
            style: prism.AppTextStyle.footnote
                .of(context)
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

  @override
  Widget build(BuildContext context) => prism.AlertDialog(
    title: _titleText,
    child: content,
    actions: actions,
    hasFields: hasFields,
    destructive: destructive,
    padding: padding,
  );
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
  Widget build(BuildContext context) => prism.TonalButtonTheme(
    size: prism.TonalButtonSize.bar,
    child: icon == null
        ? prism.FilledButton(onPressed: onPressed, style: style, child: child)
        : prism.FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon!,
            label: child,
          ),
  );
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
