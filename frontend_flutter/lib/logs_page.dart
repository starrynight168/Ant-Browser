import 'dart:async';
import 'dart:convert';

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
            _scrollController.animateTo(
              position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
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

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final filtered = _filteredLogs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrismPageContextBar(
            glyph: AntGlyphs.logs,
            title: '日志查看',
            subtitle: '应用运行日志与前端操作埋点，共 ${_logs.length} 条。',
            actions: [
              PrismBadge(
                label: '筛选到 ${filtered.length} 条',
                tone: PrismTone.neutral,
              ),
              prism.TonalButtonGroup(
                size: prism.TonalButtonSize.section,
                children: [
                  prism.IconButton(
                    tooltip: '刷新',
                    onPressed: _loading ? null : _load,
                    icon: const PrismGlyph(AntGlyphs.refresh, size: 18),
                  ),
                  prism.IconButton(
                    tooltip: '清空日志',
                    onPressed: _clearing || _logs.isEmpty ? null : _clear,
                    icon: const PrismGlyph(AntGlyphs.delete, size: 18),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          PrismSectionCard(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 8,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: PrismDropdownField<String>(
                    value: _level,
                    decoration: const PrismInputDecoration(
                      labelText: '级别',
                      isDense: true,
                    ),
                    items: const ['ALL', 'DEBUG', 'INFO', 'WARN', 'ERROR']
                        .map(
                          (value) => PrismDropdownItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _level = value ?? 'ALL'),
                  ),
                ),
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
                    onChanged: (value) =>
                        setState(() => _componentFilter = value ?? 'ALL'),
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
                    onChanged: (value) =>
                        setState(() => _methodFilter = value ?? 'ALL'),
                  ),
                ),
                for (final filter in const ['全部', '错误', '慢调用', '前端', '后端'])
                  PrismChip(
                    label: Text(filter),
                    selected: _quickFilter == filter,
                    onSelected: (_) => setState(() => _quickFilter = filter),
                  ),
                SizedBox(
                  width: 280,
                  child: PrismSearchBar(
                    controller: _searchController,
                    hintText: '搜索消息、组件或方法',
                    onChanged: (value) => setState(() => _keyword = value),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: PrismTextField(
                    controller: _fieldSearchController,
                    onChanged: (value) =>
                        setState(() => _fieldKeyword = value),
                    decoration: const PrismInputDecoration(
                      hintText: '搜索日志字段',
                      prefixIcon: PrismGlyph(AntGlyphs.dataObject, size: 17),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
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
                  width: 210,
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
                  width: 210,
                  child: PrismTextField(
                    controller: _timeToController,
                    onChanged: (value) => setState(() => _timeTo = value),
                    decoration: const PrismInputDecoration(
                      hintText: '结束时间 YYYY-MM-DD HH:mm:ss',
                      isDense: true,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    prism.Switch(
                      value: _autoScroll,
                      onChanged: (value) => setState(() => _autoScroll = value),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '自动滚动到最新',
                      style: prism.AppTextStyle.footnote.of(context),
                    ),
                  ],
                ),
                prism.OutlinedButton.icon(
                  onPressed: _resetFilters,
                  icon: const PrismGlyph(AntGlyphs.filterOff, size: 17),
                  label: const Text('重置筛选'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                : ListView.separated(
                    controller: _scrollController,
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final level = '${entry['level'] ?? 'INFO'}'.toUpperCase();
                      final component = '${entry['component'] ?? ''}';
                      final fields = entry['fields'] is Map
                          ? Map<String, dynamic>.from(entry['fields'] as Map)
                          : <String, dynamic>{};
                      return prism.Surface(
                        color: colors.surfaceContainerLow,
                        shape: prism.AppShape.lg,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  PrismBadge(
                                    label: level,
                                    tone: _levelTone(level),
                                  ),
                                  if (component.isNotEmpty)
                                    Text(
                                      component,
                                      style: prism.AppTextStyle.caption1
                                          .of(context, emphasized: true)
                                          .copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  Text(
                                    '${entry['time'] ?? ''}',
                                    style: prism.AppTextStyle.caption2
                                        .of(context)
                                        .copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
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
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
