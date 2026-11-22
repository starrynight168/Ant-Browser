import 'dart:convert';

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;
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
  List<Map<String, dynamic>> _proxies = [];
  bool _loading = true;
  String _busy = '';
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final result = await AppBridge.call('BrowserProxyList');
      _proxies = (result as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
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

  Future<void> _test(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    setState(() => _busy = id);
    try {
      final result = await AppBridge.call('BrowserProxyTestSpeed', [id]);
      final row = Map<String, dynamic>.from(result as Map);
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
      final row = result is Map ? Map<String, dynamic>.from(result) : {};
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
    final visible = _proxies
        .where(
          (item) =>
              '${item['proxyName'] ?? ''} ${item['proxyConfig'] ?? ''} ${item['groupName'] ?? ''}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PrismTextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const PrismInputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索代理或分组',
                  ),
                ),
              ),
              prism.IconButton(
                tooltip: '刷新',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
              prism.IconButton(
                tooltip: '代理检测设置',
                onPressed: _editCheckSettings,
                icon: const Icon(Icons.tune),
              ),
              prism.OutlinedButton.icon(
                onPressed: widget.onOpenGroups,
                icon: const Icon(Icons.hub_outlined),
                label: const Text('虚拟分组'),
              ),
              const SizedBox(width: 8),
              prism.OutlinedButton.icon(
                onPressed: widget.onOpenAlign,
                icon: const Icon(Icons.sync_alt),
                label: const Text('订阅记录'),
              ),
              const SizedBox(width: 8),
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty ? _importSubscription : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(_busy == 'subscription' ? '导入中…' : '导入订阅'),
              ),
              const SizedBox(width: 8),
              prism.FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('添加代理'),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                      return PrismCard(
                        child: PrismListTile(
                          title: Text((item['proxyName'] ?? id).toString()),
                          subtitle: Text(
                            '${item['proxyConfig'] ?? ''}${(item['groupName'] ?? '').toString().isEmpty ? '' : ' · ${item['groupName']}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Wrap(
                            children: [
                              prism.IconButton(
                                tooltip: '检查代理 IP',
                                onPressed: _busy == id
                                    ? null
                                    : () => _testIpHealth(item),
                                icon: const Icon(Icons.public),
                              ),
                              prism.IconButton(
                                tooltip: '测试连接',
                                onPressed: _busy == id
                                    ? null
                                    : () => _test(item),
                                icon: _busy == id
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: PrismProgressIndicator(),
                                      )
                                    : const Icon(Icons.speed),
                              ),
                              prism.IconButton(
                                tooltip: '编辑',
                                onPressed: () => _edit(item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              prism.IconButton(
                                tooltip: '删除',
                                onPressed: () => _delete(item),
                                icon: const Icon(Icons.delete_outline),
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
                  '代理订阅记录',
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
