import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _searchController = TextEditingController();
  final _fieldSearchController = TextEditingController();
  final _durationController = TextEditingController();
  final _timeFromController = TextEditingController();
  final _timeToController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _logs = [];
  String _level = 'INFO';
  String _quickFilter = '全部';
  String _keyword = '';
  String _fieldKeyword = '';
  String _componentFilter = 'ALL';
  String _methodFilter = 'ALL';
  String _durationMin = '';
  String _timeFrom = '';
  String _timeTo = '';
  bool _loading = true;
  bool _clearing = false;
  bool _refreshing = false;
  bool _autoScroll = false;
  bool _initialScrollDone = false;
  bool _showAdvancedFilters = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_loading) _load(showLoading: false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    _fieldSearchController.dispose();
    _durationController.dispose();
    _timeFromController.dispose();
    _timeToController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final value = await AppBridge.call('GetAppLogs');
      final rows = value is List ? value : const [];
      if (mounted) {
        setState(() {
          _logs = rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final position = _scrollController.position;
          if (!_initialScrollDone) {
            _initialScrollDone = true;
            _scrollController.jumpTo(position.maxScrollExtent);
          } else if (_autoScroll) {
            if (!PrismMotionSpec.current.enabled) {
              _scrollController.jumpTo(position.maxScrollExtent);
            } else {
              _scrollController.animateTo(
                position.maxScrollExtent,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
              );
            }
          }
        });
      }
    } catch (_) {
      if (mounted && showLoading) {
        showPrismNotice(context, '读取日志失败');
      }
    } finally {
      _refreshing = false;
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('清空日志？'),
        content: const Text('这会清空当前应用的运行日志。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    try {
      await AppBridge.call('ClearAppLogs');
      await _load(showLoading: false);
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, '清空失败：$error');
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  List<String> get _components {
    final values = _logs
        .map((entry) => '${entry['component'] ?? ''}')
        .where((value) => value.isNotEmpty)
        .toSet();
    if (_componentFilter != 'ALL') values.add(_componentFilter);
    final sorted = values.toList()..sort();
    return ['ALL', ...sorted];
  }

  List<String> get _methods {
    final values = _logs
        .map((entry) {
          final fields = entry['fields'];
          return fields is Map ? '${fields['method'] ?? ''}' : '';
        })
        .where((value) => value.isNotEmpty)
        .toSet();
    if (_methodFilter != 'ALL') values.add(_methodFilter);
    final sorted = values.toList()..sort();
    return ['ALL', ...sorted];
  }

  DateTime? _parseTime(String value) =>
      DateTime.tryParse(value.trim().replaceFirst(' ', 'T'));

  String _formatFieldValue(dynamic value) {
    if (value == null) return 'null';
    if (value is Map || value is List) {
      try {
        return jsonEncode(value);
      } catch (_) {
        return '$value';
      }
    }
    if (value is String) {
      if (value.isEmpty) return '""';
      if (RegExp(r'\s').hasMatch(value)) {
        return '"${value.replaceAll('"', r'\"')}"';
      }
      return value;
    }
    return '$value';
  }

  String _formatFields(Map<String, dynamic> fields) => fields.entries
      .map((item) => '${item.key}=${_formatFieldValue(item.value)}')
      .join('  ');

  void _resetFilters() {
    _searchController.clear();
    _fieldSearchController.clear();
    _durationController.clear();
    _timeFromController.clear();
    _timeToController.clear();
    setState(() {
      _level = 'INFO';
      _quickFilter = '全部';
      _keyword = '';
      _fieldKeyword = '';
      _componentFilter = 'ALL';
      _methodFilter = 'ALL';
      _durationMin = '';
      _timeFrom = '';
      _timeTo = '';
    });
  }

  List<Map<String, dynamic>> get _filteredLogs {
    final query = _keyword.trim().toLowerCase();
    return _logs.where((entry) {
      final level = '${entry['level'] ?? ''}'.toUpperCase();
      final component = '${entry['component'] ?? ''}';
      final message = '${entry['message'] ?? ''}';
      final fields = entry['fields'] is Map
          ? Map<String, dynamic>.from(entry['fields'] as Map)
          : <String, dynamic>{};
      final method = '${fields['method'] ?? ''}';
      final fieldQuery = _fieldKeyword.trim().toLowerCase();
      final duration =
          int.tryParse(
            '${fields['duration_ms'] ?? fields['durationMs'] ?? 0}',
          ) ??
          0;
      if (_level != 'ALL' && level != _level) return false;
      if (_quickFilter == '错误' && level != 'ERROR') return false;
      if (_quickFilter == '慢调用' && duration < 1000) return false;
      if (_quickFilter == '前端' && component != 'Frontend') return false;
      if (_quickFilter == '后端' && component == 'Frontend') return false;
      if (_componentFilter != 'ALL' && component != _componentFilter) {
        return false;
      }
      if (_methodFilter != 'ALL' && method != _methodFilter) return false;
      final minDuration = int.tryParse(_durationMin.trim());
      if (minDuration != null && duration < minDuration) return false;
      if (fieldQuery.isNotEmpty &&
          !jsonEncode(fields).toLowerCase().contains(fieldQuery)) {
        return false;
      }
      final from = _parseTime(_timeFrom);
      final to = _parseTime(_timeTo);
      if (from != null || to != null) {
        final logTime = _parseTime('${entry['time'] ?? ''}');
        if (logTime == null || (from != null && logTime.isBefore(from))) {
          return false;
        }
        if (to != null && logTime.isAfter(to)) return false;
      }
      if (query.isEmpty) return true;
      return '$message $component $method ${jsonEncode(fields)}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  PrismTone _levelTone(String level) => switch (level) {
    'ERROR' => PrismTone.danger,
    'WARN' => PrismTone.warning,
    'DEBUG' => PrismTone.neutral,
    _ => PrismTone.info,
  };

  int get _activeAdvancedFilterCount {
    var count = 0;
    if (_quickFilter != '全部') count++;
    if (_componentFilter != 'ALL') count++;
    if (_methodFilter != 'ALL') count++;
    if (_fieldKeyword.trim().isNotEmpty) count++;
    if (_durationMin.trim().isNotEmpty) count++;
    if (_timeFrom.trim().isNotEmpty) count++;
    if (_timeTo.trim().isNotEmpty) count++;
    return count;
  }

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (!PrismMotionSpec.current.enabled) {
      _scrollController.jumpTo(maxExtent);
    } else {
      _scrollController.animateTo(
        maxExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _setAutoScroll(bool value) {
    setState(() => _autoScroll = value);
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  String _formatLogsForExport(
    List<Map<String, dynamic>> entries, {
    required bool asJson,
  }) {
    if (asJson) {
      return const JsonEncoder.withIndent('  ').convert(entries);
    }
    return entries
        .map((entry) {
          final time = '${entry['time'] ?? ''}'.trim();
          final level = '${entry['level'] ?? 'INFO'}'.toUpperCase();
          final component = '${entry['component'] ?? ''}'.trim();
          final message = '${entry['message'] ?? ''}'.trim();
          final fields = entry['fields'] is Map
              ? Map<String, dynamic>.from(entry['fields'] as Map)
              : <String, dynamic>{};
          final prefix = [
            if (time.isNotEmpty) '[$time]',
            '[$level]',
            if (component.isNotEmpty) '[$component]',
          ].join(' ');
          final fieldsText = fields.isEmpty ? '' : ' | ${_formatFields(fields)}';
          return '$prefix $message$fieldsText'.trim();
        })
        .join('\n');
  }

  Future<void> _copyLogs(List<Map<String, dynamic>> entries) async {
    if (entries.isEmpty) {
      showPrismNotice(context, '当前没有可导出的日志');
      return;
    }
    final text = _formatLogsForExport(entries, asJson: false);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showPrismNotice(context, '已复制 ${entries.length} 条日志到剪贴板');
    }
  }

  Future<void> _exportLogsToFile(
    List<Map<String, dynamic>> entries, {
    required bool asJson,
  }) async {
    if (entries.isEmpty) {
      showPrismNotice(context, '当前没有可导出的日志');
      return;
    }
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final ext = asJson ? 'json' : 'log';
    final defaultPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}ant_browser_logs_$stamp.$ext';
    final pathController = TextEditingController(text: defaultPath);
    final chosenPath = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text(asJson ? '导出日志为 JSON' : '导出日志为文本'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '将导出当前筛选到的 ${entries.length} 条日志记录。',
                style: prism.AppTextStyle.footnote.of(context),
              ),
              const SizedBox(height: 10),
              PrismTextField(
                controller: pathController,
                autofocus: true,
                decoration: PrismInputDecoration(
                  labelText: '保存路径',
                  hintText: '输入目标 .$ext 文件完整路径',
                ),
              ),
            ],
          ),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.FilledButton.icon(
            onPressed: () => Navigator.pop(context, pathController.text.trim()),
            icon: const PrismGlyph(AntGlyphs.save, size: 15),
            label: const Text('导出'),
          ),
        ],
      ),
    );
    pathController.dispose();
    if (chosenPath == null || chosenPath.isEmpty) return;
    try {
      final file = File(chosenPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(_formatLogsForExport(entries, asJson: asJson));
      if (mounted) {
        showPrismNotice(context, '日志已导出到：$chosenPath');
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, '导出日志失败：$error');
      }
    }
  }

  Widget _buildOverviewStrip(BuildContext context) {
    var errorCount = 0;
    var warnCount = 0;
    var infoCount = 0;
    for (final entry in _logs) {
      switch ('${entry['level'] ?? ''}'.toUpperCase()) {
        case 'ERROR':
          errorCount++;
        case 'WARN':
          warnCount++;
        case 'INFO':
          infoCount++;
      }
    }

    final tiles = [
      PrismMetricTile(
        label: '日志总数',
        value: '${_logs.length}',
        subtitle: _level == 'ALL' ? '当前显示全部级别' : '点击查看全部级别',
        glyph: AntGlyphs.logs,
        tone: PrismTone.primary,
        onPressed: () => setState(() => _level = 'ALL'),
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: 'ERROR',
        value: '$errorCount',
        subtitle: _level == 'ERROR' ? '已筛选 ERROR · 点击取消' : '点击筛选 ERROR',
        glyph: AntGlyphs.error,
        tone: errorCount > 0 ? PrismTone.danger : PrismTone.neutral,
        onPressed: () => setState(
          () => _level = _level == 'ERROR' ? 'ALL' : 'ERROR',
        ),
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: 'WARN',
        value: '$warnCount',
        subtitle: _level == 'WARN' ? '已筛选 WARN · 点击取消' : '点击筛选 WARN',
        glyph: AntGlyphs.warning,
        tone: warnCount > 0 ? PrismTone.warning : PrismTone.neutral,
        onPressed: () => setState(
          () => _level = _level == 'WARN' ? 'ALL' : 'WARN',
        ),
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: 'INFO',
        value: '$infoCount',
        subtitle: _level == 'INFO' ? '已筛选 INFO · 点击取消' : '点击筛选 INFO',
        glyph: AntGlyphs.info,
        tone: PrismTone.info,
        onPressed: () => setState(
          () => _level = _level == 'INFO' ? 'ALL' : 'INFO',
        ),
        staggerIndex: 3,
        staggerDelay: const Duration(milliseconds: 45),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 10),
                Expanded(child: tiles[1]),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: tiles[2]),
                const SizedBox(width: 10),
                Expanded(child: tiles[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    List<Map<String, dynamic>> filtered,
  ) {
    final advancedCount = _activeAdvancedFilterCount;
    final levelControl = SizedBox(
      width: 340,
      child: prism.SegmentedControl<String>(
        value: _level,
        onChanged: (value) => setState(() => _level = value),
        segments: const [
          ('ALL', '全部'),
          ('DEBUG', 'DEBUG'),
          ('INFO', 'INFO'),
          ('WARN', 'WARN'),
          ('ERROR', 'ERROR'),
        ],
      ),
    );

    final actionWidgets = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          prism.Switch(value: _autoScroll, onChanged: _setAutoScroll),
          const SizedBox(width: 6),
          Text('自动滚动', style: prism.AppTextStyle.footnote.of(context)),
        ],
      ),
      PrismTonalButton.icon(
        onPressed: () =>
            setState(() => _showAdvancedFilters = !_showAdvancedFilters),
        icon: const PrismGlyph(AntGlyphs.tune, size: 15),
        child: Text(
          advancedCount > 0 ? '高级筛选 ($advancedCount)' : '高级筛选',
        ),
      ),
      prism.TonalButtonGroup(
        size: prism.TonalButtonSize.section,
        children: [
          prism.IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const PrismGlyph(AntGlyphs.refresh, size: 17),
          ),
          prism.IconButton(
            tooltip: '清空日志',
            onPressed: _clearing || _logs.isEmpty ? null : _clear,
            icon: const PrismGlyph(AntGlyphs.delete, size: 17),
          ),
        ],
      ),
      PrismPopupMenuButton<String>(
        tooltip: '导出日志与更多操作',
        icon: const PrismGlyph(AntGlyphs.download, size: 17),
        onSelected: (action) {
          switch (action) {
            case 'export-log':
              _exportLogsToFile(filtered, asJson: false);
            case 'export-json':
              _exportLogsToFile(filtered, asJson: true);
            case 'copy':
              _copyLogs(filtered);
            case 'reset':
              _resetFilters();
          }
        },
        itemBuilder: (_) => [
          PrismMenuItem(
            value: 'export-log',
            enabled: filtered.isNotEmpty,
            child: const Text('导出日志 (.log)'),
          ),
          PrismMenuItem(
            value: 'export-json',
            enabled: filtered.isNotEmpty,
            child: const Text('导出日志 (.json)'),
          ),
          PrismMenuItem(
            value: 'copy',
            enabled: filtered.isNotEmpty,
            child: const Text('复制当前筛选日志'),
          ),
          const PrismMenuItem(value: 'reset', child: Text('重置全部筛选')),
        ],
      ),
    ];

    return PrismHoverCard(
      staggerIndex: 4,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 980) {
                return Row(
                  children: [
                    Expanded(
                      child: PrismSearchBar(
                        controller: _searchController,
                        hintText: '搜索消息、组件或方法',
                        height: 36,
                        onChanged: (value) => setState(() => _keyword = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    levelControl,
                    const SizedBox(width: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actionWidgets,
                    ),
                  ],
                );
              }
              if (constraints.maxWidth >= 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: PrismSearchBar(
                            controller: _searchController,
                            hintText: '搜索消息、组件或方法',
                            height: 36,
                            onChanged: (value) =>
                                setState(() => _keyword = value),
                          ),
                        ),
                        const SizedBox(width: 10),
                        levelControl,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actionWidgets,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrismSearchBar(
                    controller: _searchController,
                    hintText: '搜索消息、组件或方法',
                    height: 36,
                    onChanged: (value) => setState(() => _keyword = value),
                  ),
                  const SizedBox(height: 8),
                  prism.SegmentedControl<String>(
                    value: _level,
                    onChanged: (value) => setState(() => _level = value),
                    segments: const [
                      ('ALL', '全部'),
                      ('DEBUG', 'DEBUG'),
                      ('INFO', 'INFO'),
                      ('WARN', 'WARN'),
                      ('ERROR', 'ERROR'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actionWidgets,
                  ),
                ],
              );
            },
          ),
          PrismCollapsible(
            expanded: _showAdvancedFilters,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                const prism.Divider(height: 1),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 175,
                      child: PrismDropdownField<String>(
                        value: _componentFilter,
                        decoration: const PrismInputDecoration(
                          labelText: '组件',
                          isDense: true,
                        ),
                        items: _components
                            .map(
                              (value) => PrismDropdownItem(
                                value: value,
                                child: Text(value == 'ALL' ? '全部组件' : value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(
                          () => _componentFilter = value ?? 'ALL',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 175,
                      child: PrismDropdownField<String>(
                        value: _methodFilter,
                        decoration: const PrismInputDecoration(
                          labelText: '方法',
                          isDense: true,
                        ),
                        items: _methods
                            .map(
                              (value) => PrismDropdownItem(
                                value: value,
                                child: Text(value == 'ALL' ? '全部方法' : value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(
                          () => _methodFilter = value ?? 'ALL',
                        ),
                      ),
                    ),
                    for (final filter in const [
                      '全部',
                      '错误',
                      '慢调用',
                      '前端',
                      '后端',
                    ])
                      PrismChip(
                        label: Text(filter),
                        selected: _quickFilter == filter,
                        onSelected: (_) =>
                            setState(() => _quickFilter = filter),
                      ),
                    SizedBox(
                      width: 210,
                      child: PrismTextField(
                        controller: _fieldSearchController,
                        onChanged: (value) =>
                            setState(() => _fieldKeyword = value),
                        decoration: const PrismInputDecoration(
                          hintText: '搜索日志字段',
                          prefixIcon: PrismGlyph(
                            AntGlyphs.dataObject,
                            size: 17,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 145,
                      child: PrismTextField(
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            setState(() => _durationMin = value),
                        decoration: const PrismInputDecoration(
                          hintText: '最短耗时（毫秒）',
                          isDense: true,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 205,
                      child: PrismTextField(
                        controller: _timeFromController,
                        onChanged: (value) => setState(() => _timeFrom = value),
                        decoration: const PrismInputDecoration(
                          hintText: '开始时间 YYYY-MM-DD HH:mm:ss',
                          isDense: true,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 205,
                      child: PrismTextField(
                        controller: _timeToController,
                        onChanged: (value) => setState(() => _timeTo = value),
                        decoration: const PrismInputDecoration(
                          hintText: '结束时间 YYYY-MM-DD HH:mm:ss',
                          isDense: true,
                        ),
                      ),
                    ),
                    prism.OutlinedButton.icon(
                      onPressed: _resetFilters,
                      icon: const PrismGlyph(AntGlyphs.filterOff, size: 17),
                      label: const Text('重置筛选'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogRow(
    BuildContext context,
    Map<String, dynamic> entry,
    prism.ColorScheme colors,
  ) {
    final level = '${entry['level'] ?? 'INFO'}'.toUpperCase();
    final component = '${entry['component'] ?? ''}';
    final fields = entry['fields'] is Map
        ? Map<String, dynamic>.from(entry['fields'] as Map)
        : <String, dynamic>{};
    return prism.Surface(
      color: colors.surfaceContainerLow,
      shape: prism.AppShape.lg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PrismBadge(label: level, tone: _levelTone(level)),
                if (component.isNotEmpty)
                  Text(
                    component,
                    style: prism.AppTextStyle.caption1
                        .of(context, emphasized: true)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                Text(
                  '${entry['time'] ?? ''}',
                  style: prism.AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            prism.SelectableText(
              '${entry['message'] ?? ''}',
              style: prism.AppTextStyle.subheadline
                  .of(context)
                  .copyWith(height: 1.45),
            ),
            if (fields.isNotEmpty) ...[
              const SizedBox(height: 6),
              prism.SelectableText(
                _formatFields(fields),
                style: prism.AppTextStyle.caption2
                    .of(context)
                    .copyWith(
                      fontFamily: 'Consolas',
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogViewerCard(
    BuildContext context,
    List<Map<String, dynamic>> filtered,
  ) {
    final colors = prism.Theme.of(context).colorScheme;
    final hasNonDefaultFilter =
        _level != 'INFO' ||
        _keyword.trim().isNotEmpty ||
        _activeAdvancedFilterCount > 0;
    return PrismHoverCard(
      staggerIndex: 5,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: false,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          prism.InfoHeader(
            info: const prism.Info(label: '运行日志', glyph: AntGlyphs.logs),
            actions: [
              if (hasNonDefaultFilter)
                prism.TextButton(
                  onPressed: _resetFilters,
                  child: const Text('重置筛选'),
                ),
              PrismBadge(
                label: '筛选到 ${filtered.length} 条',
                tone: filtered.isEmpty ? PrismTone.neutral : PrismTone.primary,
              ),
            ],
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
          ),
          const prism.Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : filtered.isEmpty
                ? PrismEmptyState(
                    glyph: AntGlyphs.logs,
                    title: '没有符合条件的日志',
                    subtitle: _logs.isEmpty
                        ? '当前暂无应用运行日志。'
                        : '尝试调整级别或筛选条件查看更多记录。',
                    action: _logs.isNotEmpty
                        ? prism.OutlinedButton.icon(
                            onPressed: _resetFilters,
                            icon: const PrismGlyph(
                              AntGlyphs.filterOff,
                              size: 16,
                            ),
                            label: const Text('重置筛选'),
                          )
                        : null,
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: kPrismListPadding,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) =>
                          _buildLogRow(context, filtered[index], colors),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLogs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewStrip(context),
          const SizedBox(height: 12),
          _buildToolbar(context, filtered),
          const SizedBox(height: 12),
          Expanded(child: _buildLogViewerCard(context, filtered)),
        ],
      ),
    );
  }
}
