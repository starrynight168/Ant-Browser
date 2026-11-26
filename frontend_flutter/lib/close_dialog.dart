import 'package:prism_ui/prism_ui.dart' as prism;

import 'prism_widgets.dart';

class CloseDialog extends StatelessWidget {
  const CloseDialog({required this.isWindows, super.key});

  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    final theme = prism.Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dangerBg = colors.error.withValues(alpha: isDark ? 0.24 : 0.13);
    final primaryBg = colors.primary.withValues(alpha: isDark ? 0.24 : 0.13);
    final neutralBg = colors.onSurface.withValues(alpha: isDark ? 0.10 : 0.06);
    const pillSize = Size(double.infinity, 48);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 368),
      child: prism.Surface(
        color: colors.surface,
        shape: prism.AppShape.all(prism.AppCorner.alert),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '关闭 Ant Browser？',
                textAlign: TextAlign.center,
                style: prism.AppTextStyle.title3.of(context, emphasized: true),
              ),
              const SizedBox(height: 8),
              Text(
                '可仅退出应用，或连同浏览器一起关闭。',
                textAlign: TextAlign.center,
                style: prism.AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 22),
              if (isWindows) ...[
                PrismHoverMotion(
                  hoverScale: 1.025,
                  pressScale: 0.975,
                  child: prism.FilledButton.icon(
                    style: prism.ButtonStyle.from(
                      backgroundColor: neutralBg,
                      foregroundColor: colors.onSurface,
                      minimumSize: pillSize,
                      shape: prism.AppShape.full,
                    ),
                    onPressed: () => Navigator.pop(context, 'minimize'),
                    icon: const PrismGlyph(AntGlyphs.alignBottom, size: 17),
                    label: const Text('最小化到托盘'),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              PrismHoverMotion(
                hoverScale: 1.025,
                pressScale: 0.975,
                child: prism.FilledButton(
                  style: prism.ButtonStyle.from(
                    backgroundColor: primaryBg,
                    foregroundColor: colors.primary,
                    minimumSize: pillSize,
                    shape: prism.AppShape.full,
                  ),
                  onPressed: () => Navigator.pop(context, 'quit-app'),
                  child: const Text('仅退出应用'),
                ),
              ),
              const SizedBox(height: 14),
              PrismHoverMotion(
                hoverScale: 1.025,
                pressScale: 0.975,
                child: prism.FilledButton(
                  style: prism.ButtonStyle.from(
                    backgroundColor: dangerBg,
                    foregroundColor: colors.error,
                    minimumSize: pillSize,
                    shape: prism.AppShape.full,
                  ),
                  onPressed: () => Navigator.pop(context, 'quit-all'),
                  child: const Text('退出应用与浏览器'),
                ),
              ),
              const SizedBox(height: 14),
              PrismHoverMotion(
                hoverScale: 1.025,
                pressScale: 0.975,
                child: prism.FilledButton(
                  style: prism.ButtonStyle.from(
                    backgroundColor: neutralBg,
                    foregroundColor: colors.onSurfaceVariant,
                    minimumSize: pillSize,
                    shape: prism.AppShape.full,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
