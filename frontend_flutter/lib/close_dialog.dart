import 'package:material_ui/material_ui.dart';

class CloseDialog extends StatelessWidget {
  const CloseDialog({required this.isWindows, super.key});

  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.exit_to_app, color: Theme.of(context).colorScheme.onErrorContainer),
              ),
              const SizedBox(height: 16),
              Text('关闭 Ant Browser？', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '可仅退出应用，或连同浏览器一起关闭。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 22),
              if (isWindows) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'minimize'),
                    icon: const Icon(Icons.vertical_align_bottom, size: 18),
                    label: const Text('最小化到托盘'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(context, 'quit-app'),
                  child: const Text('仅退出应用'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.pop(context, 'quit-all'),
                  child: const Text('退出应用与浏览器'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ],
          ),
        ),
      ),
    );
  }
}
