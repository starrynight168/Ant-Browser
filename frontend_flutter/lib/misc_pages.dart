import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';

class DocsPage extends StatefulWidget {
  const DocsPage({super.key});
  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  int _selected = 0;
  static const _sections = <(String, IconData, String)>[
    (
      '快速开始',
      Icons.rocket_launch_outlined,
      '1. 在“内核管理”下载或识别 Chrome 内核。\n2. 在“代理池配置”添加代理，或选择直连。\n3. 在“实例列表”新建浏览器实例并启动。\n4. 需要插件时，在“插件包管理”安装并设置默认安装。',
    ),
    (
      '实例迁移',
      Icons.swap_horiz,
      '批量导出：实例列表 → 勾选实例 → 导出。\n单个导出：实例列表 → 更多 → 导出。\n导入实例：实例列表 → 导入实例 → 选择 ZIP。\n导出前先停止实例，避免浏览器数据文件被占用。',
    ),
    (
      'Launch API',
      Icons.api_outlined,
      '本地 Launch Server 默认监听 127.0.0.1:19900。\n启动实例：POST /api/launch\n查询健康状态：GET /api/health\n等待实例与 CDP 可用：POST /api/runtime/session\n\n调用接口时请使用本机地址，并根据响应中的字段判断启动结果。',
    ),
    (
      '代理与故障排查',
      Icons.public_outlined,
      '代理配置支持 HTTP、HTTPS 与 SOCKS5。可在代理池测试连通性，查看延迟和错误。\n实例无法启动时，依次检查浏览器内核路径、代理状态和实例日志。\n订阅代理刷新后，可在代理池检查异常节点及引用关系。',
    ),
    (
      '备份与恢复',
      Icons.backup_outlined,
      '在“备份与恢复”设置本地目录，然后创建完整备份。\n恢复备份会修改当前本地数据，操作前请确认备份文件和实例状态。\nS3 存储需要先在 S3 设置中填写兼容服务的连接信息并测试。',
    ),
    (
      'SKILL 使用',
      Icons.auto_awesome_outlined,
      'Ant Browser 与 OpenClaw 需要安装在同一台电脑。确认 Launch Server 可访问，并安装 ant-chrome-openclaw skill。\n\n在 OpenClaw 对话中先写“使用 ant-chrome-openclaw skill”，再说明要操作的实例和目标。优先用 launchCode、profileId 或 profileName 指定实例；只有 debugReady=true 且 cdpUrl 不为空时才接管。\n\n停止浏览器接管只会断开 OpenClaw，不会关闭 Ant Browser 实例。',
    ),
  ];

  Future<void> _openProjectRoot() async {
    try {
      await AppBridge.call('OpenProjectRoot');
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = _sections[_selected];
    final colors = prism.Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 230,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '文档目录',
                  style: prism.AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              for (var i = 0; i < _sections.length; i++)
                PrismListTile(
                  selected: i == _selected,
                  selectedTileColor: colors.secondaryContainer,
                  selectedColor: colors.onSecondaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  leading: Icon(_sections[i].$2),
                  title: Text(_sections[i].$1),
                  onTap: () => setState(() => _selected = i),
                ),
            ],
          ),
        ),
        Container(width: 1, color: colors.outlineVariant),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, .012),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: ListView(
              key: ValueKey(_selected),
              padding: const EdgeInsets.fromLTRB(30, 24, 30, 36),
              children: [
                Row(
                  children: [
                    Icon(section.$2, color: colors.primary),
                    const SizedBox(width: 10),
                    Text(
                      section.$1,
                      style: prism.AppTextStyle.pageTitle.of(context),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                PrismCard(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: prism.SelectableText(
                      section.$3,
                      style: const TextStyle(fontSize: 15, height: 1.9),
                    ),
                  ),
                ),
                if (_selected == 2) ...[
                  const SizedBox(height: 14),
                  PrismCard(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: prism.SelectableText(
                        'curl http://127.0.0.1:19900/api/health\n\ncurl -X POST http://127.0.0.1:19900/api/launch \\\n  -H "Content-Type: application/json" \\\n  -d \'{"code":"BUYER_001","skipDefaultStartUrls":true}\'',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_selected == 5) ...[
                  const SizedBox(height: 14),
                  PrismCard(
                    child: PrismListTile(
                      title: const Text('打开项目根目录'),
                      subtitle: const Text('SKILL 安装命令默认从这个目录运行。'),
                      trailing: prism.OutlinedButton.icon(
                        onPressed: _openProjectRoot,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('打开目录'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChartsPage extends StatelessWidget {
  const ChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('图表案例展示', style: prism.AppTextStyle.pageTitle.of(context)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _ChartCard(
              title: '月度访问量',
              child: CustomPaint(
                size: const Size(420, 220),
                painter: _LineChartPainter(colors: colors),
              ),
            ),
            _ChartCard(
              title: '分类数据',
              child: CustomPaint(
                size: const Size(420, 220),
                painter: _BarChartPainter(colors: colors),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 480,
    child: PrismCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Center(child: child),
          ],
        ),
      ),
    ),
  );
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.colors});

  final prism.ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(12, y), Offset(size.width - 8, y), grid);
    }
    const values = [0.72, 0.58, 0.65, 0.32, 0.45, 0.22, 0.35, 0.16];
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(
        16 + (size.width - 32) * i / (values.length - 1),
        size.height * values[i],
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.primary
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({required this.colors});

  final prism.ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    const heights = [.42, .72, .55, .9, .63, .36, .78];
    final seriesColors = [colors.primary, colors.tertiary, colors.secondary];
    final width = size.width / 12;
    for (var i = 0; i < heights.length; i++) {
      final h = size.height * heights[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(12 + i * size.width / 8, size.height - h, width, h),
          const Radius.circular(5),
        ),
        Paint()..color = seriesColors[i % seriesColors.length],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
