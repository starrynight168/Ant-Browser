import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

class CloseDialog extends StatelessWidget {
  const CloseDialog({required this.isWindows, super.key});

  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: prism.Card(
        radius: 28,
        padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.exit_to_app, color: colors.onErrorContainer),
            ),
            const SizedBox(height: 16),
            Text(
              '关闭 Ant Browser？',
              style: prism.AppTextStyle.title2.of(context),
            ),
            const SizedBox(height: 8),
            Text(
              '可仅退出应用，或连同浏览器一起关闭。',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 22),
            if (isWindows) ...[
              SizedBox(
                width: double.infinity,
                child: prism.OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'minimize'),
                  icon: const Icon(Icons.vertical_align_bottom, size: 18),
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
    );
  }
}
