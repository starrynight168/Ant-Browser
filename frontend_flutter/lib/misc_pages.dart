import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:prism_ui/icons/icons.dart' as prism_icons;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'docs_api_details.dart';
import 'docs_content.dart';
import 'prism_widgets.dart';

class _DocsItem {
  const _DocsItem(this.id, this.label, this.summary);

  final String id;
  final String label;
  final String summary;
}

class _DocsGroup {
  const _DocsGroup(this.label, this.glyph, this.items);

  final String label;
  final prism_icons.Glyph glyph;
  final List<_DocsItem> items;
}

class DocsPage extends StatefulWidget {
  const DocsPage({super.key});
  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  String _selected = 'tutorial-basic';
  Map<String, dynamic> _launchServerInfo = {};
  final _searchController = TextEditingController();

  static const _groups = <_DocsGroup>[
    _DocsGroup('使用教程', AntGlyphs.book, [
      _DocsItem('tutorial-basic', '基础使用', '应用上手流程、菜单入口和最小接口链路。'),
      _DocsItem(
        'tutorial-skill',
        'SKILL 使用',
        'OpenClaw 接入 ant-chrome-openclaw 的安装、提问模板和稳定使用规则。',
      ),
      _DocsItem('tutorial-flow', '操作流程', '按步骤串起内核、代理、实例和接口调用。'),
    ]),
    _DocsGroup('更新日志', AntGlyphs.history, [
      _DocsItem('changelog-versions', '版本更新', '按大版本查看主要变化。'),
    ]),
    _DocsGroup('内核介绍', AntGlyphs.cpu, [
      _DocsItem('core-management', '内核渠道与用法', '内核下载来源、目录结构和应用内使用方式。'),
    ]),
    _DocsGroup('代理介绍', AntGlyphs.globe, [
      _DocsItem('proxy-usage', '代理池使用', '代理类型、导入方式和实例绑定建议。'),
    ]),
    _DocsGroup('插件介绍', AntGlyphs.extension, [
      _DocsItem('extension-usage', '插件包管理', '插件安装、实例限制、分组选择和单实例配置。'),
    ]),
    _DocsGroup('接口介绍', AntGlyphs.api, [
      _DocsItem('api-overview', '接口总览', '认证、选择规则和全部对外接口索引。'),
      _DocsItem('api-profiles-launch', '实例与启动', '实例配置、按 Code 启动和参数化启动。'),
      _DocsItem('api-runtime', '运行态与接管', 'runtime session、活动实例和统一 CDP 入口。'),
      _DocsItem('api-automation', '脚本自动化', '自动化接口总览、字段规则和调用顺序。'),
      _DocsItem('api-support', '排障与日志', '调用日志、常见错误码和排查顺序。'),
      _DocsItem('api-demo', '启动 API 演示', '在应用内直接演练启动 API 的完整链路。'),
    ]),
  ];

  static final List<_DocsItem> _allItems = _groups
      .expand((group) => group.items)
      .toList();

  @override
  void initState() {
    super.initState();
    _loadLaunchServerInfo();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLaunchServerInfo() async {
    try {
      final result = await AppBridge.call('GetLaunchServerInfo');
      if (mounted && result is Map) {
        setState(() => _launchServerInfo = Map<String, dynamic>.from(result));
      }
    } catch (_) {}
  }

  String _substituteLaunchConfig(String raw) {
    var text = raw;
    final baseUrl = '${_launchServerInfo['baseUrl'] ?? ''}'.trim();
    if (baseUrl.isNotEmpty) {
      final normalizedBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      text = text.replaceAll('http://127.0.0.1:19876', normalizedBase);
      final parsed = Uri.tryParse(normalizedBase);
      final hostPort = (parsed != null && parsed.authority.isNotEmpty)
          ? parsed.authority
          : normalizedBase.replaceFirst(RegExp(r'^https?://'), '');
      if (hostPort.isNotEmpty) {
        text = text.replaceAll('127.0.0.1:19876', hostPort);
      }
    }
    final authHeader = '${_launchServerInfo['authHeader'] ?? ''}'.trim();
    if (authHeader.isNotEmpty) {
      text = text.replaceAll('X-Ant-Api-Key', authHeader);
    }
    return text;
  }

  Future<void> _openProjectRoot() async {
    try {
      await AppBridge.call('OpenProjectRoot');
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _allItems.indexWhere((item) => item.id == _selected);
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;
    final section = _allItems[safeIndex];
    final activeGroup = _groups.firstWhere(
      (group) => group.items.any((item) => item.id == section.id),
      orElse: () => _groups.first,
    );
    final prevItem = safeIndex > 0 ? _allItems[safeIndex - 1] : null;
    final nextItem = safeIndex < _allItems.length - 1
        ? _allItems[safeIndex + 1]
        : null;
    final colors = prism.Theme.of(context).colorScheme;
    final rawSource = [
      docsContent[section.id] ?? '',
      docsApiDetails[section.id] ?? '',
    ].where((content) => content.isNotEmpty).join('\n\n');
    final renderedSource = _substituteLaunchConfig(rawSource);

    final serverReady = _launchServerInfo['ready'] == true;
    final baseUrl = '${_launchServerInfo['baseUrl'] ?? ''}'.trim();
    final query = _searchController.text.trim().toLowerCase();
    final filteredGroups = query.isEmpty
        ? _groups
        : [
            for (final group in _groups)
              if (group.items.any(
                (item) =>
                    item.label.toLowerCase().contains(query) ||
                    item.summary.toLowerCase().contains(query),
              ))
                _DocsGroup(
                  group.label,
                  group.glyph,
                  group.items
                      .where(
                        (item) =>
                            item.label.toLowerCase().contains(query) ||
                            item.summary.toLowerCase().contains(query),
                      )
                      .toList(),
                ),
          ];

    final kpiTiles = [
      PrismMetricTile(
        label: '文档章节',
        value: '${_allItems.length}',
        subtitle: '${_groups.length} 个主题分类',
        glyph: AntGlyphs.book,
        tone: PrismTone.primary,
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '当前分类',
        value: activeGroup.label,
        subtitle: section.label,
        glyph: activeGroup.glyph,
        tone: PrismTone.info,
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '启动服务',
        value: serverReady ? '已就绪' : '未就绪',
        subtitle: baseUrl.isNotEmpty ? baseUrl : 'Launch Server',
        glyph: AntGlyphs.api,
        tone: serverReady ? PrismTone.success : PrismTone.warning,
        onPressed: () => setState(() => _selected = 'api-demo'),
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '交互演示',
        value: 'API 调试',
        subtitle: '点击直达在线演示',
        glyph: AntGlyphs.bolt,
        tone: PrismTone.neutral,
        onPressed: () => setState(() => _selected = 'api-demo'),
        staggerIndex: 3,
        staggerDelay: const Duration(milliseconds: 45),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 760) {
                return Row(
                  children: [
                    for (var i = 0; i < kpiTiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: kpiTiles[i]),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: kpiTiles[0]),
                      const SizedBox(width: 10),
                      Expanded(child: kpiTiles[1]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: kpiTiles[2]),
                      const SizedBox(width: 10),
                      Expanded(child: kpiTiles[3]),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 248,
                  child: PrismHoverCard(
                    staggerIndex: 4,
                    staggerDelay: const Duration(milliseconds: 45),
                    radius: prism.AppCorner.xl,
                    padding: EdgeInsets.zero,
                    hoverGlow: true,
                    lift: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        prism.InfoHeader(
                          info: const prism.Info(
                            label: '文档目录',
                            glyph: AntGlyphs.book,
                          ),
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: PrismSearchBar(
                            controller: _searchController,
                            hintText: '搜索文档章节…',
                            height: 34,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const prism.Divider(height: 1),
                        Expanded(
                          child: filteredGroups.isEmpty
                              ? PrismEmptyState(
                                  glyph: AntGlyphs.search,
                                  title: '无匹配章节',
                                  subtitle: '尝试调整关键词',
                                  action: prism.OutlinedButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    child: const Text('重置搜索'),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.all(10),
                                  children: [
                                    PrismSlidingRail<String>(
                                      itemHeight: 42,
                                      gap: 2,
                                      showDividers: true,
                                      showSelectionBadge: true,
                                      selectedValue: section.id,
                                      onSelected: (id) =>
                                          setState(() => _selected = id),
                                      items: [
                                        for (final group in filteredGroups)
                                          for (
                                            var i = 0;
                                            i < group.items.length;
                                            i++
                                          )
                                            PrismSlidingRailItem<String>(
                                              value: group.items[i].id,
                                              title: group.items[i].label,
                                              glyph: group.glyph,
                                              sectionHeader: i == 0
                                                  ? group.label
                                                  : null,
                                              sectionTrailing: i == 0
                                                  ? '${group.items.length}'
                                                  : null,
                                            ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: PrismHoverCard(
                    staggerIndex: 5,
                    staggerDelay: const Duration(milliseconds: 45),
                    radius: prism.AppCorner.xl,
                    padding: EdgeInsets.zero,
                    hoverGlow: true,
                    lift: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        prism.InfoHeader(
                          info: prism.Info(
                            label: section.label,
                            glyph: activeGroup.glyph,
                          ),
                          actions: [
                            PrismBadge(
                              label: activeGroup.label,
                              tone: PrismTone.info,
                            ),
                          ],
                          padding: const EdgeInsets.fromLTRB(20, 12, 16, 10),
                        ),
                        const prism.Divider(height: 1),
                        Expanded(
                          child: prism.PageTransitionSwitcher(
                            duration: PrismMotionSpec.current.pageDuration,
                            transitionBuilder:
                                PrismSlideThroughTransition.builder,
                            child: ListView(
                              key: ValueKey(_selected),
                              padding: const EdgeInsets.fromLTRB(
                                26,
                                20,
                                26,
                                28,
                              ),
                              children: [
                                Text(
                                  section.summary,
                                  style: prism.AppTextStyle.body
                                      .of(context)
                                      .copyWith(color: colors.onSurfaceVariant),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 36,
                                      height: 3,
                                      child: DecoratedBox(
                                        decoration: ShapeDecoration(
                                          color: colors.primary,
                                          shape: prism.AppShape.full,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: prism.Divider(height: 1),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _DocsMarkdown(source: renderedSource),
                                if (section.id == 'tutorial-skill') ...[
                                  const SizedBox(height: 14),
                                  PrismSectionCard(
                                    padding: EdgeInsets.zero,
                                    child: PrismListTile(
                                      leading: PrismGlyph(
                                        AntGlyphs.folder,
                                        size: 20,
                                        color: colors.primary,
                                      ),
                                      title: const Text('打开项目根目录'),
                                      subtitle: const Text(
                                        'SKILL 安装命令默认从这个目录运行。',
                                      ),
                                      trailing: prism.OutlinedButton.icon(
                                        onPressed: _openProjectRoot,
                                        icon: const PrismGlyph(
                                          AntGlyphs.folder,
                                          size: 16,
                                        ),
                                        label: const Text('打开目录'),
                                      ),
                                    ),
                                  ),
                                ],
                                if (section.id == 'api-demo') ...[
                                  const SizedBox(height: 14),
                                  _LaunchApiDemoPanel(
                                    launchServerInfo: _launchServerInfo,
                                    onRefreshServerInfo: _loadLaunchServerInfo,
                                  ),
                                ],
                                const SizedBox(height: 28),
                                const prism.Divider(height: 1),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (prevItem != null)
                                      Flexible(
                                        child: PrismHoverMotion(
                                          child: prism.OutlinedButton.icon(
                                            onPressed: () => setState(
                                              () => _selected = prevItem.id,
                                            ),
                                            icon: const PrismGlyph(
                                              AntGlyphs.chevronBack,
                                              size: 16,
                                            ),
                                            label: Text(
                                              '上一篇：${prevItem.label}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      const SizedBox.shrink(),
                                    if (nextItem != null) ...[
                                      const SizedBox(width: 12),
                                      Flexible(
                                        child: PrismHoverMotion(
                                          child: PrismTonalButton.icon(
                                            onPressed: () => setState(
                                              () => _selected = nextItem.id,
                                            ),
                                            icon: const PrismGlyph(
                                              AntGlyphs.chevronForward,
                                              size: 16,
                                            ),
                                            child: Text(
                                              '下一篇：${nextItem.label}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocsMarkdown extends StatelessWidget {
  const _DocsMarkdown({required this.source});

  final String source;

  List<String> _parseTableRow(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed
        .split('|')
        .map((cell) => cell.trim().replaceAll('`', '').replaceAll('**', ''))
        .toList();
  }

  Widget _buildTable(BuildContext context, List<List<String>> rows) {
    final colors = prism.Theme.of(context).colorScheme;
    final colCount = rows.fold<int>(
      0,
      (prev, row) => math.max(prev, row.length),
    );
    if (colCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: prism.Surface(
        color: colors.surfaceContainerLow,
        shape: prism.AppShape.lg,
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: prism.AppShape.lg),
          child: Table(
            border: TableBorder.symmetric(
              inside: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: r == 0
                      ? ShapeDecoration(
                          color: colors.surfaceContainerHighest.withValues(
                            alpha: 0.65,
                          ),
                          shape: const RoundedRectangleBorder(),
                        )
                      : null,
                  children: [
                    for (var c = 0; c < colCount; c++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: prism.SelectableText(
                          c < rows[r].length ? rows[r][c] : '',
                          style: r == 0
                              ? prism.AppTextStyle.footnote.of(
                                  context,
                                  emphasized: true,
                                )
                              : prism.AppTextStyle.footnote.of(context),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final children = <Widget>[];
    final code = StringBuffer();
    var inCode = false;
    var codeLanguage = '';
    final tableRows = <List<String>>[];

    void flushTable() {
      if (tableRows.isEmpty) return;
      children.add(_buildTable(context, List<List<String>>.from(tableRows)));
      tableRows.clear();
    }

    void addCodeBlock() {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: PrismCodeSurface(
            code: code.toString().trimRight(),
            language: codeLanguage.isEmpty ? null : codeLanguage,
          ),
        ),
      );
      code.clear();
    }

    for (final line in source.replaceAll('\r', '').split('\n')) {
      final value = line.trim();
      if (value.startsWith('```')) {
        flushTable();
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
      if (value.startsWith('|')) {
        if (!RegExp(r'^[|\s:-]+$').hasMatch(value)) {
          tableRows.add(_parseTableRow(value));
        }
        continue;
      }
      flushTable();
      if (value.isEmpty) {
        children.add(const SizedBox(height: 12));
        continue;
      }
      if (value.startsWith('# ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Text(
              value.substring(2),
              style: prism.AppTextStyle.title3.of(context, emphasized: true),
            ),
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
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: Text(
              heading,
              style: prism.AppTextStyle.headline
                  .of(context, emphasized: true)
                  .copyWith(color: colors.primary),
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
                  style: prism.AppTextStyle.body
                      .of(context, emphasized: true)
                      .copyWith(color: colors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: prism.SelectableText(
                    bullet.group(2)!.replaceAll('`', '').replaceAll('**', ''),
                    style: prism.AppTextStyle.body
                        .of(context)
                        .copyWith(height: 1.65),
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
          style: prism.AppTextStyle.body.of(context).copyWith(height: 1.7),
        ),
      );
    }
    flushTable();
    if (inCode) addCodeBlock();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class ChartsPage extends StatelessWidget {
  const ChartsPage({super.key});

  static const _lineData = <double>[28, 42, 35, 68, 55, 78, 65, 84];
  static const _areaData = <double>[18, 34, 29, 52, 48, 72, 60, 88];
  static const _weekLabels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('图表案例展示', style: prism.AppTextStyle.pageTitle.of(context)),
        const SizedBox(height: 4),
        Text(
          '基于 Prism UI 渲染的折线、柱状、饼图、面积与复合统计视图。',
          style: prism.AppTextStyle.footnote
              .of(context)
              .copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 920;
            final cardWidth = twoColumns
                ? ((constraints.maxWidth - 16) / 2).floorToDouble()
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _ChartCard(
                  width: cardWidth,
                  staggerIndex: 0,
                  title: '折线图示例（Prism LineChart）',
                  legend: [('活跃实例数', colors.primary)],
                  child: _PrismLineChartBox(
                    values: _lineData,
                    color: colors.primary,
                    minScale: 100,
                    xLabels: const [
                      '00:00',
                      '04:00',
                      '08:00',
                      '12:00',
                      '16:00',
                      '20:00',
                      '24:00',
                    ],
                    yLabels: const ['100', '50', '0'],
                  ),
                ),
                _ChartCard(
                  width: cardWidth,
                  staggerIndex: 1,
                  title: '柱状图示例',
                  legend: [
                    ('主业务', colors.primary),
                    ('代理任务', colors.tertiary),
                    ('脚本执行', colors.secondary),
                  ],
                  child: Column(
                    children: [
                      SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _BarChartPainter(colors: colors),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          for (final label in _weekLabels)
                            Text(
                              label,
                              style: prism.AppTextStyle.caption2
                                  .of(context)
                                  .copyWith(color: colors.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                _ChartCard(
                  width: cardWidth,
                  staggerIndex: 2,
                  title: '饼图示例',
                  legend: [
                    ('实例 36%', colors.primary),
                    ('代理 28%', colors.secondary),
                    ('脚本 21%', colors.tertiary),
                    ('其他 15%', colors.onSurfaceVariant),
                  ],
                  child: SizedBox(
                    height: 210,
                    child: Center(
                      child: CustomPaint(
                        size: const Size(200, 200),
                        painter: _PieChartPainter(colors: colors),
                      ),
                    ),
                  ),
                ),
                _ChartCard(
                  width: cardWidth,
                  staggerIndex: 3,
                  title: '面积图示例（Prism LineChart）',
                  legend: [('请求吞吐量 (req/min)', colors.tertiary)],
                  child: _PrismLineChartBox(
                    values: _areaData,
                    color: colors.tertiary,
                    minScale: 100,
                    xLabels: const [
                      'T-7',
                      'T-6',
                      'T-5',
                      'T-4',
                      'T-3',
                      'T-2',
                      '现在',
                    ],
                    yLabels: const ['100', '50', '0'],
                  ),
                ),
                _ChartCard(
                  width: cardWidth,
                  staggerIndex: 4,
                  title: '复合图表示例',
                  legend: [
                    ('任务量（柱）', colors.secondary),
                    ('成功率（线）', colors.primary),
                  ],
                  child: Column(
                    children: [
                      SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _ComposedChartPainter(colors: colors),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          for (final label in _weekLabels)
                            Text(
                              label,
                              style: prism.AppTextStyle.caption2
                                  .of(context)
                                  .copyWith(color: colors.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PrismLineChartBox extends StatelessWidget {
  const _PrismLineChartBox({
    required this.values,
    required this.color,
    required this.minScale,
    required this.xLabels,
    required this.yLabels,
  });

  final List<double> values;
  final Color color;
  final double minScale;
  final List<String> xLabels;
  final List<String> yLabels;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Row(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final label in yLabels)
                    Text(
                      label,
                      style: prism.AppTextStyle.caption2
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: prism.Surface(
                  color: colors.surfaceContainerLow,
                  shape: prism.AppShape.md,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: prism.LineChart(
                      values: values,
                      revision: values.length,
                      capacity: values.length,
                      minScale: minScale,
                      color: color,
                      baselineRatio: 0.92,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in xLabels)
                Text(
                  label,
                  style: prism.AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.width,
    required this.staggerIndex,
    required this.title,
    required this.legend,
    required this.child,
  });

  final double width;
  final int staggerIndex;
  final String title;
  final List<(String, Color)> legend;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: PrismSectionCard(
        staggerIndex: staggerIndex,
        staggerDelay: const Duration(milliseconds: 45),
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (legend.isNotEmpty) ...[
              Wrap(
                spacing: 12,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  for (final (label, color) in legend)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 8,
                          child: prism.Surface(
                            color: color,
                            shape: prism.AppShape.circle,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: prism.AppTextStyle.caption2
                              .of(context)
                              .copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({required this.colors});

  final prism.ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    const heights = [.42, .72, .55, .9, .63, .36, .78];
    final seriesColors = [colors.primary, colors.tertiary, colors.secondary];
    final slot = size.width / heights.length;
    final barWidth = math.min(34.0, slot * 0.48);
    for (var i = 0; i < heights.length; i++) {
      final h = size.height * heights[i];
      final left = slot * i + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - h, barWidth, h),
          const Radius.circular(6),
        ),
        Paint()..color = seriesColors[i % seriesColors.length],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.colors != colors;
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
    final diameter = math.min(size.width, size.height) - 12;
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

class _ComposedChartPainter extends CustomPainter {
  const _ComposedChartPainter({required this.colors});

  final prism.ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    const bars = [.42, .72, .55, .9, .63, .36, .78];
    const lineValues = [.68, .56, .61, .38, .48, .28, .3];
    final barPaint = Paint()..color = colors.secondary.withValues(alpha: 0.72);
    final slot = size.width / bars.length;
    final barWidth = math.min(28.0, slot * 0.42);
    final line = Path();
    for (var i = 0; i < bars.length; i++) {
      final centerX = slot * i + slot / 2;
      final height = size.height * bars[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            centerX - barWidth / 2,
            size.height - height,
            barWidth,
            height,
          ),
          const Radius.circular(5),
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
  const _LaunchApiDemoPanel({
    required this.launchServerInfo,
    required this.onRefreshServerInfo,
  });

  final Map<String, dynamic> launchServerInfo;
  final Future<void> Function() onRefreshServerInfo;

  @override
  State<_LaunchApiDemoPanel> createState() => _LaunchApiDemoPanelState();
}

class _LaunchApiDemoPanelState extends State<_LaunchApiDemoPanel> {
  final List<String> _logs = [];
  String _demoProfileId = '';
  String _demoLaunchCode = '';
  String _cdpUrl = '';
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

  String _extractCdpUrl(dynamic value) {
    if (value is! Map) return '';
    for (final key in const [
      'cdpUrl',
      'cdpEndpoint',
      'wsEndpoint',
      'debuggerUrl',
      'webSocketDebuggerUrl',
    ]) {
      final candidate = '${value[key] ?? ''}'.trim();
      if (candidate.isNotEmpty) return candidate;
    }
    for (final nestedKey in const ['data', 'session', 'runtime', 'result']) {
      if (value[nestedKey] is Map) {
        final found = _extractCdpUrl(value[nestedKey]);
        if (found.isNotEmpty) return found;
      }
    }
    return '';
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
      await widget.onRefreshServerInfo();
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
      if (value is Map) {
        final cdp = _extractCdpUrl(value);
        if (cdp.isNotEmpty && mounted) {
          setState(() => _cdpUrl = cdp);
        }
        _log('启动结果：${jsonEncode(value)}');
      }
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
      if (mounted) {
        setState(() {
          _demoProfileId = '';
          _demoLaunchCode = '';
          _cdpUrl = '';
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final serverReady = widget.launchServerInfo['ready'] == true;
    final baseUrl = '${widget.launchServerInfo['baseUrl'] ?? ''}'.trim();

    return PrismHoverCard(
      radius: prism.AppCorner.xl,
      padding: EdgeInsets.zero,
      hoverGlow: true,
      lift: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          prism.InfoHeader(
            info: const prism.Info(label: '启动 API 交互演示', glyph: AntGlyphs.api),
            actions: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: PrismBadge(
                  label: serverReady
                      ? (baseUrl.isNotEmpty
                            ? 'LaunchServerReady · $baseUrl'
                            : 'LaunchServerReady')
                      : 'LaunchServer 未就绪',
                  tone: serverReady ? PrismTone.success : PrismTone.warning,
                  dot: true,
                ),
              ),
            ],
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
          ),
          const prism.Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '演示会创建一个临时实例并启动，验证启动 API 链路后可一键清理；不会影响已有实例。',
                  style: prism.AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    prism.OutlinedButton.icon(
                      onPressed: _busy ? null : _healthCheck,
                      icon: const PrismGlyph(AntGlyphs.health, size: 17),
                      label: const Text('健康检查'),
                    ),
                    prism.OutlinedButton.icon(
                      onPressed: _busy || _demoProfileId.isNotEmpty
                          ? null
                          : _createProfile,
                      icon: const PrismGlyph(AntGlyphs.add, size: 17),
                      label: Text(
                        _demoProfileId.isEmpty ? '创建演示实例' : '演示实例已创建',
                      ),
                    ),
                    prism.OutlinedButton.icon(
                      onPressed: _busy || _demoLaunchCode.isEmpty
                          ? null
                          : _launchProfile,
                      icon: const PrismGlyph(AntGlyphs.play, size: 17),
                      label: const Text('启动演示实例'),
                    ),
                    prism.TextButton.icon(
                      onPressed: _busy || _demoProfileId.isEmpty
                          ? null
                          : _deleteProfile,
                      icon: const PrismGlyph(AntGlyphs.delete, size: 17),
                      label: const Text('删除演示实例'),
                    ),
                  ],
                ),
                if (_demoProfileId.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  PrismBanner(
                    tone: PrismTone.info,
                    message: '当前演示实例：$_demoProfileId · 启动码 $_demoLaunchCode',
                  ),
                ],
                if (_cdpUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  prism.Surface(
                    color: colors.surfaceContainerLow,
                    shape: prism.AppShape.lg,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const PrismBadge(
                            label: 'CDP URL',
                            tone: PrismTone.success,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: prism.SelectableText(
                              _cdpUrl,
                              style: const TextStyle(
                                fontFamily: prismMonoFontFamily,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          prism.IconButton(
                            tooltip: '复制 CDP URL',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _cdpUrl));
                              showPrismNotice(context, '已复制 CDP URL');
                            },
                            style: const prism.ButtonStyle(
                              fixedSize: Size.square(36),
                              minimumSize: Size.square(36),
                              padding: EdgeInsets.zero,
                            ),
                            icon: const PrismGlyph(AntGlyphs.copy, size: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                prism.Surface(
                  color: colors.surfaceContainerLow,
                  shape: prism.AppShape.lg,
                  child: SizedBox(
                    height: 220,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _logs.isEmpty
                          ? Center(
                              child: Text(
                                '点击按钮开始演示，调用日志会显示在这里',
                                style: prism.AppTextStyle.caption1
                                    .of(context)
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                            )
                          : ListView(
                              children: [
                                for (final log in _logs)
                                  prism.SelectableText(
                                    log,
                                    style: const TextStyle(
                                      fontFamily: prismMonoFontFamily,
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
