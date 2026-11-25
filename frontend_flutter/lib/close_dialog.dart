import 'package:prism_ui/prism_ui.dart' as prism;

import 'prism_widgets.dart';

class CloseDialog extends StatelessWidget {
  const CloseDialog({required this.isWindows, super.key});

  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final dangerTone = PrismToneColors.of(context, PrismTone.danger);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: prism.Surface(
        color: colors.surface,
        shape: prism.AppShape.all(prism.AppCorner.xxl),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              prism.Surface(
                color: dangerTone.bg,
                shape: prism.AppShape.lg,
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: PrismGlyph(
                      AntGlyphs.exit,
                      size: 24,
                      color: dangerTone.fg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '关闭 Ant Browser？',
                style: prism.AppTextStyle.title2.of(context, emphasized: true),
              ),
              const SizedBox(height: 8),
              Text(
                '可仅退出应用，或连同浏览器一起关闭。',
                textAlign: TextAlign.center,
                style: prism.AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 22),
              if (isWindows) ...[
                SizedBox(
                  width: double.infinity,
                  child: prism.OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'minimize'),
                    icon: const PrismGlyph(AntGlyphs.alignBottom, size: 18),
                    label: const Text('最小化到托盘'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: PrismTonalButton(
                  onPressed: () => Navigator.pop(context, 'quit-app'),
                  child: const Text('仅退出应用'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: prism.FilledButton(
                  style: prism.ButtonStyle.from(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  onPressed: () => Navigator.pop(context, 'quit-all'),
                  child: const Text('退出应用与浏览器'),
                ),
              ),
              const SizedBox(height: 6),
              prism.TextButton(
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
