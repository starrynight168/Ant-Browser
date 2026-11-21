import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'prism_components.dart';

import 'wails_bridge.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _logs = [];
  String _level = 'INFO';
  String _quickFilter = '全部';
  String _keyword = '';
  bool _loading = true;
  bool _clearing = false;
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
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final value = await WailsBridge.call('GetAppLogs');
      final rows = value is List ? value : const [];
      if (mounted) {
        setState(() {
          _logs = rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        });
      }
    } catch (_) {
      if (mounted && showLoading) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('读取日志失败')));
      }
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('这会清空当前应用的运行日志。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    try {
      await WailsBridge.call('ClearAppLogs');
      await _load(showLoading: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清空失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
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
          Row(
            children: [
              Expanded(child: Text('${filtered.length} / ${_logs.length} 条日志')),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _clearing || _logs.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PrismCard(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
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
                    child: DropdownButtonFormField<String>(
                      initialValue: _level,
                      decoration: const InputDecoration(
                        labelText: '级别',
                        isDense: true,
                      ),
                      items: const ['ALL', 'DEBUG', 'INFO', 'WARN', 'ERROR']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _level = value ?? 'ALL'),
                    ),
                  ),
                  for (final filter in const ['全部', '错误', '慢调用', '前端', '后端'])
                    FilterChip(
                      label: Text(filter),
                      selected: _quickFilter == filter,
                      onSelected: (_) => setState(() => _quickFilter = filter),
                    ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _keyword = value),
                      decoration: const InputDecoration(
                        hintText: '搜索消息、组件或方法',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? const Center(child: Text('没有符合条件的日志'))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = filtered[filtered.length - index - 1];
                      final level = '${entry['level'] ?? 'INFO'}'.toUpperCase();
                      final colors = Theme.of(context).colorScheme;
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
                        elevation: 0,
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
                              SelectableText(
                                '${entry['message'] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                              if (fields.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                SelectableText(
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
