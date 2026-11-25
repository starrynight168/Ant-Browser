import 'dart:convert';
import 'dart:math' as math;

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'docs_api_details.dart';
import 'docs_content.dart';

class _DocsItem {
  const _DocsItem(this.id, this.label, this.summary);

  final String id;
  final String label;
  final String summary;
}

class _DocsGroup {
  const _DocsGroup(this.label, this.icon, this.items);

  final String label;
  final IconData icon;
  final List<_DocsItem> items;
}

class DocsPage extends StatefulWidget {
  const DocsPage({super.key});
  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  String _selected = 'tutorial-basic';
  static const _groups = <_DocsGroup>[
    _DocsGroup('使用教程', Icons.menu_book_outlined, [
      _DocsItem('tutorial-basic', '基础使用', '应用上手流程、菜单入口和最小接口链路。'),
      _DocsItem(
        'tutorial-skill',
        'SKILL 使用',
        'OpenClaw 接入 ant-chrome-openclaw 的安装、提问模板和稳定使用规则。',
      ),
      _DocsItem('tutorial-flow', '操作流程', '按步骤串起内核、代理、实例和接口调用。'),
    ]),
    _DocsGroup('更新日志', Icons.history, [
      _DocsItem('changelog-versions', '版本更新', '按大版本查看主要变化。'),
    ]),
    _DocsGroup('内核介绍', Icons.memory, [
      _DocsItem('core-management', '内核渠道与用法', '内核下载来源、目录结构和应用内使用方式。'),
    ]),
    _DocsGroup('代理介绍', Icons.public_outlined, [
      _DocsItem('proxy-usage', '代理池使用', '代理类型、导入方式和实例绑定建议。'),
    ]),
    _DocsGroup('插件介绍', Icons.extension_outlined, [
      _DocsItem('extension-usage', '插件包管理', '插件安装、实例限制、分组选择和单实例配置。'),
    ]),
    _DocsGroup('接口介绍', Icons.api_outlined, [
      _DocsItem('api-overview', '接口总览', '认证、选择规则和全部对外接口索引。'),
      _DocsItem('api-profiles-launch', '实例与启动', '实例配置、按 Code 启动和参数化启动。'),
      _DocsItem('api-runtime', '运行态与接管', 'runtime session、活动实例和统一 CDP 入口。'),
      _DocsItem('api-automation', '脚本自动化', '自动化接口总览、字段规则和调用顺序。'),
      _DocsItem('api-support', '排障与日志', '调用日志、常见错误码和排查顺序。'),
      _DocsItem('api-demo', '启动 API 演示', '在应用内直接演练启动 API 的完整链路。'),
    ]),
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
    final section = _groups
        .expand((group) => group.items)
        .firstWhere((item) => item.id == _selected);
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
              for (final group in _groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                  child: Text(
                    group.label,
                    style: prism.AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                for (final item in group.items)
                  PrismListTile(
                    selected: item.id == _selected,
                    selectedTileColor: colors.secondaryContainer,
                    selectedColor: colors.onSecondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    leading: Icon(group.icon),
                    title: Text(item.label),
                    onTap: () => setState(() => _selected = item.id),
                  ),
              ],
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
                    Icon(Icons.menu_book_outlined, color: colors.primary),
                    const SizedBox(width: 10),
                    Text(
                      section.label,
                      style: prism.AppTextStyle.pageTitle.of(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  section.summary,
                  style: prism.AppTextStyle.body
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                _DocsMarkdown(
                  source: [
                    docsContent[section.id] ?? '',
                    docsApiDetails[section.id] ?? '',
                  ].where((content) => content.isNotEmpty).join('\n\n'),
                ),
                if (section.id == 'tutorial-skill') ...[
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
                if (section.id == 'api-demo') ...[
                  const SizedBox(height: 14),
                  const _LaunchApiDemoPanel(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DocsMarkdown extends StatelessWidget {
  const _DocsMarkdown({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final children = <Widget>[];
    final code = StringBuffer();
    var inCode = false;
    var codeLanguage = '';

    void addCodeBlock() {
      children.add(
        PrismCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (codeLanguage.isNotEmpty) ...[
                  Text(
                    codeLanguage.toUpperCase(),
                    style: prism.AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                ],
                prism.SelectableText(
                  code.toString().trimRight(),
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      code.clear();
    }

    for (final line in source.replaceAll('\r', '').split('\n')) {
      final value = line.trim();
      if (value.startsWith('```')) {
        if (inCode) {
          addCodeBlock();
          codeLanguage = '';
          inCode = false;
        } else {
          inCode = true;
          codeLanguage = value.substring(3).trim();
        }
        continue;
      }
      if (inCode) {
        code.writeln(line);
        continue;
      }
      if (value.isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      if (value.startsWith('# ')) {
        children.add(
          Text(
            value.substring(2),
            style: prism.AppTextStyle.headline
                .of(context)
                .copyWith(color: colors.onSurface),
          ),
        );
        continue;
      }
      if (value.startsWith('## ') || value.startsWith('### ')) {
        final heading = value.startsWith('### ')
            ? value.substring(4)
            : value.substring(3);
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(
              heading,
              style: prism.AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colors.primary),
            ),
          ),
        );
        continue;
      }
      if (RegExp(r'^[|\s:-]+$').hasMatch(value)) continue;
      if (value.startsWith('|')) {
        final cells = value
            .split('|')
            .where((cell) => cell.trim().isNotEmpty)
            .map((cell) => cell.trim().replaceAll('`', ''))
            .toList();
        children.add(
          PrismCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [for (final cell in cells) Text(cell)],
              ),
            ),
          ),
        );
        continue;
      }
      final bullet = RegExp(r'^([-*]|\d+[.)])\s+(.*)$').firstMatch(value);
      if (bullet != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bullet.group(1) == '-' || bullet.group(1) == '*'
                      ? '•'
                      : bullet.group(1)!,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: prism.SelectableText(
                    bullet.group(2)!.replaceAll('`', ''),
                    style: const TextStyle(fontSize: 15, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      children.add(
        prism.SelectableText(
          value.replaceAll('`', '').replaceAll('**', ''),
          style: const TextStyle(fontSize: 15, height: 1.75),
        ),
      );
    }
    if (inCode) addCodeBlock();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
              title: '折线图示例',
              child: CustomPaint(
                size: const Size(420, 220),
                painter: _LineChartPainter(colors: colors),
              ),
            ),
            _ChartCard(
              title: '柱状图示例',
              child: CustomPaint(
                size: const Size(420, 220),
                painter: _BarChartPainter(colors: colors),
              ),
            ),
            _ChartCard(
              title: '饼图示例',
              child: _PieChart(colors: colors),
            ),
            _ChartCard(
              title: '面积图示例',
              child: CustomPaint(
                size: const Size(420, 220),
                painter: _AreaChartPainter(colors: colors),
              ),
            ),
            _ChartCard(
              title: '复合图表示例',
              child: CustomPaint(
                size: const Size(420, 220),
                painter: _ComposedChartPainter(colors: colors),
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

class _PieChart extends StatelessWidget {
  const _PieChart({required this.colors});

  final prism.ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final slices = [
      ('实例', colors.primary),
      ('代理', colors.secondary),
      ('脚本', colors.tertiary),
      ('其他', colors.onSurfaceVariant),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(210, 180),
          painter: _PieChartPainter(colors: colors),
        ),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final slice in slices)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: slice.$2,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(slice.$1, style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _PieChartPainter extends CustomPainter {
  const _PieChartPainter({required this.colors});

  final prism.ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    const values = [.36, .28, .21, .15];
    final palette = [
      colors.primary,
      colors.secondary,
      colors.tertiary,
      colors.onSurfaceVariant,
    ];
    final diameter = math.min(size.width, size.height) - 8;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: diameter,
      height: diameter,
    );
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = math.pi * 2 * values[i];
      canvas.drawArc(rect, start, sweep, true, Paint()..color = palette[i]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

class _AreaChartPainter extends CustomPainter {
  const _AreaChartPainter({required this.colors});

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
    const values = [.72, .58, .65, .32, .45, .22, .35, .16];
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        16 + (size.width - 32) * i / (values.length - 1),
        size.height * values[i],
      );
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }
    final fill = Path.from(line)
      ..lineTo(size.width - 16, size.height)
      ..lineTo(16, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = colors.primary.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = colors.primary
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AreaChartPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

class _ComposedChartPainter extends CustomPainter {
  const _ComposedChartPainter({required this.colors});

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
    const bars = [.42, .72, .55, .9, .63, .36, .78];
    const lineValues = [.68, .56, .61, .38, .48, .28, .3];
    final barPaint = Paint()..color = colors.secondary.withValues(alpha: 0.8);
    final barWidth = size.width / 16;
    final line = Path();
    for (var i = 0; i < bars.length; i++) {
      final centerX = 28 + i * (size.width - 56) / (bars.length - 1);
      final height = size.height * bars[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            centerX - barWidth / 2,
            size.height - height,
            barWidth,
            height,
          ),
          const Radius.circular(4),
        ),
        barPaint,
      );
      final point = Offset(centerX, size.height * lineValues[i]);
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = colors.primary
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ComposedChartPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

/// 启动 API 演示面板：对应旧版文档中心的 LaunchDemoPanel，
/// 在应用内逐步演练 健康检查 → 创建演示实例 → 启动 → 删除 的完整链路。
class _LaunchApiDemoPanel extends StatefulWidget {
  const _LaunchApiDemoPanel();

  @override
  State<_LaunchApiDemoPanel> createState() => _LaunchApiDemoPanelState();
}

class _LaunchApiDemoPanelState extends State<_LaunchApiDemoPanel> {
  final List<String> _logs = [];
  String _demoProfileId = '';
  String _demoLaunchCode = '';
  bool _busy = false;

  void _log(String message) {
    if (!mounted) return;
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.add('[$time] $message');
      if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
    });
  }

  Future<dynamic> _run(
    String label,
    String method, [
    List<Object?> args = const [],
  ]) async {
    _log('$label → 调用 $method');
    try {
      final value = await AppBridge.call(method, args);
      final summary = value is Map
          ? (value['ok'] == true || value['success'] == true ? '成功' : '完成')
          : '完成';
      _log('$label ← $summary');
      return value;
    } catch (error) {
      _log('$label ← 失败：$error');
      if (mounted) showPrismNotice(context, '$label失败：$error');
      rethrow;
    }
  }

  Future<void> _healthCheck() async {
    setState(() => _busy = true);
    try {
      final value = await _run('健康检查', 'AutomationDemoHealthCheck');
      if (value is Map) _log('健康检查结果：${jsonEncode(value)}');
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createProfile() async {
    setState(() => _busy = true);
    try {
      final value = await _run('创建演示实例', 'AutomationDemoCreateProfile');
      if (value is Map) {
        final profile = value['profile'] is Map
            ? Map<String, dynamic>.from(value['profile'] as Map)
            : value;
        _demoProfileId = '${profile['profileId'] ?? ''}';
        _demoLaunchCode = '${profile['launchCode'] ?? ''}';
        _log('演示实例：$_demoProfileId（启动码 $_demoLaunchCode）');
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _launchProfile() async {
    if (_demoLaunchCode.isEmpty) {
      showPrismNotice(context, '请先创建演示实例');
      return;
    }
    setState(() => _busy = true);
    try {
      final value = await _run('启动演示实例', 'AutomationDemoLaunchProfile', [
        _demoLaunchCode,
      ]);
      if (value is Map) _log('启动结果：${jsonEncode(value)}');
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProfile() async {
    if (_demoProfileId.isEmpty) {
      showPrismNotice(context, '请先创建演示实例');
      return;
    }
    setState(() => _busy = true);
    try {
      await _run('删除演示实例', 'AutomationDemoDeleteProfile', [_demoProfileId]);
      _demoProfileId = '';
      _demoLaunchCode = '';
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return PrismCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '演示会创建一个临时实例并启动，验证启动 API 链路后可一键清理；'
              '不会影响已有实例。',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                prism.OutlinedButton.icon(
                  onPressed: _busy ? null : _healthCheck,
                  icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                  label: const Text('健康检查'),
                ),
                prism.OutlinedButton.icon(
                  onPressed: _busy || _demoProfileId.isNotEmpty
                      ? null
                      : _createProfile,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_demoProfileId.isEmpty ? '创建演示实例' : '演示实例已创建'),
                ),
                prism.OutlinedButton.icon(
                  onPressed: _busy || _demoLaunchCode.isEmpty
                      ? null
                      : _launchProfile,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('启动演示实例'),
                ),
                prism.TextButton.icon(
                  onPressed: _busy || _demoProfileId.isEmpty
                      ? null
                      : _deleteProfile,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除演示实例'),
                ),
              ],
            ),
            if (_demoProfileId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '当前演示实例：$_demoProfileId · 启动码 $_demoLaunchCode',
                style: TextStyle(fontSize: 12, color: colors.tertiary),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              height: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _logs.isEmpty
                  ? Center(
                      child: Text(
                        '点击按钮开始演示，调用日志会显示在这里',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final log in _logs)
                          prism.SelectableText(
                            log,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
