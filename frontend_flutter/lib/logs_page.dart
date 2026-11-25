import 'dart:async';
import 'dart:convert';

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';

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
        showPrismNotice(context, ('读取日志失败').toString());
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
        showPrismNotice(context, ('清空失败：$error').toString());
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLogs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${filtered.length} / ${_logs.length} 条日志'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              prism.OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              prism.OutlinedButton.icon(
                onPressed: _clearing || _logs.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PrismCard(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: prism.Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 8,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    child: PrismDropdownField<String>(
                      initialValue: _level,
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
                    width: 180,
                    child: PrismDropdownField<String>(
                      initialValue: _componentFilter,
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
                    width: 180,
                    child: PrismDropdownField<String>(
                      initialValue: _methodFilter,
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
                    child: PrismTextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _keyword = value),
                      decoration: const PrismInputDecoration(
                        hintText: '搜索消息、组件或方法',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
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
                        prefixIcon: Icon(Icons.data_object),
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
                  PrismSwitchTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动滚动到最新'),
                    value: _autoScroll,
                    onChanged: (value) => setState(() => _autoScroll = value),
                  ),
                  prism.OutlinedButton.icon(
                    onPressed: _resetFilters,
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    label: const Text('重置筛选'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : filtered.isEmpty
                ? const Center(child: Text('没有符合条件的日志'))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final level = '${entry['level'] ?? 'INFO'}'.toUpperCase();
                      final colors = prism.Theme.of(context).colorScheme;
                      final color = switch (level) {
                        'ERROR' => colors.error,
                        'WARN' => colors.tertiary,
                        'DEBUG' => colors.onSurfaceVariant,
                        _ => colors.primary,
                      };
                      final fields = entry['fields'] is Map
                          ? Map<String, dynamic>.from(entry['fields'] as Map)
                          : <String, dynamic>{};
                      return PrismCard(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.outlineVariant),
                        ),
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
                                  Text(
                                    '$level',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${entry['component'] ?? ''}',
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${entry['time'] ?? ''}',
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              prism.SelectableText(
                                '${entry['message'] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                              if (fields.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                prism.SelectableText(
                                  fields.entries
                                      .map(
                                        (item) => '${item.key}=${item.value}',
                                      )
                                      .join('  '),
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 11,
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
