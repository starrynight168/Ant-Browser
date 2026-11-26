import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

String _formatExtensionFileSize(dynamic rawBytes) {
  final bytes = (rawBytes is num)
      ? rawBytes.toDouble()
      : double.tryParse('$rawBytes') ?? 0;
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final digits = index == 0 ? 0 : (value >= 100 ? 0 : (value >= 10 ? 1 : 2));
  return '${value.toStringAsFixed(digits)} ${units[index]}';
}

String _formatExtensionTime(dynamic raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final local = parsed.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _ParsedManifestInfo {
  const _ParsedManifestInfo({
    this.manifestVersion,
    this.permissions = const [],
    this.hostPermissionCount = 0,
  });

  final int? manifestVersion;
  final List<String> permissions;
  final int hostPermissionCount;
}

_ParsedManifestInfo _parseManifestJson(dynamic raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return const _ParsedManifestInfo();
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return const _ParsedManifestInfo();
    final mv = (decoded['manifest_version'] as num?)?.toInt();
    final rawPerms = (decoded['permissions'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final apiPerms = <String>[];
    final hostPatterns = <String>{};
    for (final perm in rawPerms) {
      if (perm.contains('://') || perm == '<all_urls>') {
        hostPatterns.add(perm);
      } else {
        apiPerms.add(perm);
      }
    }
    for (final host in (decoded['host_permissions'] as List? ?? [])) {
      final value = host.toString().trim();
      if (value.isNotEmpty) hostPatterns.add(value);
    }
    for (final script in (decoded['content_scripts'] as List? ?? [])) {
      if (script is Map) {
        for (final match in (script['matches'] as List? ?? [])) {
          final value = match.toString().trim();
          if (value.isNotEmpty) hostPatterns.add(value);
        }
      }
    }
    return _ParsedManifestInfo(
      manifestVersion: mv,
      permissions: apiPerms,
      hostPermissionCount: hostPatterns.length,
    );
  } catch (_) {
    return const _ParsedManifestInfo();
  }
}

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
  final _filterQuery = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _lookup;
  String _lookupMethodLabel = '';
  String _statusFilter = 'all';
  bool _storePanelExpanded = false;
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
    _filterQuery.dispose();
    super.dispose();
  }

  String get _selectedProxyConfig {
    final proxy = _proxies.where((item) => item['proxyId'] == _selectedProxyId);
    if (proxy.isEmpty) return '';
    return (proxy.first['proxyConfig'] ?? '').toString();
  }

  String get _selectedProxyLabel {
    if (!_useProxy) return '直连';
    final proxy = _proxies.where((item) => item['proxyId'] == _selectedProxyId);
    if (proxy.isEmpty)
      return _selectedProxyId.isEmpty ? '直连' : _selectedProxyId;
    final name = (proxy.first['proxyName'] ?? '').toString().trim();
    return name.isNotEmpty ? name : _selectedProxyId;
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
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

  static bool _sameStringSet(Set<String> left, Set<String> right) {
    return left.length == right.length && left.containsAll(right);
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
      if (history != null) {
        _appendHistory({...history, 'ok': true, 'message': ''});
      }
      await _refresh();
    } catch (error) {
      if (history != null) {
        _appendHistory({...history, 'ok': false, 'message': '$error'});
      }
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _lookupExtension() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    if (_useProxy && _selectedProxyConfig.isEmpty) {
      showPrismNotice(context, '请先选择下载代理');
      return;
    }
    final proxyLabel = _useProxy ? '代理：$_selectedProxyLabel' : '直连查询';
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
        final value = Map<String, dynamic>.from(result as Map);
        setState(() {
          _lookup = value;
          _lookupMethodLabel = proxyLabel;
        });
        _appendHistory({
          'action': 'lookup',
          'query': query,
          'extensionId': (value['extensionId'] ?? '').toString(),
          'name': (value['name'] ?? '').toString(),
          'version': (value['version'] ?? '').toString(),
          'storeUrl': (value['storeUrl'] ?? '').toString(),
          'proxyLabel': proxyLabel,
          'ok': value['installable'] == true,
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
        'proxyLabel': proxyLabel,
        'ok': false,
        'message': '$error',
      });
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _install() async {
    final id = (_lookup?['extensionId'] ?? _query.text).toString().trim();
    if (id.isEmpty) return;
    if (_useProxy && _selectedProxyConfig.isEmpty) {
      showPrismNotice(context, '请先选择下载代理');
      return;
    }
    final proxyLabel = _selectedProxyLabel;
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
        if (mounted) {
          setState(() {
            _lookup = null;
            _lookupMethodLabel = '';
            _query.clear();
          });
        }
      },
      history: {
        'action': 'install',
        'query': id,
        'extensionId': (_lookup?['extensionId'] ?? id).toString(),
        'name': (_lookup?['name'] ?? '').toString(),
        'version': (_lookup?['version'] ?? '').toString(),
        'storeUrl': (_lookup?['storeUrl'] ?? '').toString(),
        'proxyLabel': proxyLabel,
      },
    );
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
        builder: (context, setDialog) {
          final colors = prism.Theme.of(context).colorScheme;
          return PrismDialog(
            title: const Text('插件操作历史'),
            content: SizedBox(
              width: 720,
              height: 520,
              child: records.isEmpty
                  ? const PrismEmptyState(
                      title: '暂无操作记录',
                      subtitle: '查询、安装或导入插件后，记录会显示在这里。',
                      glyph: AntGlyphs.history,
                    )
                  : ListView.builder(
                      padding: kPrismListPadding,
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        final success = record['ok'] == true;
                        final storeUrl = (record['storeUrl'] ?? '').toString();
                        final extId = (record['extensionId'] ?? '')
                            .toString()
                            .trim();
                        final proxyLabel = (record['proxyLabel'] ?? '')
                            .toString()
                            .trim();
                        final message = (record['message'] ?? '')
                            .toString()
                            .trim();
                        final queryText = (record['query'] ?? '')
                            .toString()
                            .trim();
                        final tone = PrismToneColors.of(
                          context,
                          success ? PrismTone.success : PrismTone.danger,
                        );
                        return PrismCard(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: PrismGlyph(
                                  success
                                      ? AntGlyphs.checkCircle
                                      : AntGlyphs.error,
                                  size: 18,
                                  color: tone.fg,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 10,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        PrismBadge(
                                          label: _historyActionLabel(
                                            (record['action'] ?? '').toString(),
                                          ),
                                          tone: PrismTone.info,
                                        ),
                                        PrismBadge(
                                          label: success ? '成功' : '失败',
                                          tone: success
                                              ? PrismTone.success
                                              : PrismTone.danger,
                                        ),
                                        if (proxyLabel.isNotEmpty)
                                          PrismBadge(
                                            label: proxyLabel,
                                            tone: PrismTone.neutral,
                                          ),
                                        Text(
                                          (record['name'] ?? '')
                                                  .toString()
                                                  .isNotEmpty
                                              ? '${record['name']}'
                                              : (extId.isNotEmpty
                                                    ? extId
                                                    : queryText),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: prism.AppTextStyle.subheadline
                                              .of(context, emphasized: true),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      [
                                        if (extId.isNotEmpty) 'ID: $extId',
                                        _formatExtensionTime(
                                          record['createdAt'],
                                        ),
                                      ].where((s) => s.isNotEmpty).join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: prism.AppTextStyle.caption1
                                          .of(context)
                                          .copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                    if (message.isNotEmpty ||
                                        queryText.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        message.isNotEmpty
                                            ? message
                                            : queryText,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: prism.AppTextStyle.caption1
                                            .of(context)
                                            .copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Wrap(
                                spacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  prism.TextButton(
                                    onPressed: () {
                                      _query.text = queryText;
                                      setState(
                                        () => _storePanelExpanded = true,
                                      );
                                      Navigator.pop(context);
                                    },
                                    child: const Text('使用'),
                                  ),
                                  if (storeUrl.isNotEmpty)
                                    prism.IconButton(
                                      tooltip: '打开商店页',
                                      onPressed: () =>
                                          _openExternalUrl(storeUrl),
                                      icon: const PrismGlyph(
                                        AntGlyphs.openInNew,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              prism.TextButton(
                onPressed: records.isEmpty
                    ? null
                    : () {
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
          );
        },
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

  Future<void> _openDownloadDirectoryInstallModal() async {
    try {
      await AppBridge.call('BrowserExtensionOpenManualDownloadDir');
    } catch (_) {}
    List<Map<String, dynamic>> files = [];
    try {
      final value = await AppBridge.call(
        'BrowserExtensionListManualDownloadFiles',
      );
      files = (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (error) {
      if (mounted) showPrismNotice(context, '读取下载目录失败：$error');
      return;
    }
    if (!mounted) return;

    var refreshing = false;
    String importingFile = '';

    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          Future<void> reloadFiles() async {
            setDialog(() => refreshing = true);
            try {
              final value = await AppBridge.call(
                'BrowserExtensionListManualDownloadFiles',
              );
              files = (value as List? ?? [])
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList();
            } catch (error) {
              if (dialogContext.mounted) {
                showPrismNotice(dialogContext, '$error');
              }
            } finally {
              if (dialogContext.mounted) setDialog(() => refreshing = false);
            }
          }

          return PrismDialog(
            title: const Text('下载目录安装'),
            content: SizedBox(
              width: 580,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PrismBanner(
                    tone: PrismTone.info,
                    message:
                        '已打开插件手动下载目录。将 .crx 或 .zip 插件包放入该目录后，点击「刷新列表」并选择导入即可。',
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: files.isEmpty
                        ? const PrismEmptyState(
                            title: '目录中还没有可导入的插件包',
                            subtitle: '支持 .crx 和 .zip 格式的浏览器扩展安装包。',
                            glyph: AntGlyphs.folder,
                          )
                        : ListView.separated(
                            padding: kPrismListPadding,
                            itemCount: files.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              final file = files[index];
                              final fileName = (file['fileName'] ?? '')
                                  .toString();
                              final sizeText = _formatExtensionFileSize(
                                file['sizeBytes'],
                              );
                              final updatedAt = (file['updatedAt'] ?? '')
                                  .toString();
                              final isImporting = importingFile == fileName;
                              return PrismCard(
                                child: PrismListTile(
                                  title: Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '$sizeText · $updatedAt',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: prism.FilledButton(
                                    onPressed: importingFile.isNotEmpty
                                        ? null
                                        : () async {
                                            setDialog(
                                              () => importingFile = fileName,
                                            );
                                            try {
                                              await AppBridge.call(
                                                'BrowserExtensionInstallManualDownloadFile',
                                                [fileName],
                                              );
                                              _appendHistory({
                                                'action': 'import',
                                                'query': fileName,
                                                'extensionId': '',
                                                'name': fileName,
                                                'version': '',
                                                'storeUrl': '',
                                                'proxyLabel': '下载目录导入',
                                                'ok': true,
                                                'message': '本地插件包导入成功',
                                              });
                                              await _refresh();
                                              if (dialogContext.mounted) {
                                                showPrismNotice(
                                                  dialogContext,
                                                  '已导入 $fileName',
                                                );
                                                Navigator.pop(dialogContext);
                                              }
                                            } catch (error) {
                                              if (dialogContext.mounted) {
                                                setDialog(
                                                  () => importingFile = '',
                                                );
                                                showPrismNotice(
                                                  dialogContext,
                                                  '$error',
                                                );
                                              }
                                            }
                                          },
                                    child: Text(isImporting ? '导入中…' : '导入'),
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
              prism.TextButton.icon(
                onPressed: () =>
                    AppBridge.call('BrowserExtensionOpenManualDownloadDir'),
                icon: const PrismGlyph(AntGlyphs.folder, size: 15),
                label: const Text('打开目录'),
              ),
              prism.OutlinedButton.icon(
                onPressed: refreshing ? null : reloadFiles,
                icon: const PrismGlyph(AntGlyphs.refresh, size: 15),
                label: Text(refreshing ? '刷新中…' : '刷新列表'),
              ),
              prism.TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showInstalledProfiles(Map<String, dynamic> extension) async {
    final extensionId = (extension['extensionId'] ?? '').toString();
    if (extensionId.isEmpty) return;

    Future<List<Map<String, dynamic>>> fetchUsingProfiles() async {
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
        final configured = value['configured'] == true;
        final usesExtension = configured
            ? extensionIds.contains(extensionId)
            : extension['enabled'] == true &&
                  extension['defaultInstall'] == true;
        if (usesExtension) {
          usingProfiles.add({
            ...profiles[index],
            '_manualConfigured': configured,
          });
        }
      }
      return usingProfiles;
    }

    try {
      var usingProfiles = await fetchUsingProfiles();
      if (!mounted) return;
      String busyProfileId = '';
      await showPrismDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) {
            final runningCount = usingProfiles
                .where((p) => p['running'] == true)
                .length;
            return PrismDialog(
              title: Text('使用实例 · ${extension['name'] ?? extensionId}'),
              content: SizedBox(
                width: 620,
                height: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PrismBadge(
                          label: '共 ${usingProfiles.length} 个实例',
                          tone: PrismTone.info,
                        ),
                        PrismBadge(
                          label: '其中 $runningCount 个运行中',
                          tone: runningCount > 0
                              ? PrismTone.success
                              : PrismTone.neutral,
                          dot: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '插件在实例启动时加载，修改配置后需要重启实例。',
                      style: prism.AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: prism.Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: usingProfiles.isEmpty
                          ? const PrismEmptyState(
                              title: '没有实例配置使用此插件',
                              glyph: AntGlyphs.browser,
                            )
                          : ListView.separated(
                              padding: kPrismListPadding,
                              itemCount: usingProfiles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final profile = usingProfiles[index];
                                final id = (profile['profileId'] ?? '')
                                    .toString();
                                final running = profile['running'] == true;
                                final isBusy = busyProfileId == id;
                                return PrismCard(
                                  child: PrismListTile(
                                    title: Wrap(
                                      spacing: 10,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          (profile['profileName'] ?? id)
                                              .toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        PrismBadge(
                                          label: running ? '运行中' : '已停止',
                                          tone: running
                                              ? PrismTone.success
                                              : PrismTone.neutral,
                                          dot: true,
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    leading: PrismGlyph(
                                      running ? AntGlyphs.play : AntGlyphs.stop,
                                      size: 18,
                                      color: PrismToneColors.of(
                                        context,
                                        running
                                            ? PrismTone.success
                                            : PrismTone.neutral,
                                      ).fg,
                                    ),
                                    trailing: prism.OutlinedButton(
                                      onPressed: busyProfileId.isNotEmpty
                                          ? null
                                          : () async {
                                              setDialog(
                                                () => busyProfileId = id,
                                              );
                                              try {
                                                await AppBridge.call(
                                                  running
                                                      ? 'BrowserInstanceStop'
                                                      : 'BrowserInstanceStart',
                                                  [id],
                                                );
                                                final refreshed =
                                                    await fetchUsingProfiles();
                                                if (context.mounted) {
                                                  setDialog(() {
                                                    usingProfiles = refreshed;
                                                    busyProfileId = '';
                                                  });
                                                }
                                              } catch (error) {
                                                if (context.mounted) {
                                                  setDialog(
                                                    () => busyProfileId = '',
                                                  );
                                                  showPrismNotice(
                                                    context,
                                                    '操作实例失败：$error',
                                                  );
                                                }
                                              }
                                            },
                                      child: Text(
                                        isBusy
                                            ? '处理中…'
                                            : (running ? '停止' : '启动'),
                                      ),
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
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        ),
      );
    } catch (error) {
      if (mounted) showPrismNotice(context, '读取实例插件状态失败：$error');
    }
  }

  Future<void> _openManualInstall() async {
    final target = (_lookup?['extensionId'] ?? _query.text).toString().trim();
    if (target.isEmpty) {
      showPrismNotice(context, '请先输入插件 ID 或商店链接');
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
      final downloadDir = (guide['downloadDir'] ?? '').toString();
      final fileName = (guide['fileName'] ?? '').toString();
      final recommendedSavePath =
          (downloadDir.isNotEmpty && fileName.isNotEmpty)
          ? '$downloadDir${Platform.pathSeparator}$fileName'
          : downloadDir;

      await showPrismDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) {
            final colors = prism.Theme.of(context).colorScheme;
            return PrismDialog(
              title: const Text('手动安装插件'),
              content: SizedBox(
                width: 600,
                height: 540,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PrismBanner(
                      tone: PrismTone.info,
                      message: '无法在线安装时，可在浏览器中打开下载地址，再把下载的文件放入推荐保存路径后导入。',
                    ),
                    const SizedBox(height: 14),
                    prism.Surface(
                      color: colors.surfaceContainerLow,
                      shape: prism.AppShape.lg,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: RepaintBoundary(
                          child: prism.SelectionArea(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '插件 ID：${guide['extensionId'] ?? ''}',
                                  style: prism.AppTextStyle.caption1.of(
                                    context,
                                    emphasized: true,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '下载地址：${guide['downloadUrl'] ?? ''}',
                                  style: prism.AppTextStyle.caption1
                                      .of(context)
                                      .copyWith(color: colors.onSurfaceVariant),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '推荐保存路径：$recommendedSavePath',
                                  style: prism.AppTextStyle.caption1
                                      .of(context)
                                      .copyWith(color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        prism.OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: (guide['downloadUrl'] ?? '').toString(),
                              ),
                            );
                            showPrismNotice(context, '下载地址已复制');
                          },
                          icon: const PrismGlyph(AntGlyphs.copy, size: 15),
                          label: const Text('复制下载地址'),
                        ),
                        prism.OutlinedButton.icon(
                          onPressed: downloadDir.isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: downloadDir),
                                  );
                                  showPrismNotice(context, '文件夹路径已复制');
                                },
                          icon: const PrismGlyph(AntGlyphs.copy, size: 15),
                          label: const Text('复制文件夹路径'),
                        ),
                        if ((guide['storeUrl'] ?? '').toString().isNotEmpty)
                          prism.OutlinedButton.icon(
                            onPressed: () => _openExternalUrl(
                              (guide['storeUrl'] ?? '').toString(),
                            ),
                            icon: const PrismGlyph(
                              AntGlyphs.openInNew,
                              size: 15,
                            ),
                            label: const Text('打开商店页'),
                          ),
                        prism.OutlinedButton.icon(
                          onPressed: () async {
                            await AppBridge.call(
                              'BrowserExtensionOpenManualDownloadDir',
                            );
                          },
                          icon: const PrismGlyph(AntGlyphs.folder, size: 15),
                          label: const Text('打开下载目录'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '可导入的 CRX / ZIP 文件',
                      style: prism.AppTextStyle.footnote.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: files.isEmpty
                          ? const Center(
                              child: SingleChildScrollView(
                                child: PrismEmptyState(
                                  title: '目录中还没有插件包',
                                  glyph: AntGlyphs.folder,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: kPrismListPadding,
                              itemCount: files.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final file = files[index];
                                final name = (file['fileName'] ?? '')
                                    .toString();
                                final sizeText = _formatExtensionFileSize(
                                  file['sizeBytes'],
                                );
                                return PrismCard(
                                  child: PrismListTile(
                                    title: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '$sizeText · ${file['updatedAt'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: prism.FilledButton(
                                      onPressed: () async {
                                        try {
                                          await AppBridge.call(
                                            'BrowserExtensionInstallManualDownloadFile',
                                            [name],
                                          );
                                          _appendHistory({
                                            'action': 'import',
                                            'query': name,
                                            'extensionId':
                                                (guide['extensionId'] ?? '')
                                                    .toString(),
                                            'name': name,
                                            'version': '',
                                            'storeUrl':
                                                (guide['storeUrl'] ?? '')
                                                    .toString(),
                                            'proxyLabel': '手动导入',
                                            'ok': true,
                                            'message': '本地插件包导入成功',
                                          });
                                          await _refresh();
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                          }
                                        } catch (error) {
                                          if (context.mounted) {
                                            showPrismNotice(
                                              context,
                                              error.toString(),
                                            );
                                          }
                                        }
                                      },
                                      child: const Text('导入'),
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
                        'proxyLabel': '本地目录',
                        'ok': true,
                        'message': '本地插件目录导入成功',
                      });
                      await _refresh();
                      if (context.mounted) {
                        showPrismNotice(context, '本地插件目录导入成功');
                      }
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
                        showPrismNotice(context, error.toString());
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
            );
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, error.toString());
      }
    }
  }

  Future<void> _configureProfiles(Map<String, dynamic> extension) async {
    final extensionId = (extension['extensionId'] ?? '').toString();
    if (extensionId.isEmpty) return;
    setState(() => _busy = 'profiles:$extensionId');
    try {
      final results = await Future.wait([
        AppBridge.call('BrowserProfileList'),
        AppBridge.call('ListGroups'),
      ]);
      final profiles = (results[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final groups = (results[1] as List? ?? [])
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
      final defaultExtensionIds = <String>{
        for (final item in _items)
          if (item['enabled'] == true && item['defaultInstall'] == true)
            '${item['extensionId']}',
      };
      final initial = <String, Map<String, dynamic>>{};
      final selected = <String>{};
      var onlyInstalled = false;
      var sortOrder = 'createdAtDesc';
      for (var i = 0; i < profiles.length; i++) {
        final profileId = (profiles[i]['profileId'] ?? '').toString();
        final settings = Map<String, dynamic>.from(settingsResult[i] as Map);
        initial[profileId] = settings;
        final inherited = settings['configured'] == true
            ? (settings['extensionIds'] as List? ?? [])
                  .map((id) => id.toString())
                  .contains(extensionId)
            : extension['enabled'] == true &&
                  extension['defaultInstall'] == true;
        if (inherited) selected.add(profileId);
      }
      final groupNames = {
        for (final group in groups)
          '${group['groupId']}': '${group['groupName'] ?? '分组'}',
      };
      final groupOrder = [for (final group in groups) '${group['groupId']}'];
      if (!mounted) return;
      final query = TextEditingController();
      final saved = await showPrismDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (dialogContext, setDialog) {
              final keyword = query.text.trim().toLowerCase();
              final buckets = <String, List<Map<String, dynamic>>>{};
              for (final profile in profiles) {
                final groupId = '${profile['groupId'] ?? ''}'.trim();
                buckets
                    .putIfAbsent(
                      groupId.isEmpty ? '__ungrouped__' : groupId,
                      () => [],
                    )
                    .add(profile);
              }
              final orderedIds = [
                ...groupOrder.where(buckets.containsKey),
                if (buckets.containsKey('__ungrouped__')) '__ungrouped__',
                ...buckets.keys.where(
                  (id) => id != '__ungrouped__' && !groupOrder.contains(id),
                ),
              ];

              int compareProfiles(
                Map<String, dynamic> left,
                Map<String, dynamic> right,
              ) {
                final leftName =
                    '${left['profileName'] ?? left['profileId'] ?? ''}'
                        .toLowerCase();
                final rightName =
                    '${right['profileName'] ?? right['profileId'] ?? ''}'
                        .toLowerCase();
                if (sortOrder == 'profileNameAsc') {
                  return leftName.compareTo(rightName);
                }
                if (sortOrder == 'profileNameDesc') {
                  return rightName.compareTo(leftName);
                }
                final leftCreated = DateTime.tryParse(
                  '${left['createdAt'] ?? ''}',
                );
                final rightCreated = DateTime.tryParse(
                  '${right['createdAt'] ?? ''}',
                );
                final cmp = (leftCreated == null || rightCreated == null)
                    ? leftName.compareTo(rightName)
                    : leftCreated.compareTo(rightCreated);
                return sortOrder == 'createdAtAsc' ? cmp : -cmp;
              }

              final sections = <MapEntry<String, List<Map<String, dynamic>>>>[
                for (final id in orderedIds)
                  MapEntry(
                    id == '__ungrouped__' ? '' : id,
                    (buckets[id]!.where((profile) {
                      final searchable =
                          '${profile['profileName'] ?? ''} ${profile['profileId'] ?? ''}'
                              .toLowerCase();
                      return (keyword.isEmpty ||
                              searchable.contains(keyword)) &&
                          (!onlyInstalled ||
                              selected.contains(
                                '${profile['profileId'] ?? ''}',
                              ));
                    }).toList()..sort(compareProfiles)),
                  ),
              ].where((section) => section.value.isNotEmpty).toList();

              Widget profileTile(Map<String, dynamic> profile) {
                final id = '${profile['profileId'] ?? ''}';
                final running = profile['running'] == true;
                final configured = initial[id]?['configured'] == true;
                return PrismCheckboxTile(
                  value: selected.contains(id),
                  title: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        (profile['profileName'] ?? id).toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (running)
                        const PrismBadge(
                          label: '运行中',
                          tone: PrismTone.success,
                          dot: true,
                        ),
                      if (configured)
                        const PrismBadge(label: '手动设置', tone: PrismTone.info),
                    ],
                  ),
                  subtitle: Text(
                    id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (value) => setDialog(() {
                    if (value == true) {
                      selected.add(id);
                    } else {
                      selected.remove(id);
                    }
                  }),
                );
              }

              return PrismDialog(
                title: Text('选择安装实例 · ${extension['name'] ?? extensionId}'),
                content: SizedBox(
                  width: 620,
                  height: 520,
                  child: profiles.isEmpty
                      ? const PrismEmptyState(
                          title: '当前没有浏览器实例',
                          glyph: AntGlyphs.browser,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '勾选的实例会写入此插件并改为手动设置；未勾选的实例如果当前靠「默认安装」继承到该插件，保存后同样会改为手动设置并排除该插件。',
                              style: prism.AppTextStyle.caption1
                                  .of(dialogContext)
                                  .copyWith(
                                    color: prism.Theme.of(dialogContext)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: PrismSearchBar(
                                    controller: query,
                                    hintText: '搜索实例名称或 ID',
                                    onChanged: (_) => setDialog(() {}),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 175,
                                  child: PrismDropdownField<String>(
                                    value: sortOrder,
                                    decoration: const PrismInputDecoration(
                                      hintText: '排序方式',
                                      isDense: true,
                                    ),
                                    items: const [
                                      PrismDropdownItem(
                                        value: 'createdAtDesc',
                                        child: Text('创建时间：新到旧'),
                                      ),
                                      PrismDropdownItem(
                                        value: 'createdAtAsc',
                                        child: Text('创建时间：旧到新'),
                                      ),
                                      PrismDropdownItem(
                                        value: 'profileNameAsc',
                                        child: Text('名称：A 到 Z'),
                                      ),
                                      PrismDropdownItem(
                                        value: 'profileNameDesc',
                                        child: Text('名称：Z 到 A'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setDialog(() => sortOrder = value);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                prism.TextButton(
                                  onPressed: () => setDialog(
                                    () => onlyInstalled = !onlyInstalled,
                                  ),
                                  child: Text(onlyInstalled ? '显示全部' : '只看已选'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: sections.isEmpty
                                  ? PrismEmptyState(
                                      title: keyword.isNotEmpty
                                          ? '没有匹配的实例'
                                          : onlyInstalled
                                          ? '当前没有已勾选的实例'
                                          : '当前没有浏览器实例',
                                      glyph: AntGlyphs.search,
                                    )
                                  : ListView(
                                      padding: kPrismListPadding,
                                      children: [
                                        for (final section in sections)
                                          Builder(
                                            builder: (context) {
                                              final groupSelectedCount = section
                                                  .value
                                                  .where(
                                                    (p) => selected.contains(
                                                      '${p['profileId'] ?? ''}',
                                                    ),
                                                  )
                                                  .length;
                                              final allSelected =
                                                  groupSelectedCount ==
                                                  section.value.length;
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  PrismListTile(
                                                    dense: true,
                                                    title: Wrap(
                                                      spacing: 12,
                                                      runSpacing: 8,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          section.key.isEmpty
                                                              ? '未分组'
                                                              : (groupNames[section
                                                                        .key] ??
                                                                    '分组 ${section.key}'),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: prism
                                                              .AppTextStyle
                                                              .subheadline
                                                              .of(
                                                                context,
                                                                emphasized:
                                                                    true,
                                                              ),
                                                        ),
                                                        PrismBadge(
                                                          label:
                                                              '已选 $groupSelectedCount / ${section.value.length}',
                                                          tone:
                                                              groupSelectedCount >
                                                                  0
                                                              ? PrismTone
                                                                    .primary
                                                              : PrismTone
                                                                    .neutral,
                                                        ),
                                                      ],
                                                    ),
                                                    trailing: prism.TextButton(
                                                      onPressed: () {
                                                        setDialog(() {
                                                          for (final profile
                                                              in section
                                                                  .value) {
                                                            final id =
                                                                '${profile['profileId'] ?? ''}';
                                                            if (allSelected) {
                                                              selected.remove(
                                                                id,
                                                              );
                                                            } else {
                                                              selected.add(id);
                                                            }
                                                          }
                                                        });
                                                      },
                                                      child: Text(
                                                        allSelected
                                                            ? '取消整组'
                                                            : '整组勾选',
                                                      ),
                                                    ),
                                                  ),
                                                  for (final profile
                                                      in section.value)
                                                    profileTile(profile),
                                                  const SizedBox(height: 10),
                                                ],
                                              );
                                            },
                                          ),
                                      ],
                                    ),
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
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text('保存（已选 ${selected.length}）'),
                  ),
                ],
              );
            },
          );
        },
      );
      query.dispose();
      if (saved != true) return;
      var manualFlipCount = 0;
      for (final profile in profiles) {
        final profileId = (profile['profileId'] ?? '').toString();
        final settings = initial[profileId] ?? const <String, dynamic>{};
        final configured = settings['configured'] == true;
        final baseIds = configured
            ? (settings['extensionIds'] as List? ?? [])
                  .map((value) => value.toString())
                  .toSet()
            : Set<String>.of(defaultExtensionIds);
        final nextIds = Set<String>.of(baseIds);
        if (selected.contains(profileId)) {
          nextIds.add(extensionId);
        } else {
          nextIds.remove(extensionId);
        }
        if (!configured && _sameStringSet(baseIds, nextIds)) continue;
        if (configured &&
            _sameStringSet(
              (settings['extensionIds'] as List? ?? [])
                  .map((value) => value.toString())
                  .toSet(),
              nextIds,
            )) {
          continue;
        }
        if (!configured) manualFlipCount++;
        await AppBridge.call('BrowserProfileExtensionSave', [
          profileId,
          nextIds.toList(),
          true,
        ]);
      }
      if (mounted) {
        showPrismNotice(
          context,
          manualFlipCount > 0
              ? '实例插件设置已保存；其中 $manualFlipCount 个实例改为手动设置，不再继承默认安装'
              : '实例插件设置已保存',
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  String _formatSourceLabel(Map<String, dynamic> item) {
    final sourceUrl = (item['sourceUrl'] ?? '').toString().toLowerCase();
    final packagePath = (item['packagePath'] ?? '').toString().trim();
    if (sourceUrl.contains('chromewebstore') ||
        sourceUrl.contains('chrome.google.com')) {
      return 'Chrome 商店';
    }
    if (packagePath.isNotEmpty) return '本地导入';
    return '本地/内置';
  }

  String _resolveStoreUrl(Map<String, dynamic> item) {
    final sourceUrl = (item['sourceUrl'] ?? '').toString().trim();
    if (sourceUrl.startsWith('https://')) return sourceUrl;
    final id = (item['extensionId'] ?? '').toString().trim();
    if (RegExp(r'^[a-p]{32}$', caseSensitive: false).hasMatch(id)) {
      return 'https://chromewebstore.google.com/detail/${id.toLowerCase()}';
    }
    return '';
  }

  bool _matchesExtensionFilter(Map<String, dynamic> item) {
    final enabled = item['enabled'] == true;
    final defaultInstall = item['defaultInstall'] == true;
    switch (_statusFilter) {
      case 'enabled':
        if (!enabled) return false;
        break;
      case 'disabled':
        if (enabled) return false;
        break;
      case 'default':
        if (!defaultInstall) return false;
        break;
    }
    final query = _filterQuery.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    final id = (item['extensionId'] ?? '').toString().toLowerCase();
    final name = (item['name'] ?? '').toString().toLowerCase();
    final description = (item['description'] ?? '').toString().toLowerCase();
    final version = (item['version'] ?? '').toString().toLowerCase();
    final sourceLabel = _formatSourceLabel(item).toLowerCase();
    return id.contains(query) ||
        name.contains(query) ||
        description.contains(query) ||
        version.contains(query) ||
        sourceLabel.contains(query);
  }

  void _handleImportMenuSelection(String mode) {
    if (mode == 'manual') {
      _openManualInstall();
    } else if (mode == 'download-dir') {
      _openDownloadDirectoryInstallModal();
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
          'proxyLabel': '本地导入',
        },
      );
    }
  }

  Widget _buildOverviewStrip(BuildContext context) {
    final totalCount = _items.length;
    final enabledCount = _items.where((item) => item['enabled'] == true).length;
    final disabledCount = totalCount - enabledCount;
    final defaultInstallCount = _items
        .where((item) => item['defaultInstall'] == true)
        .length;
    final storeCount = _items
        .where((item) => _formatSourceLabel(item) == 'Chrome 商店')
        .length;
    final localCount = totalCount - storeCount;
    final mv3Count = _items
        .where(
          (item) =>
              _parseManifestJson(item['manifestJson']).manifestVersion == 3,
        )
        .length;

    final tiles = [
      PrismMetricTile(
        label: '插件总数',
        value: '$totalCount',
        subtitle: '商店 $storeCount · 本地 $localCount',
        glyph: AntGlyphs.extension,
        tone: PrismTone.primary,
        onPressed: () => setState(() => _statusFilter = 'all'),
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '已启用',
        value: '$enabledCount',
        subtitle: _statusFilter == 'enabled'
            ? '已筛选 · 点击恢复全部'
            : (disabledCount > 0 ? '已停用 $disabledCount 个 · 点击筛选' : '全部插件已启用'),
        glyph: AntGlyphs.checkCircle,
        tone: PrismTone.success,
        onPressed: () => setState(
          () => _statusFilter = _statusFilter == 'enabled' ? 'all' : 'enabled',
        ),
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '默认安装',
        value: '$defaultInstallCount',
        subtitle: _statusFilter == 'default'
            ? '已筛选 · 点击恢复全部'
            : '新实例默认加载 · 点击筛选',
        glyph: AntGlyphs.pin,
        tone: PrismTone.info,
        onPressed: () => setState(
          () => _statusFilter = _statusFilter == 'default' ? 'all' : 'default',
        ),
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: _useProxy ? '代理下载' : 'MV3 插件',
        value: '$mv3Count',
        subtitle:
            '${_useProxy ? '代理：$_selectedProxyLabel' : '直连下载'} · 历史 ${_history.length}',
        glyph: _useProxy ? AntGlyphs.shield : AntGlyphs.history,
        tone: _useProxy ? PrismTone.warning : PrismTone.neutral,
        onPressed: _showHistory,
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
                if (i > 0) const SizedBox(width: 16),
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
                const SizedBox(width: 16),
                Expanded(child: tiles[1]),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: tiles[2]),
                const SizedBox(width: 16),
                Expanded(child: tiles[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStoreInstallPanel(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        const prism.Divider(height: 1),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PrismTextField(
                controller: _query,
                onSubmitted: (_) {
                  if (_busy.isEmpty) _lookupExtension();
                },
                decoration: const PrismInputDecoration(
                  hintText: '粘贴插件 ID 或 Chrome 商店链接，按回车查询',
                ),
              ),
            ),
            const SizedBox(width: 12),
            PrismHoverMotion(
              enabled: _busy.isEmpty,
              child: prism.FilledButton(
                onPressed: _busy.isEmpty ? _lookupExtension : null,
                child: Text(_busy == 'lookup' ? '查询中…' : '查询'),
              ),
            ),
            const SizedBox(width: 10),
            prism.OutlinedButton.icon(
              onPressed: _openStoreSearch,
              icon: const PrismGlyph(AntGlyphs.openInNew, size: 15),
              label: const Text('网页查询'),
            ),
            const SizedBox(width: 12),
            prism.OutlinedButton.icon(
              onPressed: _busy.isEmpty ? _openManualInstall : null,
              icon: const PrismGlyph(AntGlyphs.download, size: 15),
              label: const Text('手动安装'),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                _proxies.any((proxy) => proxy['proxyId'] == _selectedProxyId)
                ? _selectedProxyId
                : null,
            decoration: const PrismInputDecoration(labelText: '下载代理'),
            items: [
              for (final proxy in _proxies)
                PrismDropdownItem(
                  value: proxy['proxyId']?.toString(),
                  child: Text(
                    (proxy['proxyName'] ?? proxy['proxyId'] ?? '').toString(),
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
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final installable = result['installable'] == true;
              final extId = (result['extensionId'] ?? '').toString();
              final alreadyInstalled =
                  extId.isNotEmpty &&
                  _items.any((item) => item['extensionId'] == extId);
              final desc = (result['description'] ?? '').toString().trim();
              final msg = (result['message'] ?? '').toString().trim();
              final storeUrl = (result['storeUrl'] ?? '').toString().trim();

              return PrismHoverGlow(
                radius: prism.AppCorner.lg,
                child: prism.Surface(
                  color: colors.surfaceContainerLow,
                  shape: prism.AppShape.lg,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${result['name'] ?? extId}'
                              '${(result['version'] ?? '').toString().isNotEmpty ? '  v${result['version']}' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: prism.AppTextStyle.subheadline.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                            PrismBadge(
                              label: installable ? '可安装' : '查询失败',
                              tone: installable
                                  ? PrismTone.success
                                  : PrismTone.danger,
                            ),
                            if (alreadyInstalled)
                              const PrismBadge(
                                label: '已安装',
                                tone: PrismTone.info,
                              ),
                            if (_lookupMethodLabel.isNotEmpty)
                              PrismBadge(
                                label: '查询方式：$_lookupMethodLabel',
                                tone: PrismTone.neutral,
                              ),
                          ],
                        ),
                        if (extId.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          prism.SelectableText(
                            '插件 ID：$extId',
                            style: prism.AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '插件简介：$desc',
                            style: prism.AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                        if (msg.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          PrismBanner(
                            tone: installable ? PrismTone.info : PrismTone.danger,
                            message: msg,
                          ),
                        ],
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              if (!installable)
                                prism.OutlinedButton.icon(
                                  onPressed: _busy.isEmpty
                                      ? _lookupExtension
                                      : null,
                                  icon: const PrismGlyph(
                                    AntGlyphs.refresh,
                                    size: 15,
                                  ),
                                  label: const Text('重新查询'),
                                ),
                              if (storeUrl.isNotEmpty)
                                prism.OutlinedButton.icon(
                                  onPressed: () => _openExternalUrl(storeUrl),
                                  icon: const PrismGlyph(
                                    AntGlyphs.openInNew,
                                    size: 15,
                                  ),
                                  label: const Text('打开商店页'),
                                ),
                              PrismHoverMotion(
                                enabled:
                                    _busy.isEmpty &&
                                    installable &&
                                    !alreadyInstalled,
                                child: prism.FilledButton(
                                  onPressed:
                                      _busy.isEmpty &&
                                          installable &&
                                          !alreadyInstalled
                                      ? _install
                                      : null,
                                  child: Text(
                                    alreadyInstalled
                                        ? '已安装'
                                        : (_busy == 'install' ? '安装中…' : '安装'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final storeExpanded = _storePanelExpanded || _lookup != null;
    final filterControl = SizedBox(
      width: 248,
      child: prism.SegmentedControl<String>(
        value: _statusFilter,
        onChanged: (value) => setState(() => _statusFilter = value),
        segments: const [
          ('all', '全部'),
          ('enabled', '已启用'),
          ('default', '默认'),
          ('disabled', '已停用'),
        ],
      ),
    );
    final actionWidgets = <Widget>[
      prism.TonalButtonGroup(
        size: prism.TonalButtonSize.section,
        children: [
          prism.IconButton(
            tooltip: '历史记录',
            onPressed: _showHistory,
            icon: const PrismGlyph(AntGlyphs.history, size: 17),
          ),
          prism.IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const PrismGlyph(AntGlyphs.refresh, size: 17),
          ),
        ],
      ),
      PrismTonalButton.icon(
        onPressed: _busy.isEmpty ? _openDownloadDirectoryInstallModal : null,
        icon: const PrismGlyph(AntGlyphs.folderSpecial, size: 15),
        child: const Text('下载目录'),
      ),
      PrismHoverMotion(
        enabled: _busy.isEmpty,
        child: prism.FilledButton.icon(
          onPressed: _busy.isEmpty
              ? () => setState(() => _storePanelExpanded = !storeExpanded)
              : null,
          icon: PrismGlyph(
            storeExpanded ? AntGlyphs.chevronUp : AntGlyphs.download,
            size: 15,
          ),
          label: Text(storeExpanded ? '收起商店' : '商店安装'),
        ),
      ),
      PrismPopupMenuButton<String>(
        tooltip: '导入插件',
        enabled: _busy.isEmpty,
        icon: const PrismGlyph(AntGlyphs.add, size: 18),
        onSelected: _handleImportMenuSelection,
        itemBuilder: (_) => const [
          PrismMenuItem(value: 'file', child: Text('从本地插件包导入')),
          PrismMenuItem(value: 'directory', child: Text('从本地文件夹导入')),
          PrismMenuItem(value: 'manual', child: Text('手动下载与导入')),
          PrismMenuItem(value: 'download-dir', child: Text('下载目录安装')),
        ],
      ),
    ];

    return PrismHoverCard(
      staggerIndex: 4,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 940;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: PrismSearchBar(
                        controller: _filterQuery,
                        hintText: '搜索已安装插件名称、ID 或说明…',
                        height: 36,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    filterControl,
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actionWidgets,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: PrismSearchBar(
                          controller: _filterQuery,
                          hintText: '搜索已安装插件名称、ID 或说明…',
                          height: 36,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      filterControl,
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actionWidgets,
                  ),
                ],
              );
            },
          ),
          PrismCollapsible(
            expanded: storeExpanded,
            child: _buildStoreInstallPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildExtensionsListCard(
    BuildContext context,
    List<Map<String, dynamic>> filteredItems,
  ) {
    final queryText = _filterQuery.text.trim();
    final hasFilters = _statusFilter != 'all' || queryText.isNotEmpty;
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
            info: const prism.Info(label: '已安装插件', glyph: AntGlyphs.extension),
            actions: [
              if (hasFilters)
                prism.TextButton(
                  onPressed: () {
                    _filterQuery.clear();
                    setState(() => _statusFilter = 'all');
                  },
                  child: const Text('重置筛选'),
                ),
              PrismBadge(
                label: '${filteredItems.length} 个',
                tone: filteredItems.isEmpty
                    ? PrismTone.neutral
                    : PrismTone.primary,
              ),
            ],
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
          ),
          const prism.Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : prism.PageTransitionSwitcher(
                    duration: PrismMotionSpec.current.pageDuration,
                    transitionBuilder: PrismSlideThroughTransition.builder,
                    child: KeyedSubtree(
                      key: ValueKey(
                        '$_statusFilter-$queryText-${filteredItems.isEmpty}',
                      ),
                      child: filteredItems.isEmpty
                          ? (_items.isEmpty
                                ? PrismEmptyState(
                                    title: '还没有安装插件',
                                    subtitle:
                                        '点击上方「商店安装」查询 Chrome 插件，或从本地插件包导入。',
                                    glyph: AntGlyphs.extension,
                                    action: Wrap(
                                      spacing: 12,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        PrismHoverMotion(
                                          enabled: _busy.isEmpty,
                                          child: prism.FilledButton.icon(
                                            onPressed: _busy.isEmpty
                                                ? () => setState(
                                                    () => _storePanelExpanded =
                                                        true,
                                                  )
                                                : null,
                                            icon: const PrismGlyph(
                                              AntGlyphs.download,
                                              size: 15,
                                            ),
                                            label: const Text('商店安装'),
                                          ),
                                        ),
                                        prism.OutlinedButton.icon(
                                          onPressed: _busy.isEmpty
                                              ? () =>
                                                    _handleImportMenuSelection(
                                                      'file',
                                                    )
                                              : null,
                                          icon: const PrismGlyph(
                                            AntGlyphs.folder,
                                            size: 15,
                                          ),
                                          label: const Text('导入本地插件'),
                                        ),
                                      ],
                                    ),
                                  )
                                : PrismEmptyState(
                                    title: '没有匹配的插件',
                                    subtitle: '尝试调整搜索关键词或切换筛选状态。',
                                    glyph: AntGlyphs.search,
                                    action: prism.OutlinedButton(
                                      onPressed: () {
                                        _filterQuery.clear();
                                        setState(() => _statusFilter = 'all');
                                      },
                                      child: const Text('重置筛选'),
                                    ),
                                  ))
                          : ListView.separated(
                              padding: kPrismListPadding,
                              itemCount: filteredItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) =>
                                  _extensionCard(filteredItems[index]),
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _items.where(_matchesExtensionFilter).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewStrip(context),
          const SizedBox(height: 16),
          _buildToolbar(context),
          if (_error != null) ...[
            const SizedBox(height: 16),
            PrismBanner(
              tone: PrismTone.danger,
              message: _error!,
              trailing: prism.TextButton(
                onPressed: _refresh,
                child: const Text('重试'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(child: _buildExtensionsListCard(context, filteredItems)),
        ],
      ),
    );
  }

  Widget _extensionCard(Map<String, dynamic> item) {
    final colors = prism.Theme.of(context).colorScheme;
    final id = (item['extensionId'] ?? '').toString();
    final icon = (item['iconDataUrl'] ?? '').toString();
    final enabled = item['enabled'] == true;
    final defaultInstall = item['defaultInstall'] == true;
    final busy = _busy == id;
    final manifest = _parseManifestJson(item['manifestJson']);
    final sourceLabel = _formatSourceLabel(item);
    final storeUrl = _resolveStoreUrl(item);
    final installedAt = _formatExtensionTime(item['installedAt']);
    final updatedAt = _formatExtensionTime(item['updatedAt']);
    final description = (item['description'] ?? '').toString().trim();

    return PrismCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon.startsWith('data:image') && icon.contains(','))
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ClipOval(
                    child: Image.memory(
                      base64Decode(icon.substring(icon.indexOf(',') + 1)),
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const PrismGlyph(AntGlyphs.extension, size: 20),
                    ),
                  ),
                )
              else
                prism.Surface(
                  color: colors.surfaceContainerHigh,
                  shape: prism.AppShape.full,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: PrismGlyph(AntGlyphs.extension, size: 20),
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          (item['name'] ?? id).toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: prism.AppTextStyle.subheadline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        PrismBadge(
                          label: enabled ? '已启用' : '已停用',
                          tone: enabled ? PrismTone.success : PrismTone.neutral,
                          dot: true,
                        ),
                        if (manifest.manifestVersion != null)
                          PrismBadge(
                            label: 'MV${manifest.manifestVersion}',
                            tone: manifest.manifestVersion == 3
                                ? PrismTone.primary
                                : PrismTone.warning,
                          ),
                        PrismBadge(label: sourceLabel, tone: PrismTone.neutral),
                        if (defaultInstall)
                          const PrismBadge(
                            label: '默认安装',
                            tone: PrismTone.info,
                            glyph: AntGlyphs.pin,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'v${item['version'] ?? '-'} · $id',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.caption1
                            .of(context)
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                    if (manifest.permissions.isNotEmpty ||
                        manifest.hostPermissionCount > 0) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          if (manifest.hostPermissionCount > 0)
                            PrismBadge(
                              label: '站点权限 ${manifest.hostPermissionCount}',
                              tone: PrismTone.warning,
                            ),
                          for (final perm in manifest.permissions.take(4))
                            PrismBadge(label: perm, tone: PrismTone.neutral),
                          if (manifest.permissions.length > 4)
                            PrismBadge(
                              label: '+${manifest.permissions.length - 4}',
                              tone: PrismTone.neutral,
                            ),
                        ],
                      ),
                    ],
                    if (installedAt.isNotEmpty || updatedAt.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (installedAt.isNotEmpty) '安装于 $installedAt',
                          if (updatedAt.isNotEmpty) '更新于 $updatedAt',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.caption2
                            .of(context)
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (storeUrl.isNotEmpty)
                    prism.OutlinedButton.icon(
                      onPressed: () => _openExternalUrl(storeUrl),
                      icon: const PrismGlyph(AntGlyphs.openInNew, size: 14),
                      label: const Text('商店'),
                    ),
                  prism.TonalButtonGroup(
                    size: prism.TonalButtonSize.section,
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
                                  'storeUrl': storeUrl,
                                  'proxyLabel': _selectedProxyLabel,
                                },
                              ),
                        icon: const PrismGlyph(AntGlyphs.download, size: 18),
                      ),
                      prism.IconButton(
                        tooltip: defaultInstall ? '取消默认安装' : '设为默认安装',
                        onPressed: busy
                            ? null
                            : () => _run(id, () async {
                                await AppBridge.call(
                                  'BrowserExtensionSetDefaultInstall',
                                  [id, !defaultInstall],
                                );
                              }),
                        icon: PrismGlyph(
                          AntGlyphs.pin,
                          size: 18,
                          color: defaultInstall ? colors.primary : null,
                        ),
                      ),
                      prism.IconButton(
                        tooltip: '指定安装实例',
                        onPressed: busy ? null : () => _configureProfiles(item),
                        icon: const PrismGlyph(AntGlyphs.tune, size: 18),
                      ),
                      prism.IconButton(
                        tooltip: '查看使用此插件的实例',
                        onPressed: busy
                            ? null
                            : () => _showInstalledProfiles(item),
                        icon: const PrismGlyph(AntGlyphs.browser, size: 18),
                      ),
                    ],
                  ),
                  prism.Switch(
                    value: enabled,
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
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  prism.FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              _run(id, () async {
                                await AppBridge.call('BrowserExtensionDelete', [
                                  id,
                                ]);
                              });
                            }
                          },
                    icon: PrismGlyph(
                      AntGlyphs.delete,
                      size: 18,
                      color: busy ? null : colors.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
