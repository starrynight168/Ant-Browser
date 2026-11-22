import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  static const _historyKey = 'ant-chrome.extensionManagement.history.v1';
  static const _proxyPreferenceKey =
      'ant-chrome.extensionManagement.downloadProxy.v1';
  final _query = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _lookup;
  bool _loading = true;
  String _busy = '';
  bool _useProxy = false;
  String _selectedProxyId = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _history = _readHistory();
    try {
      final preference = jsonDecode(AppBridge.readStorage(_proxyPreferenceKey));
      if (preference is Map) {
        _useProxy = preference['useProxy'] == true;
        _selectedProxyId = (preference['proxyId'] ?? '').toString();
      }
    } catch (_) {}
    _refresh();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final value = await AppBridge.call('BrowserExtensionList');
      _items = (value as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      try {
        final proxies = await AppBridge.call('BrowserProxyList');
        _proxies = (proxies as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {
        _proxies = [];
      }
      if (!_proxies.any((proxy) => proxy['proxyId'] == _selectedProxyId)) {
        _selectedProxyId = '';
      }
      if (!_proxies.any((proxy) => proxy['proxyId'] == _selectedProxyId)) {
        _useProxy = false;
      }
      _saveProxyPreference();
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _readHistory() {
    try {
      final value = jsonDecode(AppBridge.readStorage(_historyKey));
      return (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .take(100)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _appendHistory(Map<String, dynamic> entry) {
    final record = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'createdAt': DateTime.now().toIso8601String(),
      ...entry,
    };
    if (mounted) {
      setState(() => _history = [record, ..._history].take(100).toList());
    } else {
      _history = [record, ..._history].take(100).toList();
    }
    AppBridge.writeStorage(_historyKey, jsonEncode(_history));
  }

  void _saveProxyPreference() {
    AppBridge.writeStorage(
      _proxyPreferenceKey,
      jsonEncode({'useProxy': _useProxy, 'proxyId': _selectedProxyId}),
    );
  }

  Future<void> _openExternalUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return;
    final command = Platform.isWindows
        ? ('rundll32.exe', ['url.dll,FileProtocolHandler', uri.toString()])
        : Platform.isMacOS
        ? ('open', [uri.toString()])
        : ('xdg-open', [uri.toString()]);
    try {
      await Process.run(command.$1, command.$2);
    } catch (error) {
      if (mounted) showPrismNotice(context, '打开链接失败：$error');
    }
  }

  Future<void> _run(
    String id,
    Future<void> Function() action, {
    Map<String, dynamic>? history,
  }) async {
    setState(() => _busy = id);
    try {
      await action();
      if (history != null)
        _appendHistory({...history, 'ok': true, 'message': ''});
      await _refresh();
    } catch (error) {
      if (history != null) {
        _appendHistory({...history, 'ok': false, 'message': '$error'});
      }
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _lookupExtension() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    if (_useProxy && _selectedProxyConfig.isEmpty) {
      showPrismNotice(context, ('请先选择下载代理').toString());
      return;
    }
    setState(() => _busy = 'lookup');
    try {
      final result = await AppBridge.call('BrowserExtensionLookupWithProxy', [
        {
          'query': query,
          'useProxy': _useProxy,
          'proxyConfig': _selectedProxyConfig,
        },
      ]);
      if (mounted) {
        setState(() => _lookup = Map<String, dynamic>.from(result as Map));
        final value = Map<String, dynamic>.from(result as Map);
        _appendHistory({
          'action': 'lookup',
          'query': query,
          'extensionId': (value['extensionId'] ?? '').toString(),
          'name': (value['name'] ?? '').toString(),
          'version': (value['version'] ?? '').toString(),
          'storeUrl': (value['storeUrl'] ?? '').toString(),
          'proxyLabel': _useProxy ? _selectedProxyId : '直连查询',
          'ok': true,
          'message': (value['message'] ?? '').toString(),
        });
      }
    } catch (error) {
      _appendHistory({
        'action': 'lookup',
        'query': query,
        'extensionId': '',
        'name': '',
        'version': '',
        'storeUrl': '',
        'proxyLabel': _useProxy ? _selectedProxyId : '直连查询',
        'ok': false,
        'message': '$error',
      });
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _install() async {
    final id = (_lookup?['extensionId'] ?? _query.text).toString().trim();
    if (id.isEmpty) return;
    if (_useProxy && _selectedProxyConfig.isEmpty) {
      showPrismNotice(context, ('请先选择下载代理').toString());
      return;
    }
    await _run(
      'install',
      () async {
        await AppBridge.call('BrowserExtensionInstallWithProxy', [
          {
            'query': id,
            'useProxy': _useProxy,
            'proxyConfig': _selectedProxyConfig,
          },
        ]);
        if (mounted)
          setState(() {
            _lookup = null;
            _query.clear();
          });
      },
      history: {
        'action': 'install',
        'query': id,
        'extensionId': (_lookup?['extensionId'] ?? id).toString(),
        'name': (_lookup?['name'] ?? '').toString(),
        'version': (_lookup?['version'] ?? '').toString(),
        'storeUrl': (_lookup?['storeUrl'] ?? '').toString(),
        'proxyLabel': _useProxy ? _selectedProxyId : '直连',
      },
    );
  }

  String get _selectedProxyConfig {
    final proxy = _proxies.where((item) => item['proxyId'] == _selectedProxyId);
    if (proxy.isEmpty) return '';
    return (proxy.first['proxyConfig'] ?? '').toString();
  }

  String _historyActionLabel(String value) => switch (value) {
    'install' => '安装',
    'import' => '导入',
    _ => '查询',
  };

  Future<void> _showHistory() async {
    var records = List<Map<String, dynamic>>.from(_history);
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('插件操作历史'),
          content: SizedBox(
            width: 700,
            height: 520,
            child: records.isEmpty
                ? const Center(child: Text('暂无插件查询、安装或导入记录'))
                : ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final success = record['ok'] == true;
                      final storeUrl = (record['storeUrl'] ?? '').toString();
                      return PrismCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: PrismListTile(
                          title: Text(
                            '${_historyActionLabel((record['action'] ?? '').toString())} · ${record['name'] ?? record['extensionId'] ?? record['query'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${success ? '成功' : '失败'} · ${record['createdAt'] ?? ''}\n${record['message'] ?? record['query'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          leading: Icon(
                            success
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: success
                                ? prism.Theme.of(context).colorScheme.tertiary
                                : prism.Theme.of(context).colorScheme.error,
                          ),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              prism.TextButton(
                                onPressed: () {
                                  _query.text = (record['query'] ?? '')
                                      .toString();
                                  Navigator.pop(context);
                                },
                                child: const Text('使用'),
                              ),
                              if (storeUrl.isNotEmpty)
                                prism.IconButton(
                                  tooltip: '打开商店页',
                                  onPressed: () => _openExternalUrl(storeUrl),
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () {
                records = [];
                _history = [];
                AppBridge.writeStorage(_historyKey, '[]');
                setDialog(() {});
              },
              child: const Text('清空历史'),
            ),
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openStoreSearch() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    final url = RegExp(r'^[a-p]{32}$', caseSensitive: false).hasMatch(query)
        ? 'https://chromewebstore.google.com/detail/${query.toLowerCase()}'
        : 'https://chromewebstore.google.com/search/${Uri.encodeComponent(query)}';
    await _openExternalUrl(url);
  }

  Future<void> _showInstalledProfiles(Map<String, dynamic> extension) async {
    final extensionId = (extension['extensionId'] ?? '').toString();
    if (extensionId.isEmpty) return;
    try {
      final profileResult = await AppBridge.call('BrowserProfileList');
      final profiles = (profileResult as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final settings = await Future.wait(
        profiles.map(
          (profile) => AppBridge.call('BrowserProfileExtensionGet', [
            profile['profileId'],
          ]),
        ),
      );
      final usingProfiles = <Map<String, dynamic>>[];
      for (var index = 0; index < profiles.length; index++) {
        final value = Map<String, dynamic>.from(settings[index] as Map);
        final extensionIds = (value['extensionIds'] as List? ?? [])
            .map((id) => id.toString())
            .toSet();
        final usesExtension = value['configured'] == true
            ? extensionIds.contains(extensionId)
            : extension['enabled'] == true &&
                  extension['defaultInstall'] == true;
        if (usesExtension) usingProfiles.add(profiles[index]);
      }
      if (!mounted) return;
      await showPrismDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: Text('使用实例 · ${extension['name'] ?? extensionId}'),
            content: SizedBox(
              width: 600,
              height: 450,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '共 ${usingProfiles.length} 个实例配置使用此插件。插件在实例启动时加载，修改配置后需要重启实例。',
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: usingProfiles.isEmpty
                        ? const Center(child: Text('没有实例配置使用此插件'))
                        : ListView(
                            children: [
                              for (final profile in usingProfiles)
                                PrismListTile(
                                  title: Text(
                                    (profile['profileName'] ??
                                            profile['profileId'] ??
                                            '')
                                        .toString(),
                                  ),
                                  subtitle: Text(
                                    (profile['profileId'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  leading: Icon(
                                    profile['running'] == true
                                        ? Icons.play_circle_outline
                                        : Icons.stop_circle_outlined,
                                  ),
                                  trailing: prism.OutlinedButton(
                                    onPressed: () async {
                                      final id = (profile['profileId'] ?? '')
                                          .toString();
                                      final running =
                                          profile['running'] == true;
                                      try {
                                        await AppBridge.call(
                                          running
                                              ? 'BrowserInstanceStop'
                                              : 'BrowserInstanceStart',
                                          [id],
                                        );
                                        setDialog(() {
                                          profile['running'] = !running;
                                        });
                                      } catch (error) {
                                        if (context.mounted) {
                                          showPrismNotice(
                                            context,
                                            '操作实例失败：$error',
                                          );
                                        }
                                      }
                                    },
                                    child: Text(
                                      profile['running'] == true ? '停止' : '启动',
                                    ),
                                  ),
                                ),
                            ],
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
        ),
      );
    } catch (error) {
      if (mounted) showPrismNotice(context, '读取实例插件状态失败：$error');
    }
  }

  Future<void> _openManualInstall() async {
    final target = (_lookup?['extensionId'] ?? _query.text).toString().trim();
    if (target.isEmpty) {
      showPrismNotice(context, ('请先输入插件 ID 或商店链接').toString());
      return;
    }
    try {
      final values = await Future.wait([
        AppBridge.call('BrowserExtensionManualInstallGuide', [target]),
        AppBridge.call('BrowserExtensionListManualDownloadFiles'),
      ]);
      if (!mounted || values[0] is! Map) return;
      final guide = Map<String, dynamic>.from(values[0] as Map);
      var files = (values[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      await showPrismDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: const Text('手动安装插件'),
            content: SizedBox(
              width: 560,
              height: 430,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('无法在线安装时，可在浏览器中打开下载地址，再把下载的文件放入此目录。'),
                  const SizedBox(height: 10),
                  prism.SelectableText('下载地址：${guide['downloadUrl'] ?? ''}'),
                  prism.SelectableText('下载目录：${guide['downloadDir'] ?? ''}'),
                  Wrap(
                    spacing: 8,
                    children: [
                      prism.TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: (guide['downloadUrl'] ?? '').toString(),
                            ),
                          );
                          showPrismNotice(context, '下载地址已复制');
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('复制下载地址'),
                      ),
                      if ((guide['storeUrl'] ?? '').toString().isNotEmpty)
                        prism.TextButton.icon(
                          onPressed: () => _openExternalUrl(
                            (guide['storeUrl'] ?? '').toString(),
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('打开商店页'),
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: prism.TextButton.icon(
                      onPressed: () async {
                        await AppBridge.call(
                          'BrowserExtensionOpenManualDownloadDir',
                        );
                      },
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('打开下载目录'),
                    ),
                  ),
                  const prism.Divider(),
                  const Text('可导入的 CRX / ZIP 文件'),
                  Expanded(
                    child: files.isEmpty
                        ? const Center(child: Text('目录中还没有插件包'))
                        : ListView(
                            children: [
                              for (final file in files)
                                PrismListTile(
                                  title: Text(
                                    (file['fileName'] ?? '').toString(),
                                  ),
                                  subtitle: Text(
                                    (file['updatedAt'] ?? '').toString(),
                                  ),
                                  trailing: prism.TextButton(
                                    onPressed: () async {
                                      try {
                                        await AppBridge.call(
                                          'BrowserExtensionInstallManualDownloadFile',
                                          [file['fileName']],
                                        );
                                        _appendHistory({
                                          'action': 'import',
                                          'query': file['fileName'] ?? '',
                                          'extensionId': '',
                                          'name': file['fileName'] ?? '',
                                          'version': '',
                                          'storeUrl': '',
                                          'proxyLabel': '',
                                          'ok': true,
                                          'message': '本地插件包导入成功',
                                        });
                                        await _refresh();
                                        if (context.mounted)
                                          Navigator.pop(context);
                                      } catch (error) {
                                        if (context.mounted) {
                                          showPrismNotice(
                                            context,
                                            (error.toString()).toString(),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('导入'),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: () async {
                  try {
                    await AppBridge.call(
                      'BrowserExtensionInstallLocalDirectory',
                    );
                    _appendHistory({
                      'action': 'import',
                      'query': '本地插件目录',
                      'extensionId': '',
                      'name': '',
                      'version': '',
                      'storeUrl': '',
                      'proxyLabel': '',
                      'ok': true,
                      'message': '本地插件目录导入成功',
                    });
                    await _refresh();
                  } catch (error) {
                    if (context.mounted) {
                      showPrismNotice(context, '导入目录失败：$error');
                    }
                  }
                },
                child: const Text('导入目录'),
              ),
              prism.TextButton(
                onPressed: () async {
                  try {
                    final value = await AppBridge.call(
                      'BrowserExtensionListManualDownloadFiles',
                    );
                    files = (value as List? ?? [])
                        .whereType<Map>()
                        .map((row) => Map<String, dynamic>.from(row))
                        .toList();
                    setDialog(() {});
                  } catch (error) {
                    if (context.mounted) {
                      showPrismNotice(context, (error.toString()).toString());
                    }
                  }
                },
                child: const Text('刷新文件'),
              ),
              prism.TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    }
  }

  Future<void> _configureProfiles(Map<String, dynamic> extension) async {
    final extensionId = (extension['extensionId'] ?? '').toString();
    if (extensionId.isEmpty) return;
    setState(() => _busy = 'profiles:$extensionId');
    try {
      final profileResult = await AppBridge.call('BrowserProfileList');
      final profiles = (profileResult as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final settingsResult = await Future.wait(
        profiles.map(
          (profile) => AppBridge.call('BrowserProfileExtensionGet', [
            profile['profileId'],
          ]),
        ),
      );
      final initial = <String, Map<String, dynamic>>{};
      final selected = <String>{};
      for (var i = 0; i < profiles.length; i++) {
        final profileId = (profiles[i]['profileId'] ?? '').toString();
        final settings = Map<String, dynamic>.from(settingsResult[i] as Map);
        initial[profileId] = settings;
        if ((settings['extensionIds'] as List? ?? []).contains(extensionId))
          selected.add(profileId);
      }
      if (!mounted) return;
      final saved = await showPrismDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: Text('选择安装实例 · ${extension['name'] ?? extensionId}'),
            content: SizedBox(
              width: 500,
              height: 440,
              child: profiles.isEmpty
                  ? const Center(child: Text('当前没有浏览器实例'))
                  : ListView(
                      children: [
                        for (final profile in profiles)
                          PrismCheckboxTile(
                            value: selected.contains(profile['profileId']),
                            title: Text(
                              (profile['profileName'] ??
                                      profile['profileId'] ??
                                      '')
                                  .toString(),
                            ),
                            subtitle: Text(
                              (profile['profileId'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (value) => setDialog(() {
                              final id = (profile['profileId'] ?? '')
                                  .toString();
                              if (value == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            }),
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
      if (saved != true) return;
      for (final profile in profiles) {
        final profileId = (profile['profileId'] ?? '').toString();
        final settings = initial[profileId] ?? const <String, dynamic>{};
        final ids = (settings['extensionIds'] as List? ?? [])
            .map((value) => value.toString())
            .toSet();
        final wasSelected = ids.contains(extensionId);
        final shouldSelect = selected.contains(profileId);
        if (wasSelected == shouldSelect) continue;
        if (shouldSelect) {
          ids.add(extensionId);
        } else {
          ids.remove(extensionId);
        }
        await AppBridge.call('BrowserProfileExtensionSave', [
          profileId,
          ids.toList(),
          true,
        ]);
      }
      if (mounted) showPrismNotice(context, ('实例插件设置已保存').toString());
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '插件包管理',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            prism.IconButton(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            PrismPopupMenuButton<String>(
              tooltip: '导入插件',
              icon: const Icon(Icons.add),
              onSelected: (mode) {
                if (mode == 'manual') {
                  _openManualInstall();
                } else if (mode == 'download-dir') {
                  _run(mode, () async {
                    await AppBridge.call(
                      'BrowserExtensionOpenManualDownloadDir',
                    );
                  });
                } else {
                  _run(
                    mode,
                    () async {
                      await AppBridge.call(
                        mode == 'file'
                            ? 'BrowserExtensionInstallLocalFile'
                            : 'BrowserExtensionInstallLocalDirectory',
                      );
                    },
                    history: {
                      'action': 'import',
                      'query': mode == 'file' ? '本地插件包' : '本地插件目录',
                      'extensionId': '',
                      'name': '',
                      'version': '',
                      'storeUrl': '',
                      'proxyLabel': '',
                    },
                  );
                }
              },
              itemBuilder: (_) => const [
                PrismMenuItem(value: 'file', child: Text('从本地插件包导入')),
                PrismMenuItem(value: 'directory', child: Text('从本地文件夹导入')),
                PrismMenuItem(value: 'manual', child: Text('手动下载与导入')),
                PrismMenuItem(value: 'download-dir', child: Text('打开手动下载目录')),
              ],
            ),
            const SizedBox(width: 8),
            prism.OutlinedButton.icon(
              onPressed: _showHistory,
              icon: const Icon(Icons.history),
              label: const Text('历史记录'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PrismCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '安装 Chrome 商店插件',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: PrismTextField(
                        controller: _query,
                        decoration: const PrismInputDecoration(
                          hintText: '粘贴插件 ID 或商店链接',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    prism.OutlinedButton(
                      onPressed: _busy.isEmpty ? _lookupExtension : null,
                      child: const Text('查询'),
                    ),
                    prism.OutlinedButton.icon(
                      onPressed: _openStoreSearch,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('网页查询'),
                    ),
                  ],
                ),
                PrismSwitchTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('通过代理下载'),
                  value: _useProxy,
                  onChanged: (value) {
                    setState(() => _useProxy = value);
                    _saveProxyPreference();
                  },
                ),
                if (_useProxy)
                  PrismDropdownField<String>(
                    initialValue:
                        _proxies.any(
                          (proxy) => proxy['proxyId'] == _selectedProxyId,
                        )
                        ? _selectedProxyId
                        : null,
                    decoration: const PrismInputDecoration(labelText: '下载代理'),
                    items: [
                      for (final proxy in _proxies)
                        PrismDropdownItem(
                          value: proxy['proxyId']?.toString(),
                          child: Text(
                            (proxy['proxyName'] ?? proxy['proxyId'] ?? '')
                                .toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedProxyId = value ?? '');
                      _saveProxyPreference();
                    },
                  ),
                if (_lookup case final result?) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${result['name'] ?? result['extensionId'] ?? ''}  ${result['version'] ?? ''}',
                  ),
                  Text(
                    (result['message'] ?? '').toString(),
                    style: TextStyle(
                      color: prism.Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if ((result['storeUrl'] ?? '').toString().isNotEmpty)
                          prism.OutlinedButton.icon(
                            onPressed: () => _openExternalUrl(
                              (result['storeUrl'] ?? '').toString(),
                            ),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('打开商店页'),
                          ),
                        prism.FilledButton(
                          onPressed:
                              _busy.isEmpty && result['installable'] != false
                              ? _install
                              : null,
                          child: const Text('安装'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_error != null)
          PrismCard(
            child: PrismListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(_error!),
              trailing: prism.TextButton(
                onPressed: _refresh,
                child: const Text('重试'),
              ),
            ),
          ),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: PrismProgressIndicator(),
            ),
          ),
        if (!_loading && _items.isEmpty && _error == null)
          const Center(
            child: Padding(padding: EdgeInsets.all(32), child: Text('还没有安装插件')),
          ),
        for (final item in _items) _extensionCard(item),
      ],
    );
  }

  Widget _extensionCard(Map<String, dynamic> item) {
    final id = (item['extensionId'] ?? '').toString();
    final icon = (item['iconDataUrl'] ?? '').toString();
    final busy = _busy == id;
    return PrismCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: PrismListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: icon.startsWith('data:image') && icon.contains(',')
            ? SizedBox(
                width: 40,
                height: 40,
                child: ClipOval(
                  child: Image.memory(
                    base64Decode(icon.substring(icon.indexOf(',') + 1)),
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.extension_outlined),
                  ),
                ),
              )
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: prism.Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.extension_outlined),
              ),
        title: Text((item['name'] ?? id).toString()),
        subtitle: Text(
          'v${item['version'] ?? '-'} · $id\n${item['description'] ?? ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            prism.IconButton(
              tooltip: '重新安装 / 更新',
              onPressed: busy
                  ? null
                  : () => _run(
                      id,
                      () async {
                        await AppBridge.call(
                          'BrowserExtensionInstallWithProxy',
                          [
                            {
                              'query': id,
                              'useProxy': _useProxy,
                              'proxyConfig': _selectedProxyConfig,
                            },
                          ],
                        );
                      },
                      history: {
                        'action': 'install',
                        'query': id,
                        'extensionId': id,
                        'name': item['name'] ?? '',
                        'version': item['version'] ?? '',
                        'storeUrl': item['sourceUrl'] ?? '',
                        'proxyLabel': _useProxy ? _selectedProxyId : '直连',
                      },
                    ),
              icon: const Icon(Icons.system_update_alt),
            ),
            prism.IconButton(
              tooltip: item['defaultInstall'] == true ? '取消默认安装' : '设为默认安装',
              onPressed: busy
                  ? null
                  : () => _run(id, () async {
                      await AppBridge.call(
                        'BrowserExtensionSetDefaultInstall',
                        [id, item['defaultInstall'] != true],
                      );
                    }),
              icon: Icon(
                item['defaultInstall'] == true
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
              ),
            ),
            prism.IconButton(
              tooltip: '指定安装实例',
              onPressed: busy ? null : () => _configureProfiles(item),
              icon: const Icon(Icons.tune),
            ),
            prism.IconButton(
              tooltip: '打开使用此插件的实例',
              onPressed: busy ? null : () => _showInstalledProfiles(item),
              icon: const Icon(Icons.open_in_browser_outlined),
            ),
            prism.Switch(
              value: item['enabled'] == true,
              onChanged: busy
                  ? null
                  : (value) => _run(id, () async {
                      await AppBridge.call('BrowserExtensionSetEnabled', [
                        id,
                        value,
                      ]);
                    }),
            ),
            prism.IconButton(
              tooltip: '删除',
              onPressed: busy
                  ? null
                  : () async {
                      final confirm = await showPrismDialog<bool>(
                        context: context,
                        useRootNavigator: false,
                        builder: (context) => PrismDialog(
                          title: const Text('删除插件？'),
                          content: Text((item['name'] ?? id).toString()),
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
                      if (confirm == true)
                        _run(id, () async {
                          await AppBridge.call('BrowserExtensionDelete', [id]);
                        });
                    },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}
