import 'dart:async';
import 'dart:convert';

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:yaml/yaml.dart';

import 'app_bridge.dart';

dynamic _plainYaml(dynamic value) {
  if (value is YamlMap) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _plainYaml(entry.value),
    };
  }
  if (value is YamlList) return value.map(_plainYaml).toList();
  if (value is DateTime) return value.toIso8601String();
  return value;
}

List<Map<String, dynamic>> _parseClashNodes(String content, String prefix) {
  final parsed = loadYaml(content);
  final rawNodes = parsed is YamlMap
      ? parsed['proxies'] ?? parsed['proxy'] ?? parsed['Proxy']
      : parsed;
  if (rawNodes is! YamlList) {
    throw const FormatException('订阅内容中没有 proxies 节点列表');
  }
  final nodes = <Map<String, dynamic>>[];
  for (final item in rawNodes) {
    final plain = _plainYaml(item);
    if (plain is! Map) continue;
    final node = Map<String, dynamic>.from(plain);
    final rawName = (node['name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? '导入代理 ${nodes.length + 1}' : rawName;
    node['name'] = name;
    final fullName = prefix.trim().isEmpty ? name : '${prefix.trim()}-$name';
    final config = jsonEncode([node]);
    nodes.add({
      'index': nodes.length,
      'key': '$fullName|||$config',
      'name': fullName,
      'config': config,
      'server': node['server'],
      'port': node['port'],
      'type': node['type'],
    });
  }
  if (nodes.isEmpty) throw const FormatException('订阅内容未解析到可用节点');
  return nodes;
}

String _stableSourceId(String url, String prefix) {
  final parsed = Uri.parse(url.trim());
  final normalizedUrl = parsed.replace(fragment: '').toString();
  final key = '$normalizedUrl|||${prefix.trim()}';
  var hash = 5381;
  for (final unit in key.codeUnits) {
    hash = (((hash << 5) + hash) ^ unit) & 0xffffffff;
  }
  return 'src-${hash.toRadixString(36)}';
}

String _proxyProtocol(Map<String, dynamic> proxy) {
  final config = (proxy['proxyConfig'] ?? '').toString().trim();
  if (config == 'direct://') return 'direct';
  try {
    final decoded = jsonDecode(config);
    final node = decoded is List && decoded.isNotEmpty
        ? decoded.first
        : decoded;
    if (node is Map) {
      if (node['first'] is Map && node['second'] is Map) return 'chain';
      final protocol = (node['type'] ?? node['protocol'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (protocol.isNotEmpty) return protocol;
    }
  } catch (_) {}
  final separator = config.indexOf('://');
  return separator > 0 ? config.substring(0, separator).toLowerCase() : '-';
}

Map<String, dynamic> _proxyNode(Map<String, dynamic> proxy) {
  try {
    final decoded = jsonDecode((proxy['proxyConfig'] ?? '').toString());
    final node = decoded is List && decoded.isNotEmpty
        ? decoded.first
        : decoded;
    if (node is Map) return Map<String, dynamic>.from(node);
  } catch (_) {}
  return {};
}

String _proxyServer(Map<String, dynamic> proxy) {
  final node = _proxyNode(proxy);
  if (node['server'] != null) return node['server'].toString();
  for (final key in ['second', 'first']) {
    final part = node[key];
    if (part is Map && part['server'] != null) return part['server'].toString();
  }
  return Uri.tryParse((proxy['proxyConfig'] ?? '').toString())?.host ?? '';
}

int _proxyPort(Map<String, dynamic> proxy) {
  final node = _proxyNode(proxy);
  final second = node['second'];
  final first = node['first'];
  final raw =
      node['port'] ??
      (second is Map ? second['port'] : null) ??
      (first is Map ? first['port'] : null);
  return int.tryParse(raw?.toString() ?? '') ??
      Uri.tryParse((proxy['proxyConfig'] ?? '').toString())?.port ??
      0;
}

String _virtualGroupFilterKey(Map<String, dynamic> group) {
  final id = (group['groupId'] ?? '').toString().trim();
  final name = (group['groupName'] ?? '').toString().trim().toLowerCase();
  return 'virtual:' + (id.isNotEmpty ? id : name);
}

class ProxyPoolPage extends StatefulWidget {
  const ProxyPoolPage({
    super.key,
    required this.onOpenGroups,
    required this.onOpenAlign,
  });
  final VoidCallback onOpenGroups;
  final VoidCallback onOpenAlign;

  @override
  State<ProxyPoolPage> createState() => _ProxyPoolPageState();
}

class _ProxyPoolPageState extends State<ProxyPoolPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _virtualGroups = [];
  bool _loading = true;
  String _busy = '';
  String _query = '';
  String _filterProtocol = 'all';
  String _filterGroup = 'all';
  String _sortBy = '';
  bool _sortDescending = false;
  bool _availableOnly = false;
  final Set<String> _selectedIds = {};
  final Map<String, Map<String, dynamic>> _speedResults = {};
  final Map<String, Map<String, dynamic>> _ipHealthResults = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        AppBridge.call('BrowserProxyList'),
        AppBridge.call('BrowserProxyVirtualGroupList'),
      ]);
      _proxies = (values[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _virtualGroups = (values[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final knownGroups = _proxies
          .map((proxy) => (proxy['groupName'] ?? '').toString())
          .toSet();
      if (_filterGroup != 'all' &&
          !_virtualGroups.any(
            (group) => _virtualGroupFilterKey(group) == _filterGroup,
          ) &&
          !knownGroups.contains(_filterGroup)) {
        _filterGroup = 'all';
      }
      final knownProtocols = _proxies.map(_proxyProtocol).toSet();
      if (_filterProtocol != 'all' &&
          !knownProtocols.contains(_filterProtocol)) {
        _filterProtocol = 'all';
      }
      for (final proxy in _proxies) {
        final id = (proxy['proxyId'] ?? '').toString();
        final testedAt = (proxy['lastTestedAt'] ?? '').toString();
        if (id.isNotEmpty && testedAt.isNotEmpty) {
          _speedResults[id] = {
            'proxyId': id,
            'ok': proxy['lastTestOk'] == true,
            'latencyMs': proxy['lastLatencyMs'] ?? 0,
            'engine': proxy['lastTestEngine'] ?? '',
            'testedAt': testedAt,
          };
        }
        final rawHealth = (proxy['lastIPHealthJson'] ?? '').toString();
        if (id.isNotEmpty && rawHealth.isNotEmpty) {
          try {
            final health = jsonDecode(rawHealth);
            if (health is Map) {
              _ipHealthResults[id] = Map<String, dynamic>.from(health);
            }
          } catch (_) {}
        }
      }
      _selectedIds.removeWhere(
        (id) => !_proxies.any((proxy) => proxy['proxyId'] == id),
      );
      _error = null;
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(List<Map<String, dynamic>> next) async {
    await AppBridge.call('SaveBrowserProxies', [next]);
    await _refresh();
  }

  Future<void> _edit([Map<String, dynamic>? proxy]) async {
    final name = TextEditingController(
      text: (proxy?['proxyName'] ?? '').toString(),
    );
    final config = TextEditingController(
      text: (proxy?['proxyConfig'] ?? '').toString(),
    );
    final group = TextEditingController(
      text: (proxy?['groupName'] ?? '').toString(),
    );
    final result = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text(proxy == null ? '添加代理' : '编辑代理'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismTextField(
                controller: name,
                autofocus: true,
                decoration: const PrismInputDecoration(labelText: '代理名称'),
              ),
              PrismTextField(
                controller: config,
                decoration: const PrismInputDecoration(
                  labelText: '代理地址',
                  hintText: 'http://127.0.0.1:8080',
                ),
              ),
              PrismTextField(
                controller: group,
                decoration: const PrismInputDecoration(labelText: '分组（可选）'),
              ),
            ],
          ),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == true &&
        name.text.trim().isNotEmpty &&
        config.text.trim().isNotEmpty) {
      final id =
          (proxy?['proxyId'] ??
                  'proxy-${DateTime.now().millisecondsSinceEpoch}')
              .toString();
      final row = <String, dynamic>{
        ...?proxy,
        'proxyId': id,
        'proxyName': name.text.trim(),
        'proxyConfig': config.text.trim(),
        'groupName': group.text.trim(),
      };
      await _save(
        proxy == null
            ? [..._proxies, row]
            : _proxies
                  .map((item) => item['proxyId'] == id ? row : item)
                  .toList(),
      );
    }
    name.dispose();
    config.dispose();
    group.dispose();
  }

  Future<void> _delete(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    final ok = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除代理？'),
        content: Text((proxy['proxyName'] ?? id).toString()),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true)
      await _save(_proxies.where((item) => item['proxyId'] != id).toList());
  }

  int get _missingCount =>
      _proxies.where((proxy) => proxy['sourceMissing'] == true).length;

  Future<void> _cleanupMissing() async {
    setState(() => _busy = 'cleanup-preview');
    try {
      final preview = Map<String, dynamic>.from(
        await AppBridge.call('BrowserProxyCleanupMissing', ['', true]) as Map,
      );
      final scanned = int.tryParse('${preview['scanned'] ?? 0}') ?? 0;
      final deletable = int.tryParse('${preview['deletable'] ?? 0}') ?? 0;
      final skipped = (preview['skipped'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (scanned == 0) {
        if (mounted) showPrismNotice(context, '当前没有标记异常的订阅节点');
        return;
      }
      if (deletable == 0) {
        if (mounted) {
          showPrismNotice(context, '异常节点都仍被实例或虚拟分组引用，暂时不能清理');
        }
        return;
      }
      final confirmed = await showPrismDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => PrismDialog(
          title: const Text('清理异常节点？'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发现 $scanned 个订阅异常节点，可以安全删除 $deletable 个。'),
                if (skipped.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('以下 ${skipped.length} 个仍被使用，将保留：'),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final item in skipped)
                          Text(
                            '• ${(item['proxyName'] ?? item['proxyId'] ?? '').toString()} · ${switch (item['reason']) {
                              'instance' => '实例正在使用',
                              'virtual_group' => '虚拟分组正在使用',
                              'fetch_proxy' => '订阅刷新正在使用',
                              _ => '仍被引用',
                            }}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('删除 $deletable 个'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() => _busy = 'cleanup');
      final result = Map<String, dynamic>.from(
        await AppBridge.call('BrowserProxyCleanupMissing', ['', false]) as Map,
      );
      await _refresh();
      final deleted = int.tryParse('${result['deleted'] ?? 0}') ?? 0;
      final skippedCount = (result['skipped'] as List? ?? []).length;
      if (mounted) {
        showPrismNotice(
          context,
          skippedCount == 0
              ? '已清理 $deleted 个异常节点'
              : '已清理 $deleted 个，$skippedCount 个仍被使用的节点已保留',
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '清理异常节点失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _openProxyCoreDownload() async {
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => const _ProxyCoreDownloadDialog(),
    );
  }

  Future<void> _test(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    setState(() => _busy = id);
    try {
      final result = await AppBridge.call('BrowserProxyTestSpeed', [id]);
      final row = Map<String, dynamic>.from(result as Map);
      _speedResults[id] = row;
      if (mounted) setState(() {});
      final message = row['ok'] == true
          ? '连接成功，延迟 ${row['latencyMs'] ?? 0} ms'
          : '连接失败：${row['error'] ?? '未知错误'}';
      if (mounted) showPrismNotice(context, (message).toString());
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _testIpHealth(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    setState(() => _busy = id);
    try {
      final result = await AppBridge.call('BrowserProxyCheckIPHealth', [id]);
      final row = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};
      _ipHealthResults[id] = row;
      if (mounted) setState(() {});
      final message = row['ok'] == true
          ? 'IP 检查完成：${row['ip'] ?? '未返回 IP'} · ${row['country'] ?? row['region'] ?? ''}'
          : 'IP 检查失败：${row['error'] ?? '未知错误'}';
      if (mounted) {
        showPrismNotice(context, (message).toString());
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  bool _isAvailable(Map<String, dynamic> proxy) {
    final id = (proxy['proxyId'] ?? '').toString();
    return _speedResults[id]?['ok'] == true ||
        _ipHealthResults[id]?['ok'] == true;
  }

  Future<void> _testAll(List<Map<String, dynamic>> proxies) async {
    final ids = proxies
        .where((proxy) => proxy['proxyConfig'] != 'direct://')
        .map((proxy) => (proxy['proxyId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    setState(() => _busy = 'batch-speed');
    try {
      final raw = await AppBridge.call('BrowserProxyBatchTestSpeed', [ids, 5]);
      final results = raw is List ? raw : const [];
      var failed = 0;
      for (final item in results.whereType<Map>()) {
        final result = Map<String, dynamic>.from(item);
        final id = (result['proxyId'] ?? '').toString();
        if (id.isNotEmpty) _speedResults[id] = result;
        if (result['ok'] != true) failed++;
      }
      if (mounted) {
        setState(() {});
        showPrismNotice(
          context,
          failed == 0
              ? '批量测速完成：${results.length} 个代理'
              : '批量测速完成：${results.length - failed} 个成功，$failed 个失败',
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '批量测速失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _checkAllIPHealth(List<Map<String, dynamic>> proxies) async {
    final ids = proxies
        .where((proxy) => proxy['proxyConfig'] != 'direct://')
        .map((proxy) => (proxy['proxyId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    setState(() => _busy = 'batch-ip');
    try {
      final raw = await AppBridge.call('BrowserProxyBatchCheckIPHealth', [
        ids,
        10,
      ]);
      final results = raw is List ? raw : const [];
      var failed = 0;
      for (final item in results.whereType<Map>()) {
        final result = Map<String, dynamic>.from(item);
        final id = (result['proxyId'] ?? '').toString();
        if (id.isNotEmpty) _ipHealthResults[id] = result;
        if (result['ok'] != true) failed++;
      }
      if (mounted) {
        setState(() {});
        showPrismNotice(
          context,
          failed == 0
              ? 'IP 健康检测完成：${results.length} 个代理'
              : 'IP 健康检测完成：${results.length - failed} 个成功，$failed 个失败',
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '批量 IP 检测失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _refreshAllSources() async {
    final sources = <String, Map<String, dynamic>>{};
    for (final proxy in _proxies) {
      final id = (proxy['sourceId'] ?? '').toString();
      if (id.isNotEmpty && (proxy['sourceUrl'] ?? '').toString().isNotEmpty) {
        sources.putIfAbsent(id, () => proxy);
      }
    }
    if (sources.isEmpty) {
      showPrismNotice(context, '当前没有可刷新的订阅');
      return;
    }
    setState(() => _busy = 'refresh-all');
    var succeeded = 0;
    var failed = 0;
    try {
      for (final entry in sources.entries) {
        try {
          await AppBridge.call('BrowserProxyRefreshSource', [
            entry.key,
            entry.value['sourceFetchProxyId'] ?? '',
          ]);
          succeeded++;
        } catch (_) {
          failed++;
        }
      }
      await _refresh();
      if (mounted) {
        showPrismNotice(
          context,
          failed == 0
              ? '已刷新 $succeeded 个订阅'
              : '刷新完成：$succeeded 个成功，$failed 个失败',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _refreshSource(Map<String, dynamic> proxy) async {
    final sourceId = (proxy['sourceId'] ?? '').toString();
    if (sourceId.isEmpty) return;
    setState(() => _busy = sourceId);
    try {
      await AppBridge.call('BrowserProxyRefreshSource', [
        sourceId,
        proxy['sourceFetchProxyId'] ?? '',
      ]);
      await _refresh();
      if (mounted) showPrismNotice(context, '订阅刷新完成');
    } catch (error) {
      if (mounted) showPrismNotice(context, '刷新订阅失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedIds.toList();
    if (selected.isEmpty) return;
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除所选代理？'),
        content: Text('将从代理池删除 ${selected.length} 个代理。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = 'delete-selected');
    try {
      await _save(
        _proxies
            .where((proxy) => !selected.contains(proxy['proxyId']))
            .toList(),
      );
      if (mounted) {
        setState(() => _selectedIds.clear());
        showPrismNotice(context, '已删除 ${selected.length} 个代理');
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '批量删除失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _showIPHealthDetail(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    final result = _ipHealthResults[id];
    if (result == null) {
      showPrismNotice(context, '请先检测此代理的 IP 健康信息');
      return;
    }
    final rawData = result['rawData'] is Map ? result['rawData'] : result;
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('IP 健康检测详情'),
        content: SizedBox(
          width: 680,
          height: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '代理：${proxy['proxyName'] ?? id}  ·  来源：${result['source'] ?? '-'}  ·  时间：${result['updatedAt'] ?? '-'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (result['ok'] != true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('检测失败：${result['error'] ?? '未知错误'}'),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: prism.SelectableText(
                    const JsonEncoder.withIndent('  ').convert(rawData),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUsageGuide() async {
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => const _ProxyUsageGuideDialog(),
    );
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _filterProtocol = 'all';
      _filterGroup = 'all';
      _sortBy = '';
      _sortDescending = false;
      _availableOnly = false;
    });
  }

  Future<void> _editCheckSettings() async {
    try {
      final raw = await AppBridge.call('GetProxyCheckSettings');
      if (raw is! Map) return;
      final settings = Map<String, dynamic>.from(raw);
      final bridgeTimeout = TextEditingController(
        text: '${settings['bridgeStartTimeoutMs'] ?? 15000}',
      );
      final interval = TextEditingController(
        text: '${settings['speedIntervalMinutes'] ?? 30}',
      );
      final retry = TextEditingController(
        text: '${settings['failureRetryMinutes'] ?? 5}',
      );
      final concurrency = TextEditingController(
        text: '${settings['speedConcurrency'] ?? 5}',
      );
      final speedTarget = TextEditingController(
        text: '${settings['speedTargetId'] ?? ''}',
      );
      final healthTarget = TextEditingController(
        text: '${settings['ipHealthTargetId'] ?? ''}',
      );
      final targets = TextEditingController(
        text: const JsonEncoder.withIndent('  ')
            .convert(settings['targets'] ?? []),
      );
      final result = await showPrismDialog<Map<String, dynamic>>(
        context: context,
        useRootNavigator: false,
        builder: (context) => PrismDialog(
          title: const Text('代理检测设置'),
          content: SizedBox(
            width: 620,
            height: 560,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  PrismTextField(
                    controller: bridgeTimeout,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '代理启动等待（毫秒）',
                    ),
                  ),
                  PrismTextField(
                    controller: interval,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '成功节点重测间隔（分钟）',
                    ),
                  ),
                  PrismTextField(
                    controller: retry,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '失败重试间隔（分钟）',
                    ),
                  ),
                  PrismTextField(
                    controller: concurrency,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '测速并发上限（1 到 10）',
                    ),
                  ),
                  PrismTextField(
                    controller: speedTarget,
                    decoration: const PrismInputDecoration(
                      labelText: '测速目标 ID',
                    ),
                  ),
                  PrismTextField(
                    controller: healthTarget,
                    decoration: const PrismInputDecoration(
                      labelText: 'IP 健康目标 ID',
                    ),
                  ),
                  PrismTextField(
                    controller: targets,
                    minLines: 8,
                    maxLines: 16,
                    decoration: const PrismInputDecoration(
                      labelText: '检测目标列表 JSON',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () {
                try {
                  final parsedTargets = jsonDecode(targets.text);
                  if (parsedTargets is! List)
                    throw const FormatException('目标列表必须是 JSON 数组');
                  Navigator.pop(context, {
                    ...settings,
                    'bridgeStartTimeoutMs':
                        int.tryParse(bridgeTimeout.text) ?? 15000,
                    'speedIntervalMinutes': int.tryParse(interval.text) ?? 30,
                    'failureRetryMinutes': int.tryParse(retry.text) ?? 5,
                    'speedConcurrency': (int.tryParse(concurrency.text) ?? 5)
                        .clamp(1, 10),
                    'speedTargetId': speedTarget.text.trim(),
                    'ipHealthTargetId': healthTarget.text.trim(),
                    'targets': parsedTargets,
                  });
                } catch (error) {
                  showPrismNotice(context, ('检测目标 JSON 无效：$error').toString());
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      bridgeTimeout.dispose();
      interval.dispose();
      retry.dispose();
      concurrency.dispose();
      speedTarget.dispose();
      healthTarget.dispose();
      targets.dispose();
      if (result == null) return;
      await AppBridge.call('SaveProxyCheckSettings', [result]);
      if (mounted) {
        showPrismNotice(context, ('代理检测设置已保存').toString());
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    }
  }

  Future<void> _importSubscription() async {
    final url = TextEditingController();
    final prefix = TextEditingController();
    final group = TextEditingController();
    final interval = TextEditingController(text: '30');
    var autoRefresh = false;
    var fetchProxyId = '';
    final accepted = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('导入代理订阅'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrismTextField(
                  controller: url,
                  autofocus: true,
                  decoration: const PrismInputDecoration(labelText: '订阅地址'),
                ),
                PrismTextField(
                  controller: prefix,
                  decoration: const PrismInputDecoration(
                    labelText: '节点名前缀（可选）',
                  ),
                ),
                PrismTextField(
                  controller: group,
                  decoration: const PrismInputDecoration(labelText: '代理分组（可选）'),
                ),
                PrismDropdownField<String>(
                  initialValue: fetchProxyId,
                  decoration: const PrismInputDecoration(
                    labelText: '拉取订阅使用的代理',
                  ),
                  items: [
                    const PrismDropdownItem(value: '', child: Text('直连')),
                    for (final proxy in _proxies)
                      PrismDropdownItem(
                        value: proxy['proxyId']?.toString(),
                        child: Text(
                          (proxy['proxyName'] ?? '未命名代理').toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => fetchProxyId = value ?? '',
                ),
                PrismSwitchTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动刷新'),
                  value: autoRefresh,
                  onChanged: (value) => setDialog(() => autoRefresh = value),
                ),
                if (autoRefresh)
                  PrismTextField(
                    controller: interval,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '刷新间隔（分钟）',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始导入'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && url.text.trim().isNotEmpty) {
      setState(() => _busy = 'subscription');
      try {
        final minutes = autoRefresh
            ? (int.tryParse(interval.text) ?? 30).clamp(5, 1440)
            : 0;
        final importUrl = url.text.trim();
        final importPrefix = prefix.text.trim();
        final fetch = await AppBridge.call(
          fetchProxyId.isEmpty
              ? 'BrowserProxyFetchClashByURL'
              : 'BrowserProxyFetchClashByURLWithProxy',
          fetchProxyId.isEmpty ? [importUrl] : [importUrl, fetchProxyId],
        );
        final fetched = Map<String, dynamic>.from(fetch as Map);
        final nodes = _parseClashNodes(
          (fetched['content'] ?? '').toString(),
          importPrefix,
        );
        if (group.text.trim().isEmpty &&
            fetched['suggestedGroup']?.toString().trim().isNotEmpty == true) {
          group.text = fetched['suggestedGroup'].toString().trim();
        }
        final selectedIndices = await _chooseSubscriptionNodes(nodes);
        if (!mounted || selectedIndices == null || selectedIndices.isEmpty) {
          url.dispose();
          prefix.dispose();
          group.dispose();
          interval.dispose();
          return;
        }
        final selectedNodes = nodes
            .where((node) => selectedIndices.contains(node['index']))
            .toList();
        final existingSourceId = _proxies
            .where(
              (proxy) =>
                  _normalizedSubscriptionUrl(
                        proxy['sourceUrl']?.toString() ?? '',
                      ) ==
                      _normalizedSubscriptionUrl(importUrl) &&
                  (proxy['sourceNamePrefix'] ?? '').toString().trim() ==
                      importPrefix,
            )
            .map((proxy) => (proxy['sourceId'] ?? '').toString().trim())
            .firstWhere((id) => id.isNotEmpty, orElse: () => '');
        final sourceId = existingSourceId.isEmpty
            ? _stableSourceId(importUrl, importPrefix)
            : existingSourceId;
        final now = DateTime.now().toUtc().toIso8601String();
        final existingRows = _proxies
            .where((proxy) => (proxy['sourceId'] ?? '').toString() == sourceId)
            .toList();
        final consumedOld = <String>{};
        final imported = <Map<String, dynamic>>[];
        for (var index = 0; index < selectedNodes.length; index++) {
          final node = selectedNodes[index];
          final name = node['name'].toString();
          Map<String, dynamic>? old;
          for (final candidate in existingRows) {
            final id = (candidate['proxyId'] ?? '').toString();
            if (consumedOld.contains(id)) continue;
            if ((candidate['proxyName'] ?? '').toString() == name ||
                (candidate['proxyConfig'] ?? '').toString() == node['config']) {
              old = candidate;
              consumedOld.add(id);
              break;
            }
          }
          imported.add({
            'proxyId':
                old?['proxyId'] ??
                'proxy-${DateTime.now().microsecondsSinceEpoch}-$index',
            'proxyName': name,
            'proxyConfig': node['config'],
            'preferredKernel': old?['preferredKernel'] ?? 'auto',
            'dnsServers': (fetched['dnsServers'] ?? '').toString(),
            'groupName': group.text.trim(),
            'sourceId': sourceId,
            'sourceUrl': (fetched['url'] ?? importUrl).toString(),
            'sourceNamePrefix': importPrefix,
            'sourceAutoRefresh': autoRefresh,
            'sourceRefreshIntervalM': minutes,
            'sourceLastRefreshAt': now,
            'sourceFetchProxyId': fetchProxyId,
            'sourceMissing': false,
            'sourceMissingSince': '',
            'sourceLastRefreshError': '',
          });
        }
        final missing = existingRows
            .where(
              (proxy) =>
                  !consumedOld.contains((proxy['proxyId'] ?? '').toString()),
            )
            .map(
              (proxy) => {
                ...proxy,
                'sourceAutoRefresh': autoRefresh,
                'sourceRefreshIntervalM': minutes,
                'sourceFetchProxyId': fetchProxyId,
                'sourceMissing': true,
                'sourceMissingSince':
                    (proxy['sourceMissingSince'] ?? '').toString().isEmpty
                    ? now
                    : proxy['sourceMissingSince'],
              },
            )
            .toList();
        final next = [
          ..._proxies.where(
            (proxy) => (proxy['sourceId'] ?? '').toString() != sourceId,
          ),
          ...imported,
          ...missing,
        ];
        await AppBridge.call('SaveBrowserProxies', [next]);
        final ignoredNames = nodes
            .where((node) => !selectedIndices.contains(node['index']))
            .map((node) => node['name'].toString())
            .toList();
        await AppBridge.call('BrowserProxySetSourceIgnoredNames', [
          sourceId,
          ignoredNames,
        ]);
        setState(() => _proxies = next);
        await _refresh();
        if (mounted)
          showPrismNotice(
            context,
            ('导入完成：保存 ${imported.length} 个代理').toString(),
          );
      } catch (error) {
        if (mounted) showPrismNotice(context, (error.toString()).toString());
      } finally {
        if (mounted) setState(() => _busy = '');
      }
    }
    url.dispose();
    prefix.dispose();
    group.dispose();
    interval.dispose();
  }

  String _normalizedSubscriptionUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    try {
      return Uri.parse(raw).replace(fragment: '').toString();
    } catch (_) {
      return raw;
    }
  }

  Future<Set<int>?> _chooseSubscriptionNodes(
    List<Map<String, dynamic>> nodes,
  ) => showPrismDialog<Set<int>>(
    context: context,
    useRootNavigator: false,
    builder: (context) {
      final selected = nodes.map((node) => node['index'] as int).toSet();
      return StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: Text('选择要导入的节点（${nodes.length}）'),
          content: SizedBox(
            width: 560,
            height: 480,
            child: ListView.builder(
              itemCount: nodes.length,
              itemBuilder: (context, index) {
                final node = nodes[index];
                final nodeIndex = node['index'] as int;
                return PrismCheckboxTile(
                  value: selected.contains(nodeIndex),
                  title: Text(node['name'].toString()),
                  subtitle: Text(
                    '${node['server'] ?? ''}:${node['port'] ?? ''} · ${node['type'] ?? ''}',
                  ),
                  onChanged: (value) => setDialog(() {
                    if (value == true) {
                      selected.add(nodeIndex);
                    } else {
                      selected.remove(nodeIndex);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected),
              child: Text('导入 ${selected.length} 个'),
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final protocols =
        _proxies
            .map(_proxyProtocol)
            .where((protocol) => protocol != '-')
            .toSet()
            .toList()
          ..sort();
    final groups =
        _proxies
            .map((proxy) => (proxy['groupName'] ?? '').toString().trim())
            .where((group) => group.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    Map<String, dynamic>? selectedVirtualGroup;
    for (final group in _virtualGroups) {
      if (_virtualGroupFilterKey(group) == _filterGroup) {
        selectedVirtualGroup = group;
        break;
      }
    }
    final virtualMemberIds = Set<String>.from(
      (selectedVirtualGroup?['memberProxyIds'] as List? ?? []).map(
        (id) => id.toString().trim().toLowerCase(),
      ),
    );
    final virtualMemberGroups = Set<String>.from(
      (selectedVirtualGroup?['memberGroupNames'] as List? ?? []).map(
        (name) => name.toString().trim().toLowerCase(),
      ),
    );
    final visible = _proxies.where((item) {
      final text = [
        item['proxyName'],
        item['proxyConfig'],
        item['groupName'],
      ].join(' ').toLowerCase();
      final id = (item['proxyId'] ?? '').toString().trim().toLowerCase();
      final groupName = (item['groupName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final groupMatches = selectedVirtualGroup != null
          ? item['proxyConfig'] != 'direct://' &&
                (virtualMemberIds.contains(id) ||
                    virtualMemberGroups.contains(groupName))
          : _filterGroup == 'all' ||
                (item['groupName'] ?? '').toString() == _filterGroup;
      return text.contains(_query.toLowerCase()) &&
          (_filterProtocol == 'all' ||
              _proxyProtocol(item) == _filterProtocol) &&
          groupMatches &&
          (!_availableOnly || _isAvailable(item));
    }).toList();
    int latency(Map<String, dynamic> proxy) {
      final id = (proxy['proxyId'] ?? '').toString();
      final result = _speedResults[id];
      if (result == null || result['ok'] != true) return 1 << 60;
      return int.tryParse(
            (result['latencyMs'] ?? proxy['lastLatencyMs'] ?? 0).toString(),
          ) ??
          (1 << 60);
    }

    if (_sortBy.isNotEmpty) {
      visible.sort((a, b) {
        final comparison = switch (_sortBy) {
          'name' => (a['proxyName'] ?? '').toString().compareTo(
            (b['proxyName'] ?? '').toString(),
          ),
          'group' => (a['groupName'] ?? '').toString().compareTo(
            (b['groupName'] ?? '').toString(),
          ),
          'protocol' => _proxyProtocol(a).compareTo(_proxyProtocol(b)),
          'server' => _proxyServer(a).compareTo(_proxyServer(b)),
          'port' => _proxyPort(a).compareTo(_proxyPort(b)),
          'latency' => latency(a).compareTo(latency(b)),
          _ => 0,
        };
        return _sortDescending ? -comparison : comparison;
      });
    }
    final selectable = visible
        .where((item) => (item['proxyId'] ?? '').toString() != '__direct__')
        .toList();
    final allFilteredSelected =
        selectable.isNotEmpty &&
        selectable.every(
          (item) => _selectedIds.contains(item['proxyId'].toString()),
        );
    final hasSources = _proxies.any(
      (proxy) =>
          (proxy['sourceId'] ?? '').toString().isNotEmpty &&
          (proxy['sourceUrl'] ?? '').toString().isNotEmpty,
    );
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: PrismTextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const PrismInputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索代理名称、地址或分组',
                  ),
                ),
              ),
              prism.IconButton(
                tooltip: '刷新列表',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
              prism.IconButton(
                tooltip: '代理检测设置',
                onPressed: _editCheckSettings,
                icon: const Icon(Icons.tune),
              ),
              prism.IconButton(
                tooltip: '清理异常订阅节点（' + _missingCount.toString() + '）',
                onPressed: _busy.isEmpty && _missingCount > 0
                    ? _cleanupMissing
                    : null,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
              prism.IconButton(
                tooltip: '下载代理内核',
                onPressed: _openProxyCoreDownload,
                icon: const Icon(Icons.system_update_alt_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty ? () => _testAll(visible) : null,
                icon: const Icon(Icons.speed),
                label: Text(_busy == 'batch-speed' ? '测速中…' : '测试全部'),
              ),
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty
                    ? () => _checkAllIPHealth(visible)
                    : null,
                icon: const Icon(Icons.public),
                label: Text(_busy == 'batch-ip' ? '检测中…' : '检测 IP 健康'),
              ),
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty && hasSources
                    ? _refreshAllSources
                    : null,
                icon: const Icon(Icons.sync),
                label: Text(_busy == 'refresh-all' ? '刷新中…' : '刷新全部订阅'),
              ),
              prism.OutlinedButton.icon(
                onPressed: widget.onOpenGroups,
                icon: const Icon(Icons.hub_outlined),
                label: const Text('虚拟分组'),
              ),
              prism.OutlinedButton.icon(
                onPressed: widget.onOpenAlign,
                icon: const Icon(Icons.sync_alt),
                label: const Text('订阅管理'),
              ),
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty ? _importSubscription : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(_busy == 'subscription' ? '导入中…' : '导入订阅'),
              ),
              prism.OutlinedButton(
                onPressed: _showUsageGuide,
                child: const Text('使用说明'),
              ),
              prism.FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('添加代理'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 170,
                child: PrismDropdownField<String>(
                  value: _filterProtocol,
                  decoration: const PrismInputDecoration(labelText: '代理协议'),
                  items: [
                    const PrismDropdownItem(value: 'all', child: Text('全部协议')),
                    for (final protocol in protocols)
                      PrismDropdownItem(
                        value: protocol,
                        child: Text(protocol.toUpperCase()),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _filterProtocol = value ?? 'all'),
                ),
              ),
              SizedBox(
                width: 190,
                child: PrismDropdownField<String>(
                  value: _filterGroup,
                  decoration: const PrismInputDecoration(labelText: '代理分组'),
                  items: [
                    const PrismDropdownItem(value: 'all', child: Text('全部分组')),
                    for (final group in groups)
                      PrismDropdownItem(value: group, child: Text(group)),
                    for (final group in _virtualGroups)
                      PrismDropdownItem(
                        value: _virtualGroupFilterKey(group),
                        child: Text('虚拟：' + group['groupName'].toString()),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _filterGroup = value ?? 'all'),
                ),
              ),
              SizedBox(
                width: 160,
                child: PrismDropdownField<String>(
                  value: _sortBy,
                  decoration: const PrismInputDecoration(labelText: '排序'),
                  items: const [
                    PrismDropdownItem(value: '', child: Text('默认顺序')),
                    PrismDropdownItem(value: 'name', child: Text('代理名称')),
                    PrismDropdownItem(value: 'group', child: Text('分组')),
                    PrismDropdownItem(value: 'protocol', child: Text('协议')),
                    PrismDropdownItem(value: 'server', child: Text('服务器')),
                    PrismDropdownItem(value: 'port', child: Text('端口')),
                    PrismDropdownItem(value: 'latency', child: Text('延迟')),
                  ],
                  onChanged: (value) => setState(() => _sortBy = value ?? ''),
                ),
              ),
              prism.IconButton(
                tooltip: _sortDescending ? '降序' : '升序',
                onPressed: () =>
                    setState(() => _sortDescending = !_sortDescending),
                icon: Icon(_sortDescending ? Icons.south : Icons.north),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  prism.Checkbox(
                    value: _availableOnly,
                    onChanged: (value) =>
                        setState(() => _availableOnly = value == true),
                  ),
                  const Text('只看可用'),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  prism.Checkbox(
                    value: allFilteredSelected,
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selectedIds.addAll(
                          selectable.map((item) => item['proxyId'].toString()),
                        );
                      } else {
                        _selectedIds.removeAll(
                          selectable.map((item) => item['proxyId'].toString()),
                        );
                      }
                    }),
                  ),
                  Text('全选当前结果（' + visible.length.toString() + '）'),
                ],
              ),
              if (_query.isNotEmpty ||
                  _filterProtocol != 'all' ||
                  _filterGroup != 'all' ||
                  _sortBy.isNotEmpty ||
                  _availableOnly)
                prism.TextButton(
                  onPressed: _clearFilters,
                  child: const Text('清除筛选'),
                ),
              if (_selectedIds.isNotEmpty)
                prism.OutlinedButton.icon(
                  onPressed: _busy.isEmpty ? _deleteSelected : null,
                  icon: const Icon(Icons.delete_outline),
                  label: Text('删除所选（' + _selectedIds.length.toString() + '）'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        prism.TextButton(
                          onPressed: _refresh,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : visible.isEmpty
                ? const Center(child: Text('还没有代理'))
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final id = (item['proxyId'] ?? '').toString();
                      final isSelectable = id.isNotEmpty && id != '__direct__';
                      final isDirect = item['proxyConfig'] == 'direct://';
                      final speed = _speedResults[id];
                      final health = _ipHealthResults[id];
                      final sourceId = (item['sourceId'] ?? '').toString();
                      final speedLabel = item['proxyConfig'] == 'direct://'
                          ? '不适用'
                          : speed == null
                          ? '未测速'
                          : speed['ok'] == true
                          ? (speed['latencyMs'] ?? 0).toString() + ' ms'
                          : '失败';
                      final ipLabel = item['proxyConfig'] == 'direct://'
                          ? '不适用'
                          : health == null
                          ? '未检测'
                          : health['ok'] == true
                          ? (health['ip'] ?? '已检测').toString()
                          : '失败';
                      return PrismCard(
                        child: PrismListTile(
                          leading: isSelectable
                              ? prism.Checkbox(
                                  value: _selectedIds.contains(id),
                                  onChanged: _busy.isEmpty
                                      ? (value) => setState(() {
                                          if (value == true) {
                                            _selectedIds.add(id);
                                          } else {
                                            _selectedIds.remove(id);
                                          }
                                        })
                                      : null,
                                )
                              : const Icon(Icons.shield_outlined),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (item['proxyName'] ?? id).toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item['sourceMissing'] == true)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Text('订阅异常'),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['proxyConfig'] ?? '').toString() +
                                    ((item['groupName'] ?? '')
                                            .toString()
                                            .isEmpty
                                        ? ''
                                        : ' · ' + item['groupName'].toString()),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '协议 ' +
                                    _proxyProtocol(item).toUpperCase() +
                                    '  ·  延迟 ' +
                                    speedLabel +
                                    '  ·  IP ' +
                                    ipLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          trailing: Wrap(
                            children: [
                              prism.IconButton(
                                tooltip: '检查代理 IP',
                                onPressed: _busy.isEmpty && !isDirect
                                    ? () => _testIpHealth(item)
                                    : null,
                                icon: const Icon(Icons.public),
                              ),
                              prism.IconButton(
                                tooltip: '测试连接',
                                onPressed: _busy.isEmpty && !isDirect
                                    ? () => _test(item)
                                    : null,
                                icon: _busy == id || _busy == 'batch-speed'
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: PrismProgressIndicator(),
                                      )
                                    : const Icon(Icons.speed),
                              ),
                              PrismPopupMenuButton<String>(
                                tooltip: '更多操作',
                                enabled:
                                    _busy.isEmpty &&
                                    (isSelectable ||
                                        sourceId.isNotEmpty ||
                                        health != null),
                                icon: const Icon(Icons.more_vert),
                                itemBuilder: (_) => [
                                  if (sourceId.isNotEmpty)
                                    const PrismMenuItem(
                                      value: 'refresh',
                                      child: Text('刷新订阅'),
                                    ),
                                  if (health != null)
                                    const PrismMenuItem(
                                      value: 'ip-detail',
                                      child: Text('查看 IP 检测详情'),
                                    ),
                                  if (isSelectable) ...[
                                    const PrismMenuItem(
                                      value: 'edit',
                                      child: Text('编辑'),
                                    ),
                                    const PrismMenuItem(
                                      value: 'delete',
                                      child: Text('删除'),
                                      danger: true,
                                    ),
                                  ],
                                ],
                                onSelected: (action) {
                                  if (action == 'refresh') {
                                    _refreshSource(item);
                                  } else if (action == 'ip-detail') {
                                    _showIPHealthDetail(item);
                                  } else if (action == 'edit') {
                                    _edit(item);
                                  } else if (action == 'delete') {
                                    _delete(item);
                                  }
                                },
                              ),
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

class _ProxyUsageGuideDialog extends StatefulWidget {
  const _ProxyUsageGuideDialog();

  @override
  State<_ProxyUsageGuideDialog> createState() => _ProxyUsageGuideDialogState();
}

class _ProxyUsageGuideDialogState extends State<_ProxyUsageGuideDialog> {
  String _tab = 'ipfly';

  static const _clashExample = '''proxies:
  - name: hk-vless
    type: vless
    server: example.com
    port: 443
    uuid: your-uuid
    network: ws
    tls: true
    servername: example.com''';
  static const _proxyExample = '''http://user:password@gateway.example.com:8080
https://user:password@gateway.example.com:8443
socks5://user:password@proxy.example.com:6616''';
  static const _chainExample = '''{
  "name": "IPFLY-落地",
  "first": {
    "protocol": "socks5",
    "server": "127.0.0.1",
    "port": "7890"
  },
  "second": {
    "protocol": "socks5",
    "server": "gateway.example.com",
    "port": "6616",
    "username": "账号",
    "password": "密码"
  }
}''';

  @override
  Widget build(BuildContext context) => PrismDialog(
    title: const Text('代理池使用说明'),
    content: SizedBox(
      width: 880,
      height: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final tab in const [
                ('clash', 'Clash 订阅 / YAML'),
                ('direct', 'HTTP / SOCKS5'),
                ('ipfly', '链式代理'),
              ])
                _tab == tab.$1
                    ? prism.FilledButton(
                        onPressed: () => setState(() => _tab = tab.$1),
                        child: Text(tab.$2),
                      )
                    : prism.OutlinedButton(
                        onPressed: () => setState(() => _tab = tab.$1),
                        child: Text(tab.$2),
                      ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (_tab == 'clash') ...[
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('导入订阅或 YAML'),
                      subtitle: Text(
                        '输入订阅 URL 获取内容，或粘贴 YAML。内容需要包含 proxies 节点列表；解析后先检查名称和数量，再确认导入。',
                      ),
                    ),
                  ),
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('拉取失败或解析为空'),
                      subtitle: Text(
                        '订阅无法直连时，在导入界面选择拉取代理。解析为空时检查 YAML 缩进、proxies 拼写及每个节点的 name、type、server、port。',
                      ),
                    ),
                  ),
                  _ProxyGuideCodeCard(
                    title: 'Clash YAML 示例',
                    value: _clashExample,
                  ),
                ],
                if (_tab == 'direct') ...[
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('手动添加'),
                      subtitle: Text(
                        '表单地址只填域名或 IP，不要带协议头。HTTP、HTTPS 和 SOCKS5 均可用；有密码时同时填写账号。',
                      ),
                    ),
                  ),
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('批量导入'),
                      subtitle: Text(
                        '一行一个代理地址。地址格式为“协议://账号:密码@服务器:端口”，也可以在导入界面粘贴 JSON。',
                      ),
                    ),
                  ),
                  _ProxyGuideCodeCard(title: '代理地址示例', value: _proxyExample),
                ],
                if (_tab == 'ipfly') ...[
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('链式代理'),
                      subtitle: Text(
                        'first 填本机的 VPN 或前置代理，second 填 IPFLY 等落地代理。前置代理需先运行，端口和账号信息要与实际配置一致。',
                      ),
                    ),
                  ),
                  _ProxyGuideCodeCard(
                    title: '链式代理 JSON 示例',
                    value: _chainExample,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      prism.TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  );
}

class _ProxyGuideCodeCard extends StatelessWidget {
  const _ProxyGuideCodeCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => PrismCard(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              prism.TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (context.mounted) showPrismNotice(context, '示例已复制');
                },
                child: const Text('复制'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          prism.SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _ProxyCoreDownloadDialog extends StatefulWidget {
  const _ProxyCoreDownloadDialog();

  @override
  State<_ProxyCoreDownloadDialog> createState() =>
      _ProxyCoreDownloadDialogState();
}

class _ProxyCoreDownloadDialogState extends State<_ProxyCoreDownloadDialog> {
  final _proxyConfig = TextEditingController();
  String _core = 'xray';
  String _goos = 'windows';
  String _goarch = 'amd64';
  bool _loadingStatus = true;
  bool _loadingInfo = false;
  bool _starting = false;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _downloadInfo;
  late final void Function() _removeProgressListener;

  bool get _downloading =>
      _starting ||
      (_progress != null &&
          !{'done', 'error'}.contains(_progress!['phase']?.toString()));

  Map<String, Object?> get _request => {
    'core': _core,
    'goos': _goos,
    'goarch': _goarch,
    'proxyConfig': _proxyConfig.text.trim(),
  };

  @override
  void initState() {
    super.initState();
    _removeProgressListener = AppBridge.onEvent(
      'proxy-core:download:progress',
      _onProgress,
    );
    _refreshStatus();
  }

  @override
  void dispose() {
    _removeProgressListener();
    _proxyConfig.dispose();
    super.dispose();
  }

  void _onProgress(dynamic value) {
    if (!mounted || value is! Map) return;
    final progress = Map<String, dynamic>.from(value);
    if (progress['core'] != _core ||
        progress['goos'] != _goos ||
        progress['goarch'] != _goarch) {
      return;
    }
    setState(() => _progress = progress);
    if (progress['phase'] == 'done') unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    if (mounted) setState(() => _loadingStatus = true);
    try {
      final result = await AppBridge.call('BrowserProxyCoreStatus', [_request]);
      if (mounted)
        setState(() => _status = Map<String, dynamic>.from(result as Map));
    } catch (error) {
      if (mounted) showPrismNotice(context, '读取代理内核状态失败：$error');
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  void _changeTarget({String? core, String? goos, String? goarch}) {
    setState(() {
      _core = core ?? _core;
      _goos = goos ?? _goos;
      _goarch = goarch ?? _goarch;
      _progress = null;
      _downloadInfo = null;
    });
    _refreshStatus();
  }

  Future<void> _startDownload() async {
    if (_downloading) return;
    setState(() {
      _starting = true;
      _progress = {'phase': 'starting', 'progress': 0, 'message': '正在准备下载…'};
    });
    try {
      await AppBridge.call('BrowserProxyCoreDownload', [_request]);
    } catch (error) {
      if (mounted) {
        setState(() {
          _progress = {
            'phase': 'error',
            'progress': 0,
            'message': error.toString(),
          };
        });
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openRemoteDownload() async {
    setState(() => _loadingInfo = true);
    try {
      final result = await AppBridge.call('BrowserProxyCoreDownloadInfo', [
        _request,
      ]);
      final info = Map<String, dynamic>.from(result as Map);
      if (mounted) setState(() => _downloadInfo = info);
      final url = (info['downloadUrl'] ?? info['releaseUrl'] ?? '')
          .toString()
          .trim();
      if (url.isEmpty) {
        if (mounted) {
          showPrismNotice(
            context,
            (info['message'] ?? '没有可打开的下载地址').toString(),
          );
        }
      } else {
        AppBridge.openExternal(url);
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '获取下载地址失败：$error');
    } finally {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  Future<void> _openLocalDirectory() async {
    try {
      await AppBridge.call('BrowserProxyCoreOpenLocal', [_request]);
    } catch (error) {
      if (mounted) showPrismNotice(context, '打开代理内核目录失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => PrismDialog(
    title: const Text('代理内核'),
    content: SizedBox(
      width: 560,
      height: 500,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrismDropdownField<String>(
              key: ValueKey(_core),
              initialValue: _core,
              decoration: const PrismInputDecoration(labelText: '代理内核'),
              items: const [
                PrismDropdownItem(value: 'xray', child: Text('Xray')),
                PrismDropdownItem(value: 'mihomo', child: Text('Mihomo')),
                PrismDropdownItem(value: 'sing-box', child: Text('sing-box')),
                PrismDropdownItem(value: 'mieru', child: Text('mieru')),
              ],
              onChanged: _downloading
                  ? null
                  : (value) {
                      if (value != null) _changeTarget(core: value);
                    },
            ),
            Row(
              children: [
                Expanded(
                  child: PrismDropdownField<String>(
                    key: ValueKey(_goos),
                    initialValue: _goos,
                    decoration: const PrismInputDecoration(labelText: '目标系统'),
                    items: const [
                      PrismDropdownItem(
                        value: 'windows',
                        child: Text('Windows'),
                      ),
                      PrismDropdownItem(value: 'linux', child: Text('Linux')),
                      PrismDropdownItem(value: 'darwin', child: Text('macOS')),
                    ],
                    onChanged: _downloading
                        ? null
                        : (value) {
                            if (value != null) _changeTarget(goos: value);
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PrismDropdownField<String>(
                    key: ValueKey(_goarch),
                    initialValue: _goarch,
                    decoration: const PrismInputDecoration(labelText: '目标架构'),
                    items: const [
                      PrismDropdownItem(
                        value: 'amd64',
                        child: Text('amd64 / x64'),
                      ),
                      PrismDropdownItem(value: 'arm64', child: Text('arm64')),
                      PrismDropdownItem(value: '386', child: Text('386 / x86')),
                    ],
                    onChanged: _downloading
                        ? null
                        : (value) {
                            if (value != null) _changeTarget(goarch: value);
                          },
                  ),
                ),
              ],
            ),
            PrismTextField(
              controller: _proxyConfig,
              enabled: !_downloading,
              decoration: const PrismInputDecoration(
                labelText: '下载代理（可选）',
                hintText: '例如 http://127.0.0.1:7890',
              ),
            ),
            const SizedBox(height: 12),
            PrismCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _loadingStatus
                          ? '正在检查内核…'
                          : (_status?['message'] ?? '未知状态').toString(),
                    ),
                    if ((_status?['binaryPath'] ?? '').toString().isNotEmpty)
                      Text(
                        _status!['binaryPath'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            if (_progress case final progress?) ...[
              const SizedBox(height: 12),
              PrismCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (_downloading) ...[
                        const PrismProgressIndicator(size: 20),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          '${progress['message'] ?? ''} ${progress['progress'] ?? 0}%',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_downloadInfo case final info?)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text((info['message'] ?? '').toString()),
              ),
          ],
        ),
      ),
    ),
    actions: [
      prism.TextButton(
        onPressed: _downloading ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      prism.OutlinedButton(
        onPressed: _loadingInfo ? null : _openRemoteDownload,
        child: Text(_loadingInfo ? '查询中…' : '手动下载'),
      ),
      prism.OutlinedButton(
        onPressed: _openLocalDirectory,
        child: const Text('打开目录'),
      ),
      prism.FilledButton(
        onPressed: _downloading ? null : _startDownload,
        child: Text(_downloading ? '下载中…' : '开始下载'),
      ),
    ],
  );
}

class ProxyAlignPage extends StatefulWidget {
  const ProxyAlignPage({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<ProxyAlignPage> createState() => _ProxyAlignPageState();
}

class _ProxyAlignPageState extends State<ProxyAlignPage> {
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _records = [];
  String _sourceId = '';
  String _busy = '';
  bool _loading = true;

  List<Map<String, dynamic>> get _sources {
    final result = <String, Map<String, dynamic>>{};
    for (final proxy in _proxies) {
      final id = (proxy['sourceId'] ?? '').toString().trim();
      if (id.isNotEmpty) result.putIfAbsent(id, () => proxy);
    }
    return result.entries
        .map((entry) => {'sourceId': entry.key, ...entry.value})
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final value = await AppBridge.call('BrowserProxyList');
      _proxies = (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final sources = _sources;
      if (!sources.any((item) => item['sourceId'] == _sourceId) &&
          sources.isNotEmpty)
        _sourceId = sources.first['sourceId'].toString();
      if (_sourceId.isNotEmpty) await _loadRecords();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRecords() async {
    final result = await AppBridge.call('BrowserProxyAlignRecords', [
      _sourceId,
    ]);
    _records = (result as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _editSourceSettings(Map<String, dynamic> source) async {
    final sourceId = (source['sourceId'] ?? '').toString();
    final interval = TextEditingController(
      text: '${int.tryParse('${source['sourceRefreshIntervalM'] ?? 0}') ?? 60}',
    );
    var autoRefresh = source['sourceAutoRefresh'] == true;
    var fetchProxyId = (source['sourceFetchProxyId'] ?? '').toString();
    var saving = false;
    final saved = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('订阅源设置'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrismSwitchTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动刷新'),
                  value: autoRefresh,
                  onChanged: (value) => setDialog(() => autoRefresh = value),
                ),
                if (autoRefresh)
                  PrismTextField(
                    controller: interval,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '刷新间隔（分钟，5–1440）',
                    ),
                  ),
                PrismDropdownField<String>(
                  initialValue: fetchProxyId,
                  decoration: const PrismInputDecoration(
                    labelText: '拉取订阅使用的代理',
                  ),
                  items: [
                    const PrismDropdownItem(value: '', child: Text('直连')),
                    if (fetchProxyId.isNotEmpty &&
                        !_proxies.any(
                          (proxy) =>
                              (proxy['proxyId'] ?? '').toString() ==
                              fetchProxyId,
                        ))
                      PrismDropdownItem(
                        value: fetchProxyId,
                        child: const Text('当前拉取代理已不存在'),
                      ),
                    for (final proxy in _proxies)
                      if ((proxy['proxyId'] ?? '').toString().isNotEmpty)
                        PrismDropdownItem(
                          value: proxy['proxyId'].toString(),
                          child: Text(
                            (proxy['proxyName'] ?? '未命名代理').toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      setDialog(() => fetchProxyId = value ?? ''),
                ),
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final intervalM = autoRefresh
                          ? (int.tryParse(interval.text) ?? 60).clamp(5, 1440)
                          : 0;
                      setDialog(() => saving = true);
                      try {
                        await AppBridge.call('BrowserProxyUpdateSourceConfig', [
                          sourceId,
                          autoRefresh,
                          intervalM,
                          fetchProxyId,
                        ]);
                        if (context.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (context.mounted) {
                          showPrismNotice(context, '保存订阅源设置失败：$error');
                          setDialog(() => saving = false);
                        }
                      }
                    },
              child: Text(saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
    interval.dispose();
    if (saved == true && mounted) {
      await _load();
      if (mounted) showPrismNotice(context, '订阅源设置已保存');
    }
  }

  Future<void> _refreshAllSources() async {
    final sources = _sources;
    if (sources.isEmpty || _busy.isNotEmpty) return;
    setState(() => _busy = 'all');
    var succeeded = 0;
    final failed = <String>[];
    try {
      for (final source in sources) {
        final id = (source['sourceId'] ?? '').toString();
        try {
          await AppBridge.call('BrowserProxyRefreshSource', [
            id,
            source['sourceFetchProxyId'] ?? '',
          ]);
          succeeded++;
        } catch (_) {
          failed.add(
            (source['sourceNamePrefix'] ?? source['sourceUrl'] ?? id)
                .toString(),
          );
        }
      }
      await _load();
      if (mounted) {
        showPrismNotice(
          context,
          failed.isEmpty
              ? '已刷新 $succeeded 个订阅源'
              : '刷新完成：成功 $succeeded 个，失败 ${failed.length} 个',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAlignmentNodes(
    Map<String, dynamic> source,
  ) async {
    final url = (source['sourceUrl'] ?? '').toString();
    final fetchProxyId = (source['sourceFetchProxyId'] ?? '').toString();
    final fetched = await AppBridge.call(
      fetchProxyId.isEmpty
          ? 'BrowserProxyFetchClashByURL'
          : 'BrowserProxyFetchClashByURLWithProxy',
      fetchProxyId.isEmpty ? [url] : [url, fetchProxyId],
    );
    return _parseClashNodes(
      ((fetched as Map)['content'] ?? '').toString(),
      (source['sourceNamePrefix'] ?? '').toString(),
    );
  }

  Future<void> _refreshSource(
    Map<String, dynamic> source, {
    List<Map<String, dynamic>> manualPairs = const [],
  }) async {
    final id = source['sourceId'].toString();
    final originalIds = _proxies
        .where((proxy) => (proxy['sourceId'] ?? '').toString() == id)
        .map((proxy) => (proxy['proxyId'] ?? '').toString())
        .toSet();
    setState(() => _busy = id);
    try {
      final result = await AppBridge.call('BrowserProxyRefreshSource', [
        id,
        source['sourceFetchProxyId'] ?? '',
      ]);
      final value = Map<String, dynamic>.from(result as Map);
      if (manualPairs.isNotEmpty) {
        final current = await AppBridge.call('BrowserProxyList');
        final next = (current as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final now = DateTime.now().toUtc().toIso8601String();
        for (final pair in manualPairs) {
          final oldId = (pair['oldProxyId'] ?? '').toString();
          final nodeConfig = (pair['newNodeConfig'] ?? '').toString();
          final nodeName = (pair['newNodeName'] ?? '').toString();
          final newType = _clashConfigType(nodeConfig);
          final oldIndex = next.indexWhere(
            (proxy) => (proxy['proxyId'] ?? '').toString() == oldId,
          );
          if (oldIndex < 0 || nodeConfig.isEmpty) continue;
          next.removeWhere(
            (proxy) =>
                (proxy['sourceId'] ?? '').toString() == id &&
                !originalIds.contains((proxy['proxyId'] ?? '').toString()) &&
                (proxy['proxyConfig'] ?? '').toString() == nodeConfig,
          );
          final index = next.indexWhere(
            (proxy) => (proxy['proxyId'] ?? '').toString() == oldId,
          );
          if (index < 0) continue;
          final old = next[index];
          next[index] = {
            ...old,
            'proxyName': nodeName,
            'proxyConfig': nodeConfig,
            'preferredKernel':
                _clashConfigType((old['proxyConfig'] ?? '').toString()) ==
                    newType
                ? old['preferredKernel'] ?? 'auto'
                : 'auto',
            'sourceMissing': false,
            'sourceMissingSince': '',
            'sourceLastRefreshAt': now,
            'sourceLastRefreshError': '',
          };
        }
        await AppBridge.call('SaveBrowserProxies', [next]);
        value['manualMatched'] = manualPairs.length;
      }
      final alignmentSummary = manualPairs.isEmpty
          ? ''
          : '手动匹配 ${value['manualMatched'] ?? 0}，';
      if (mounted)
        showPrismNotice(
          context,
          ('刷新完成：$alignmentSummary新增 ${value['added'] ?? 0}，标记异常 ${value['markedMissing'] ?? 0}')
              .toString(),
        );
      await _load();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _openManualAlign(Map<String, dynamic> source) async {
    final sourceId = source['sourceId'].toString();
    final oldProxies = _proxies
        .where((proxy) => (proxy['sourceId'] ?? '').toString() == sourceId)
        .toList();
    if (oldProxies.isEmpty || _busy.isNotEmpty) return;
    setState(() => _busy = 'preview:$sourceId');
    try {
      final nodes = await _fetchAlignmentNodes(source);
      if (!mounted) return;
      if (nodes.isEmpty) throw StateError('订阅中没有可匹配的节点');
      final pairs = await showPrismDialog<List<Map<String, dynamic>>>(
        context: context,
        useRootNavigator: false,
        builder: (context) => _ProxyManualAlignmentDialog(
          oldProxies: oldProxies,
          newNodes: nodes,
        ),
      );
      if (!mounted || pairs == null || pairs.isEmpty) return;
      await _refreshSource(source, manualPairs: pairs);
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted && _busy == 'preview:$sourceId') setState(() => _busy = '');
    }
  }

  String _clashConfigType(String value) {
    try {
      final parsed = jsonDecode(value);
      if (parsed is List && parsed.isNotEmpty && parsed.first is Map) {
        return (parsed.first['type'] ?? '').toString().toLowerCase();
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final source = _sources
        .where((item) => item['sourceId'] == _sourceId)
        .firstOrNull;
    final theme = prism.Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              prism.IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  '订阅源管理与记录',
                  style: prism.AppTextStyle.title2.of(context),
                ),
              ),
              prism.IconButton(
                tooltip: '刷新记录',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_sources.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: PrismDropdownField<String>(
                    initialValue: _sourceId,
                    decoration: const PrismInputDecoration(labelText: '订阅来源'),
                    items: [
                      for (final item in _sources)
                        PrismDropdownItem(
                          value: item['sourceId'].toString(),
                          child: Text(
                            (item['sourceNamePrefix'] ??
                                    item['sourceUrl'] ??
                                    item['sourceId'])
                                .toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() {
                        _sourceId = value;
                        _loading = true;
                      });
                      try {
                        await _loadRecords();
                      } catch (error) {
                        if (mounted)
                          showPrismNotice(
                            context,
                            (error.toString()).toString(),
                          );
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                prism.OutlinedButton.icon(
                  onPressed: source == null || _busy.isNotEmpty
                      ? null
                      : () => _openManualAlign(source),
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('手动匹配'),
                ),
                prism.IconButton(
                  tooltip: '编辑当前订阅源设置',
                  onPressed: source == null || _busy.isNotEmpty
                      ? null
                      : () => _editSourceSettings(source),
                  icon: const Icon(Icons.settings_outlined),
                ),
                prism.IconButton(
                  tooltip: '刷新全部订阅源',
                  onPressed: _busy.isNotEmpty || _sources.isEmpty
                      ? null
                      : _refreshAllSources,
                  icon: _busy == 'all'
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: PrismProgressIndicator(size: 18),
                        )
                      : const Icon(Icons.sync),
                ),
                const SizedBox(width: 8),
                prism.FilledButton.icon(
                  onPressed: source == null || _busy.isNotEmpty
                      ? null
                      : () => _refreshSource(source),
                  icon: const Icon(Icons.sync),
                  label: Text(_busy.isNotEmpty ? '处理中…' : '刷新订阅'),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : _sources.isEmpty
                ? const Center(child: Text('还没有订阅来源'))
                : _records.isEmpty
                ? const Center(child: Text('还没有对齐记录，点击“手动匹配”可在刷新前指定节点对应关系'))
                : ListView(
                    children: [
                      for (final record in _records)
                        PrismCard(
                          child: PrismListTile(
                            leading: Icon(
                              record['mode'] == 'auto'
                                  ? Icons.auto_mode
                                  : Icons.compare_arrows,
                            ),
                            title: Text(
                              record['mode'] == 'auto' ? '自动刷新记录' : '手动匹配记录',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${record['at'] ?? ''} · 新增 ${record['added'] ?? 0} · 保留异常 ${record['keptMissing'] ?? 0}',
                                ),
                                for (final pair
                                    in (record['pairs'] as List? ?? [])
                                        .whereType<Map>())
                                  Text(
                                    '${pair['oldName'] ?? ''} → ${pair['newName'] ?? ''} · ${pair['match'] ?? ''}',
                                    style: prism.AppTextStyle.footnote
                                        .of(context)
                                        .copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
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

class _ProxyManualAlignmentDialog extends StatefulWidget {
  const _ProxyManualAlignmentDialog({
    required this.oldProxies,
    required this.newNodes,
  });

  final List<Map<String, dynamic>> oldProxies;
  final List<Map<String, dynamic>> newNodes;

  @override
  State<_ProxyManualAlignmentDialog> createState() =>
      _ProxyManualAlignmentDialogState();
}

class _ProxyManualAlignmentDialogState
    extends State<_ProxyManualAlignmentDialog> {
  final Map<String, int> _selectedNodes = {};

  String _nodeLabel(Map<String, dynamic> node) {
    final endpoint = [
      '${node['server'] ?? ''}:${node['port'] ?? ''}',
      '${node['type'] ?? ''}',
    ].where((part) => part.replaceAll(':', '').trim().isNotEmpty).join(' · ');
    return endpoint.isEmpty
        ? '${node['name'] ?? '未命名节点'}'
        : '${node['name'] ?? '未命名节点'} · $endpoint';
  }

  @override
  Widget build(BuildContext context) {
    final theme = prism.Theme.of(context);
    return PrismDialog(
      title: const Text('手动匹配订阅节点'),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '为需要保留实例绑定的旧代理选择新的订阅节点。未选择的代理仍按自动规则刷新。',
              style: prism.AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: widget.oldProxies.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final proxy = widget.oldProxies[index];
                  final proxyId = (proxy['proxyId'] ?? '').toString();
                  final selected = _selectedNodes[proxyId];
                  final options = widget.newNodes.where((node) {
                    final nodeIndex = node['index'] as int;
                    final usedByOther = _selectedNodes.entries.any(
                      (entry) =>
                          entry.key != proxyId && entry.value == nodeIndex,
                    );
                    return !usedByOther || selected == nodeIndex;
                  }).toList();
                  return PrismCard(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (proxy['proxyName'] ?? '未命名代理').toString(),
                            style: prism.AppTextStyle.subheadline.of(context),
                          ),
                          const SizedBox(height: 8),
                          PrismDropdownField<int>(
                            initialValue: selected,
                            isExpanded: true,
                            decoration: const PrismInputDecoration(
                              labelText: '对应的新节点',
                              isDense: true,
                            ),
                            items: [
                              for (final node in options)
                                PrismDropdownItem(
                                  value: node['index'] as int,
                                  child: Text(
                                    _nodeLabel(node),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              if (value == null) {
                                _selectedNodes.remove(proxyId);
                              } else {
                                _selectedNodes[proxyId] = value;
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
        prism.FilledButton(
          onPressed: _selectedNodes.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final entry in _selectedNodes.entries)
                    {
                      'oldProxyId': entry.key,
                      'newNodeIndex': entry.value,
                      'newNodeKey': widget.newNodes.firstWhere(
                        (node) => node['index'] == entry.value,
                      )['key'],
                      'newNodeName': widget.newNodes.firstWhere(
                        (node) => node['index'] == entry.value,
                      )['name'],
                      'newNodeConfig': widget.newNodes.firstWhere(
                        (node) => node['index'] == entry.value,
                      )['config'],
                    },
                ]),
          child: Text('应用并刷新（${_selectedNodes.length}）'),
        ),
      ],
    );
  }
}

class ProxyGroupsPage extends StatefulWidget {
  const ProxyGroupsPage({super.key});
  @override
  State<ProxyGroupsPage> createState() => _ProxyGroupsPageState();
}

class _ProxyGroupsPageState extends State<ProxyGroupsPage> {
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _health = [];
  bool _loading = true;
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        AppBridge.call('BrowserProxyVirtualGroupList'),
        AppBridge.call('BrowserProxyList'),
        AppBridge.call('BrowserProxyVirtualGroupHealthList'),
      ]);
      _groups = (values[0] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _proxies = (values[1] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _health = (values[2] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([Map<String, dynamic>? group]) async {
    final name = TextEditingController(
      text: (group?['groupName'] ?? '').toString(),
    );
    var strategy = (group?['strategy'] ?? 'round_robin').toString();
    final selected = Set<String>.from(
      (group?['memberProxyIds'] as List? ?? []).map((e) => e.toString()),
    );
    final result = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: Text(group == null ? '新建虚拟分组' : '编辑虚拟分组'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrismTextField(
                  controller: name,
                  decoration: const PrismInputDecoration(labelText: '分组名称'),
                ),
                PrismDropdownField<String>(
                  initialValue: strategy,
                  decoration: const PrismInputDecoration(labelText: '分配方式'),
                  items: const [
                    PrismDropdownItem(value: 'round_robin', child: Text('轮询')),
                    PrismDropdownItem(value: 'sticky', child: Text('固定节点')),
                  ],
                  onChanged: (value) =>
                      setDialog(() => strategy = value ?? 'round_robin'),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('选择成员代理'),
                ),
                SizedBox(
                  height: 230,
                  child: ListView(
                    children: [
                      for (final proxy in _proxies)
                        PrismCheckboxTile(
                          value: selected.contains(proxy['proxyId']),
                          title: Text(
                            (proxy['proxyName'] ?? proxy['proxyId'] ?? '')
                                .toString(),
                          ),
                          onChanged: (value) => setDialog(() {
                            value == true
                                ? selected.add(proxy['proxyId'].toString())
                                : selected.remove(proxy['proxyId'].toString());
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == true && name.text.trim().isNotEmpty) {
      final id =
          (group?['groupId'] ??
                  'group-${DateTime.now().millisecondsSinceEpoch}')
              .toString();
      final value = <String, dynamic>{
        ...?group,
        'groupId': id,
        'groupName': name.text.trim(),
        'strategy': strategy,
        'memberProxyIds': selected.toList(),
      };
      await AppBridge.call('SaveBrowserProxyVirtualGroup', [value]);
      await _refresh();
    }
    name.dispose();
  }

  Future<void> _probe(Map<String, dynamic> group) async {
    final id = (group['groupId'] ?? '').toString();
    setState(() => _busy = id);
    try {
      await AppBridge.call('BrowserProxyVirtualGroupProbe', [id]);
      await _refresh();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _delete(Map<String, dynamic> group) async {
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除虚拟分组？'),
        content: Text((group['groupName'] ?? '').toString()),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await AppBridge.call('DeleteBrowserProxyVirtualGroup', [
        group['groupId'],
      ]);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '代理虚拟分组',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            prism.IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
            prism.FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('新建分组'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: PrismProgressIndicator())
              : _groups.isEmpty
              ? const Center(child: Text('还没有虚拟分组'))
              : ListView(
                  children: [
                    for (final group in _groups)
                      Builder(
                        builder: (context) {
                          final id = (group['groupId'] ?? '').toString();
                          final healthRows = _health.where(
                            (row) => row['groupId'] == id,
                          );
                          final health = healthRows.isEmpty
                              ? null
                              : healthRows.first;
                          final members =
                              (group['memberProxyIds'] as List? ?? []).length;
                          return PrismCard(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: PrismListTile(
                              title: Text(
                                (group['groupName'] ?? id).toString(),
                              ),
                              subtitle: Text(
                                '${group['strategy'] == 'sticky' ? '固定节点' : '轮询'} · $members 个成员 · ${health?['status'] ?? '状态未知'}',
                              ),
                              trailing: Wrap(
                                children: [
                                  prism.IconButton(
                                    tooltip: '探测',
                                    onPressed: _busy == id
                                        ? null
                                        : () => _probe(group),
                                    icon: _busy == id
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: PrismProgressIndicator(),
                                          )
                                        : const Icon(
                                            Icons.health_and_safety_outlined,
                                          ),
                                  ),
                                  prism.IconButton(
                                    tooltip: '编辑',
                                    onPressed: () => _edit(group),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  prism.IconButton(
                                    tooltip: '删除',
                                    onPressed: () => _delete(group),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}
