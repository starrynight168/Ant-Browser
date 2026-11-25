import 'package:prism_ui/prism_ui.dart' as prism;

import 'prism_widgets.dart';

class CloseDialog extends StatelessWidget {
  const CloseDialog({required this.isWindows, super.key});

  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final dangerTone = PrismToneColors.of(context, PrismTone.danger);
    const pillHeight = Size(double.infinity, 46);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: prism.Surface(
        color: colors.surface,
        shape: prism.AppShape.all(prism.AppCorner.alert),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              prism.Surface(
                color: dangerTone.bg,
                shape: prism.AppShape.lg,
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Center(
                    child: PrismGlyph(
                      AntGlyphs.exit,
                      size: 22,
                      color: dangerTone.fg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '关闭 Ant Browser？',
                style: prism.AppTextStyle.title3.of(context, emphasized: true),
              ),
              const SizedBox(height: 6),
              Text(
                '可仅退出应用，或连同浏览器一起关闭。',
                textAlign: TextAlign.center,
                style: prism.AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 20),
              if (isWindows) ...[
                prism.FilledButton.icon(
                  style: prism.ButtonStyle.from(
                    backgroundColor: colors.surfaceContainerHigh,
                    foregroundColor: colors.onSurface,
                    minimumSize: pillHeight,
                    shape: prism.AppShape.full,
                  ),
                  onPressed: () => Navigator.pop(context, 'minimize'),
                  icon: const PrismGlyph(AntGlyphs.alignBottom, size: 17),
                  label: const Text('最小化到托盘'),
                ),
                const SizedBox(height: 8),
              ],
              prism.FilledButton(
                style: prism.ButtonStyle.from(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  minimumSize: pillHeight,
                  shape: prism.AppShape.full,
                ),
                onPressed: () => Navigator.pop(context, 'quit-app'),
                child: const Text('仅退出应用'),
              ),
              const SizedBox(height: 8),
              prism.FilledButton(
                style: prism.ButtonStyle.from(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                  minimumSize: pillHeight,
                  shape: prism.AppShape.full,
                ),
                onPressed: () => Navigator.pop(context, 'quit-all'),
                child: const Text('退出应用与浏览器'),
              ),
              const SizedBox(height: 8),
              prism.FilledButton(
                style: prism.ButtonStyle.from(
                  backgroundColor: colors.surfaceContainerLow,
                  foregroundColor: colors.onSurfaceVariant,
                  minimumSize: pillHeight,
                  shape: prism.AppShape.full,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
