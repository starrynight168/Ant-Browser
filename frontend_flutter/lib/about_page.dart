import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'wails_bridge.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '读取中';
  bool _checking = false;
  Map<String, dynamic>? _updateResult;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final config = await WailsBridge.call('GetAppConfig');
      if (mounted)
        setState(
          () =>
              _version = config is Map ? '${config['version'] ?? '未知'}' : '未知',
        );
    } catch (_) {
      if (mounted) setState(() => _version = '未知');
    }
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await WailsBridge.call('CheckForUpdates');
      if (mounted) {
        setState(
          () => _updateResult = result is Map
              ? Map<String, dynamic>.from(result)
              : null,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _updateResult = {'error': error.toString()});
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        final cards = [
          Expanded(flex: 5, child: _authorCard()),
          Expanded(flex: 6, child: _projectCard()),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: compact
                ? Column(
                    children: [
                      _authorCard(),
                      const SizedBox(height: 16),
                      _projectCard(),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [cards[0], const SizedBox(width: 16), cards[1]],
                  ),
          ),
        );
      },
    );
  }

  Widget _authorCard() {
    final colors = prism.Theme.of(context).colorScheme;
    return _AboutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '志',
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '志字辈小蚂蚁',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '全栈开发工程师',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '热爱开源，专注于 Web 和桌面应用开发。致力于打造优雅、高效的开发工具和框架。',
            style: TextStyle(height: 1.7, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _MetaLabel(icon: Icons.place_outlined, text: '中国'),
              _MetaLabel(icon: Icons.calendar_month_outlined, text: '加入于 2020'),
            ],
          ),
          const SizedBox(height: 20),
          const Text('技能', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Go',
              'Flutter',
              'Dart',
              'Wails',
              'TypeScript',
              'Node.js',
              'Docker',
            ].map((skill) => _SkillChip(label: skill)).toList(),
          ),
          const SizedBox(height: 18),
          prism.OutlinedButton.icon(
            onPressed: () =>
                WailsBridge.openExternal('https://github.com/black-ant'),
            icon: const Icon(Icons.code, size: 18),
            label: const Text('GitHub'),
          ),
        ],
      ),
    );
  }

  Widget _projectCard() {
    final colors = prism.Theme.of(context).colorScheme;
    final result = _updateResult;
    final updateText = result == null
        ? ''
        : result['updateAvailable'] == true
        ? '发现新版本 ${result['latestVersion'] ?? ''}'
        : result['error']?.toString().isNotEmpty == true
        ? result['error'].toString()
        : '当前已是最新版本';
    return _AboutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ant Browser',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '面向多账号隔离、代理绑定和本地环境管理的桌面浏览器工具。',
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 20),
          const Text('项目能力', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          Text(
            '管理浏览器实例、代理池、浏览器内核和扩展插件，支持标签检索及快捷启动。',
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Flutter',
              'Go',
              'Wails',
            ].map((item) => _SkillChip(label: item)).toList(),
          ),
          const SizedBox(height: 22),
          const prism.Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前版本：$_version',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              PrismTonalButton(
                onPressed: _checking ? null : _checkUpdate,
                child: _checking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: PrismProgressIndicator(),
                      )
                    : const Text('检查更新'),
              ),
            ],
          ),
          if (updateText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              updateText,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
            if (result?['releaseUrl']?.toString().isNotEmpty == true)
              prism.TextButton.icon(
                onPressed: () =>
                    WailsBridge.openExternal(result!['releaseUrl'].toString()),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开下载页面'),
              ),
          ],
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PrismCard(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: prism.Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(22), child: child),
    );
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return prism.TonalChip(
      label: label,
      color: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
    );
  }
}
