import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart' as prism_icons;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'prism_glyphs.dart';

enum PrismTone { neutral, primary, success, warning, danger, info }

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
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
      hoverScale: 1.03,
      pressScale: 0.96,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            prism_icons.GlyphIcon(effectiveGlyph, size: 18, color: palette.fg),
            const SizedBox(width: 10),
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
                  Text(
                    message,
                    style: prism.AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: palette.fg),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 页面顶部上下文栏（settings_page 样板）：
/// 左侧 Surface 图标块 + 标题 + 副标题，右侧为页面操作按钮组。
/// 页面主体配合 `EdgeInsets.fromLTRB(24, 6, 24, 24)` 外边距使用，
/// 标题不再重复渲染页面大标题（外壳 _PageHeader 已展示）。
class PrismPageContextBar extends StatelessWidget {
  const PrismPageContextBar({
    super.key,
    required this.glyph,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final prism_icons.Glyph glyph;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: prism.AppTextStyle.title3.of(context, emphasized: true),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: prism.AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class PrismSectionCard extends StatelessWidget {
  const PrismSectionCard({
    super.key,
    this.title,
    this.glyph,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.radius = prism.AppCorner.xl,
  });

  final String? title;
  final prism_icons.Glyph? glyph;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: margin,
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
                ),
                const prism.Divider(height: 1),
              ],
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
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
  });

  final String label;
  final String value;
  final String? subtitle;
  final prism_icons.Glyph? glyph;
  final PrismTone tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final palette = PrismToneColors.of(context, tone);
    final card = prism.Card(
      radius: prism.AppCorner.lg,
      onPressed: onPressed,
      inert: onPressed == null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            prism.Surface(
              color: palette.bg,
              shape: prism.AppShape.md,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: prism_icons.GlyphIcon(
                  glyph!,
                  size: 18,
                  color: palette.fg,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: prism.AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: prism.AppTextStyle.title3.of(
                    context,
                    emphasized: true,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: prism.AppTextStyle.caption2
                        .of(context)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (onPressed == null) return card;
    return PrismHoverMotion(hoverScale: 1.02, pressScale: 0.98, child: card);
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
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
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
    this.height = 40,
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
      style: TextStyle(
        fontFamily: 'Consolas',
        fontSize: 12.5,
        height: 1.5,
        color: colors.onSurface,
      ),
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
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    child: body,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
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
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
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
    return prism.Card(
      radius: prism.AppCorner.lg,
      inert: true,
      padding: const EdgeInsets.all(14),
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
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
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
          padding: const EdgeInsets.only(left: 10, bottom: 5),
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
          padding: const EdgeInsets.only(left: 10, bottom: 5),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          padding: const EdgeInsets.only(left: 10, bottom: 5),
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
                      padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
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
                            const EdgeInsets.fromLTRB(24, 18, 24, 18),
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
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 8,
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
    this.hoverScale = 1.025,
    this.pressScale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double hoverScale;
  final double pressScale;

  @override
  State<PrismHoverMotion> createState() => _PrismHoverMotionState();
}

class _PrismHoverMotionState extends State<PrismHoverMotion> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final scale = _pressed
        ? widget.pressScale
        : _hovered
        ? widget.hoverScale
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
          duration: Duration(milliseconds: _pressed ? 90 : 180),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
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
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
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
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsets? padding;
  final double? radius;
  final VoidCallback? onPressed;
  final ShapeBorder? shape;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final card = Padding(
      padding: margin,
      child: prism.Card(
        radius: radius ?? prism.AppCorner.xl,
        shape: shape is OutlinedBorder ? shape as OutlinedBorder : null,
        padding: padding,
        onPressed: onPressed,
        inert: onPressed == null,
        child: child,
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
