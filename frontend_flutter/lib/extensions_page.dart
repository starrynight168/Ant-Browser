import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'prism_components.dart';

import 'wails_bridge.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _proxies = [];
  Map<String, dynamic>? _lookup;
  bool _loading = true;
  String _busy = '';
  bool _useProxy = false;
  String _selectedProxyId = '';
  String? _error;

  @override
  void initState() {
    super.initState();
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
      final value = await WailsBridge.call('BrowserExtensionList');
      _items = (value as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      try {
        final proxies = await WailsBridge.call('BrowserProxyList');
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
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() => _busy = id);
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _lookupExtension() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    if (_useProxy && _selectedProxyConfig.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择下载代理')));
      return;
    }
    setState(() => _busy = 'lookup');
    try {
      final result = await WailsBridge.call('BrowserExtensionLookupWithProxy', [
        {
          'query': query,
          'useProxy': _useProxy,
          'proxyConfig': _selectedProxyConfig,
        },
      ]);
      if (mounted)
        setState(() => _lookup = Map<String, dynamic>.from(result as Map));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _install() async {
    final id = (_lookup?['extensionId'] ?? _query.text).toString().trim();
    if (id.isEmpty) return;
    if (_useProxy && _selectedProxyConfig.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择下载代理')));
      return;
    }
    await _run('install', () async {
      await WailsBridge.call('BrowserExtensionInstallWithProxy', [
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
    });
  }

  String get _selectedProxyConfig {
    final proxy = _proxies.where((item) => item['proxyId'] == _selectedProxyId);
    if (proxy.isEmpty) return '';
    return (proxy.first['proxyConfig'] ?? '').toString();
  }

  Future<void> _openManualInstall() async {
    final target = (_lookup?['extensionId'] ?? _query.text).toString().trim();
    if (target.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先输入插件 ID 或商店链接')));
      return;
    }
    try {
      final values = await Future.wait([
        WailsBridge.call('BrowserExtensionManualInstallGuide', [target]),
        WailsBridge.call('BrowserExtensionListManualDownloadFiles'),
      ]);
      if (!mounted || values[0] is! Map) return;
      final guide = Map<String, dynamic>.from(values[0] as Map);
      var files = (values[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('手动安装插件'),
            content: SizedBox(
              width: 560,
              height: 430,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('无法在线安装时，可在浏览器中打开下载地址，再把下载的文件放入此目录。'),
                  const SizedBox(height: 10),
                  SelectableText('下载地址：${guide['downloadUrl'] ?? ''}'),
                  SelectableText('下载目录：${guide['downloadDir'] ?? ''}'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await WailsBridge.call(
                          'BrowserExtensionOpenManualDownloadDir',
                        );
                      },
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('打开下载目录'),
                    ),
                  ),
                  const Divider(),
                  const Text('可导入的 CRX / ZIP 文件'),
                  Expanded(
                    child: files.isEmpty
                        ? const Center(child: Text('目录中还没有插件包'))
                        : ListView(
                            children: [
                              for (final file in files)
                                ListTile(
                                  title: Text(
                                    (file['fileName'] ?? '').toString(),
                                  ),
                                  subtitle: Text(
                                    (file['updatedAt'] ?? '').toString(),
                                  ),
                                  trailing: TextButton(
                                    onPressed: () async {
                                      try {
                                        await WailsBridge.call(
                                          'BrowserExtensionInstallManualDownloadFile',
                                          [file['fileName']],
                                        );
                                        await _refresh();
                                        if (context.mounted)
                                          Navigator.pop(context);
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
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
              TextButton(
                onPressed: () async {
                  try {
                    final value = await WailsBridge.call(
                      'BrowserExtensionListManualDownloadFiles',
                    );
                    files = (value as List? ?? [])
                        .whereType<Map>()
                        .map((row) => Map<String, dynamic>.from(row))
                        .toList();
                    setDialog(() {});
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  }
                },
                child: const Text('刷新文件'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _configureProfiles(Map<String, dynamic> extension) async {
    final extensionId = (extension['extensionId'] ?? '').toString();
    if (extensionId.isEmpty) return;
    setState(() => _busy = 'profiles:$extensionId');
    try {
      final profileResult = await WailsBridge.call('BrowserProfileList');
      final profiles = (profileResult as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final settingsResult = await Future.wait(
        profiles.map(
          (profile) => WailsBridge.call('BrowserProfileExtensionGet', [
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
      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text('选择安装实例 · ${extension['name'] ?? extensionId}'),
            content: SizedBox(
              width: 500,
              height: 440,
              child: profiles.isEmpty
                  ? const Center(child: Text('当前没有浏览器实例'))
                  : ListView(
                      children: [
                        for (final profile in profiles)
                          CheckboxListTile(
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
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
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
        await WailsBridge.call('BrowserProfileExtensionSave', [
          profileId,
          ids.toList(),
          true,
        ]);
      }
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('实例插件设置已保存')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
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
            IconButton(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: '导入插件',
              icon: const Icon(Icons.add),
              onSelected: (mode) {
                if (mode == 'manual') {
                  _openManualInstall();
                } else if (mode == 'download-dir') {
                  _run(mode, () async {
                    await WailsBridge.call(
                      'BrowserExtensionOpenManualDownloadDir',
                    );
                  });
                } else {
                  _run(mode, () async {
                    await WailsBridge.call(
                      mode == 'file'
                          ? 'BrowserExtensionInstallLocalFile'
                          : 'BrowserExtensionInstallLocalDirectory',
                    );
                  });
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'file', child: Text('从本地插件包导入')),
                PopupMenuItem(value: 'directory', child: Text('从本地文件夹导入')),
                PopupMenuItem(value: 'manual', child: Text('手动下载与导入')),
                PopupMenuItem(value: 'download-dir', child: Text('打开手动下载目录')),
              ],
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
                      child: TextField(
                        controller: _query,
                        decoration: const InputDecoration(
                          hintText: '粘贴插件 ID 或商店链接',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy.isEmpty ? _lookupExtension : null,
                      child: const Text('查询'),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('通过代理下载'),
                  value: _useProxy,
                  onChanged: (value) => setState(() => _useProxy = value),
                ),
                if (_useProxy)
                  DropdownButtonFormField<String>(
                    initialValue:
                        _proxies.any(
                          (proxy) => proxy['proxyId'] == _selectedProxyId,
                        )
                        ? _selectedProxyId
                        : null,
                    decoration: const InputDecoration(labelText: '下载代理'),
                    items: [
                      for (final proxy in _proxies)
                        DropdownMenuItem(
                          value: proxy['proxyId']?.toString(),
                          child: Text(
                            (proxy['proxyName'] ?? proxy['proxyId'] ?? '')
                                .toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedProxyId = value ?? ''),
                  ),
                if (_lookup case final result?) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${result['name'] ?? result['extensionId'] ?? ''}  ${result['version'] ?? ''}',
                  ),
                  Text(
                    (result['message'] ?? '').toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _busy.isEmpty && result['installable'] != false
                          ? _install
                          : null,
                      child: const Text('安装'),
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
              trailing: TextButton(
                onPressed: _refresh,
                child: const Text('重试'),
              ),
            ),
          ),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(),
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
            ? CircleAvatar(
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
            : const CircleAvatar(child: Icon(Icons.extension_outlined)),
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
            IconButton(
              tooltip: '重新安装 / 更新',
              onPressed: busy
                  ? null
                  : () => _run(id, () async {
                      await WailsBridge.call(
                        'BrowserExtensionInstallWithProxy',
                        [
                          {
                            'query': id,
                            'useProxy': _useProxy,
                            'proxyConfig': _selectedProxyConfig,
                          },
                        ],
                      );
                    }),
              icon: const Icon(Icons.system_update_alt),
            ),
            IconButton(
              tooltip: item['defaultInstall'] == true ? '取消默认安装' : '设为默认安装',
              onPressed: busy
                  ? null
                  : () => _run(id, () async {
                      await WailsBridge.call(
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
            IconButton(
              tooltip: '指定安装实例',
              onPressed: busy ? null : () => _configureProfiles(item),
              icon: const Icon(Icons.tune),
            ),
            Switch(
              value: item['enabled'] == true,
              onChanged: busy
                  ? null
                  : (value) => _run(id, () async {
                      await WailsBridge.call('BrowserExtensionSetEnabled', [
                        id,
                        value,
                      ]);
                    }),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: busy
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        useRootNavigator: false,
                        builder: (context) => AlertDialog(
                          title: const Text('删除插件？'),
                          content: Text((item['name'] ?? id).toString()),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true)
                        _run(id, () async {
                          await WailsBridge.call('BrowserExtensionDelete', [
                            id,
                          ]);
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
