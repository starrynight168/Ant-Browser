import 'package:prism_ui/prism_ui.dart' as prism;

import 'prism_widgets.dart';

class CloseDialog extends StatelessWidget {
  const CloseDialog({
    required this.isWindows,
    this.backupImportInProgress = false,
    this.backupImportProgress = 0,
    this.backupImportMessage = '',
    super.key,
  });

  final bool isWindows;
  final bool backupImportInProgress;
  final int backupImportProgress;
  final String backupImportMessage;

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
                backupImportInProgress ? '正在导入备份' : '关闭 Ant Browser？',
                textAlign: TextAlign.center,
                style: prism.AppTextStyle.title3.of(context, emphasized: true),
              ),
              const SizedBox(height: 8),
              Text(
                backupImportInProgress
                    ? '关闭应用可能中断备份导入，导致数据不完整。'
                    : '可仅退出应用，或连同浏览器一起关闭。',
                textAlign: TextAlign.center,
                style: prism.AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant, height: 1.45),
              ),
              if (backupImportInProgress) ...[
                const SizedBox(height: 14),
                PrismBanner(
                  tone: PrismTone.warning,
                  title: backupImportProgress > 0
                      ? '导入进度：$backupImportProgress%'
                      : '备份导入进行中',
                  message: backupImportMessage.isEmpty
                      ? '建议等待导入完成后再关闭应用。'
                      : backupImportMessage,
                ),
              ],
              const SizedBox(height: 22),
              if (backupImportInProgress) ...[
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
                    child: const Text('继续导入'),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (isWindows && !backupImportInProgress) ...[
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
              if (!backupImportInProgress) PrismHoverMotion(
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
                  child: Text(
                    backupImportInProgress ? '仍要关闭' : '退出应用与浏览器',
                  ),
                ),
              ),
              if (!backupImportInProgress) ...[
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
            ],
          ),
        ),
      ),
    );
  }
}
