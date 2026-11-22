import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'wails_bridge.dart';

class CoresPage extends StatefulWidget {
  const CoresPage({super.key});

  @override
  State<CoresPage> createState() => _CoresPageState();
}

class _CoresPageState extends State<CoresPage> {
  List<Map<String, dynamic>> _cores = [];
  Map<String, dynamic> _settings = {};
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _downloadProgress;
  late final void Function() _removeDownloadListener;
  late final void Function() _removeImportListener;

  @override
  void initState() {
    super.initState();
    _removeDownloadListener = WailsBridge.onEvent('download:progress', (
      payload,
    ) {
      if (!mounted || payload is! Map) return;
      final progress = Map<String, dynamic>.from(payload);
      setState(() => _downloadProgress = progress);
      if (progress['phase'] == 'done' || progress['phase'] == 'error') {
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          setState(() => _downloadProgress = null);
          _load();
        });
      }
    });
    _removeImportListener = WailsBridge.onEvent('core-import:progress', (
      payload,
    ) {
      if (!mounted || payload is! Map) return;
      setState(() => _downloadProgress = Map<String, dynamic>.from(payload));
    });
    _load();
  }

  @override
  void dispose() {
    _removeDownloadListener();
    _removeImportListener();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        WailsBridge.call('BrowserCoreList'),
        WailsBridge.call('BrowserCoreExtendedInfo'),
        WailsBridge.call('GetBrowserSettings'),
      ]);
      final cores = (values[0] is List ? values[0] as List : const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final extended = <String, Map<String, dynamic>>{};
      for (final item in (values[1] is List ? values[1] as List : const [])) {
        if (item is Map)
          extended['${item['coreId'] ?? ''}'] = Map<String, dynamic>.from(item);
      }
      final checks = await Future.wait(
        cores.map((core) async {
          try {
            return await WailsBridge.call('BrowserCoreValidate', [
              '${core['corePath'] ?? ''}',
            ]);
          } catch (error) {
            return {'valid': false, 'message': '$error'};
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        if (values[2] is Map) {
          _settings = Map<String, dynamic>.from(values[2] as Map);
        }
        _cores = [
          for (var index = 0; index < cores.length; index++)
            {
              ...cores[index],
              ...extended['${cores[index]['coreId'] ?? ''}'] ??
                  const <String, dynamic>{},
              'validation': checks[index] is Map
                  ? Map<String, dynamic>.from(checks[index] as Map)
                  : const <String, dynamic>{},
            },
        ];
      });
    } catch (error) {
      if (mounted) _message('读取内核列表失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      await WailsBridge.call('BrowserCoreScan');
      await _load();
      _message('内核扫描完成');
    } catch (error) {
      _message('扫描失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSettings() async {
    if (_settings.isEmpty) return;
    final root = TextEditingController(
      text: '${_settings['userDataRoot'] ?? ''}',
    );
    final fingerprint = TextEditingController(
      text: (_settings['defaultFingerprintArgs'] as List? ?? []).join('\n'),
    );
    final launchArgs = TextEditingController(
      text: (_settings['defaultLaunchArgs'] as List? ?? []).join('\n'),
    );
    final startUrls = TextEditingController(
      text: (_settings['defaultStartUrls'] as List? ?? []).join('\n'),
    );
    final readyTimeout = TextEditingController(
      text: '${_settings['startReadyTimeoutMs'] ?? 3000}',
    );
    final stableWindow = TextEditingController(
      text: '${_settings['startStableWindowMs'] ?? 1200}',
    );
    final concurrent = TextEditingController(
      text: '${_settings['maxConcurrentInstances'] ?? 0}',
    );
    var lightStart = _settings['lightStartEnabled'] != false;
    var restoreSession = _settings['restoreLastSession'] == true;
    var connectorType = (_settings['defaultConnectorType'] ?? 'xray')
        .toString();
    final result = await showPrismDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('浏览器全局设置'),
          content: SizedBox(
            width: 560,
            height: 580,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  PrismTextField(
                    controller: root,
                    decoration: const PrismInputDecoration(
                      labelText: '用户数据根目录',
                    ),
                  ),
                  PrismTextField(
                    controller: fingerprint,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const PrismInputDecoration(
                      labelText: '默认指纹参数（每行一个）',
                    ),
                  ),
                  PrismTextField(
                    controller: launchArgs,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const PrismInputDecoration(
                      labelText: '默认启动参数（每行一个）',
                    ),
                  ),
                  PrismTextField(
                    controller: startUrls,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const PrismInputDecoration(
                      labelText: '默认启动页面（每行一个 URL）',
                    ),
                  ),
                  PrismDropdownField<String>(
                    initialValue: connectorType == 'mihomo' ? 'mihomo' : 'xray',
                    decoration: const PrismInputDecoration(
                      labelText: '默认代理连接内核',
                    ),
                    items: const [
                      PrismDropdownItem(
                        value: 'xray',
                        child: Text('Xray / Sing-box'),
                      ),
                      PrismDropdownItem(
                        value: 'mihomo',
                        child: Text('Mihomo / Clash'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialog(() => connectorType = value ?? 'xray'),
                  ),
                  PrismSwitchTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('轻启动模式'),
                    subtitle: const Text('先启动空白页，准备好后再打开默认页面'),
                    value: lightStart,
                    onChanged: (value) => setDialog(() => lightStart = value),
                  ),
                  PrismSwitchTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('恢复上次打开的标签页'),
                    value: restoreSession,
                    onChanged: (value) =>
                        setDialog(() => restoreSession = value),
                  ),
                  PrismTextField(
                    controller: readyTimeout,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '启动就绪超时（毫秒）',
                    ),
                  ),
                  PrismTextField(
                    controller: stableWindow,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '启动稳定窗口（毫秒）',
                    ),
                  ),
                  PrismTextField(
                    controller: concurrent,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '同时运行实例上限（0 表示不限制）',
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
              onPressed: () => Navigator.pop(context, {
                'userDataRoot': root.text.trim(),
                'defaultFingerprintArgs': fingerprint.text
                    .split('\n')
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList(),
                'defaultLaunchArgs': launchArgs.text
                    .split('\n')
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList(),
                'defaultStartUrls': startUrls.text
                    .split('\n')
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList(),
                'defaultConnectorType': connectorType,
                'lightStartEnabled': lightStart,
                'restoreLastSession': restoreSession,
                'startReadyTimeoutMs': int.tryParse(readyTimeout.text) ?? 3000,
                'startStableWindowMs': int.tryParse(stableWindow.text) ?? 1200,
                'maxConcurrentInstances': int.tryParse(concurrent.text) ?? 0,
              }),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    root.dispose();
    fingerprint.dispose();
    launchArgs.dispose();
    startUrls.dispose();
    readyTimeout.dispose();
    stableWindow.dispose();
    concurrent.dispose();
    if (result == null) return;
    try {
      await WailsBridge.call('SaveBrowserSettings', [result]);
      await _load();
      _message('浏览器全局设置已保存');
    } catch (error) {
      _message('保存失败：$error');
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await WailsBridge.call('BrowserCoreImportLocal');
      await _load();
      if (result != null) _message('内核已导入');
    } catch (error) {
      _message('导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? core]) async {
    final name = TextEditingController(text: '${core?['coreName'] ?? ''}');
    final path = TextEditingController(text: '${core?['corePath'] ?? ''}');
    final result = await showPrismDialog<Map<String, String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text(core == null ? '添加浏览器内核' : '编辑浏览器内核'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismTextField(
                controller: name,
                decoration: const PrismInputDecoration(labelText: '内核名称'),
              ),
              const SizedBox(height: 10),
              PrismTextField(
                controller: path,
                decoration: const PrismInputDecoration(labelText: '可执行文件路径'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: prism.TextButton.icon(
                  onPressed: () async {
                    try {
                      final validation = await WailsBridge.call(
                        'BrowserCoreValidate',
                        [path.text.trim()],
                      );
                      if (context.mounted && validation is Map) {
                        showPrismNotice(
                          context,
                          ('${validation['message'] ?? (validation['valid'] == true ? '路径有效' : '路径无效')}')
                              .toString(),
                        );
                      }
                    } catch (error) {
                      if (context.mounted)
                        showPrismNotice(context, ('$error').toString());
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 17),
                  label: const Text('验证路径'),
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
            onPressed: () => Navigator.pop(context, {
              'name': name.text.trim(),
              'path': path.text.trim(),
            }),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    name.dispose();
    path.dispose();
    if (result == null) return;
    if (result['name']!.isEmpty || result['path']!.isEmpty) {
      _message('请填写内核名称和路径');
      return;
    }
    setState(() => _busy = true);
    try {
      await WailsBridge.call('BrowserCoreSave', [
        {
          'coreId': '${core?['coreId'] ?? ''}',
          'coreName': result['name'],
          'corePath': result['path'],
          'isDefault': core?['isDefault'] == true,
        },
      ]);
      await _load();
      _message('内核已保存');
    } catch (error) {
      _message('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDefault(String id) async {
    setState(() => _busy = true);
    try {
      await WailsBridge.call('BrowserCoreSetDefault', [id]);
      await _load();
      _message('默认内核已更新');
    } catch (error) {
      _message('设置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> core) async {
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除内核？'),
        content: Text('确定删除“${core['coreName'] ?? ''}”吗？'),
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
    setState(() => _busy = true);
    try {
      await WailsBridge.call('BrowserCoreDelete', ['${core['coreId'] ?? ''}']);
      await _load();
      _message('内核已删除');
    } catch (error) {
      _message('删除失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redownload(Map<String, dynamic> core) async {
    final url = TextEditingController();
    final proxy = TextEditingController();
    final values = await showPrismDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text('重新下载 ${core['coreName'] ?? '内核'}'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismTextField(
                controller: url,
                decoration: const PrismInputDecoration(labelText: '下载地址'),
              ),
              PrismTextField(
                controller: proxy,
                decoration: const PrismInputDecoration(labelText: '代理配置（可选）'),
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
            onPressed: () =>
                Navigator.pop(context, [url.text.trim(), proxy.text.trim()]),
            child: const Text('开始重新下载'),
          ),
        ],
      ),
    );
    url.dispose();
    proxy.dispose();
    if (values == null) return;
    if (values[0].isEmpty) {
      _message('请填写下载地址');
      return;
    }
    setState(() {
      _busy = true;
      _downloadProgress = {
        'phase': 'starting',
        'progress': 0,
        'message': '准备重新下载',
      };
    });
    try {
      await WailsBridge.call('BrowserCoreRedownload', [
        core['coreId'],
        ...values,
      ]);
    } catch (error) {
      _message('重新下载失败：$error');
      if (mounted) setState(() => _downloadProgress = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final proxy = TextEditingController();
    final values = await showPrismDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('下载浏览器内核'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismTextField(
                controller: name,
                decoration: const PrismInputDecoration(labelText: '内核名称'),
              ),
              PrismTextField(
                controller: url,
                decoration: const PrismInputDecoration(labelText: '下载地址'),
              ),
              PrismTextField(
                controller: proxy,
                decoration: const PrismInputDecoration(labelText: '代理配置（可选）'),
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
            onPressed: () => Navigator.pop(context, [
              name.text.trim(),
              url.text.trim(),
              proxy.text.trim(),
            ]),
            child: const Text('开始下载'),
          ),
        ],
      ),
    );
    name.dispose();
    url.dispose();
    proxy.dispose();
    if (values == null) return;
    if (values[0].isEmpty || values[1].isEmpty) {
      _message('请填写内核名称和下载地址');
      return;
    }
    setState(() {
      _busy = true;
      _downloadProgress = {
        'phase': 'starting',
        'progress': 0,
        'message': '正在启动下载',
      };
    });
    try {
      await WailsBridge.call('BrowserCoreDownload', values);
    } catch (error) {
      _message('下载失败：$error');
      if (mounted) setState(() => _downloadProgress = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (mounted) showPrismNotice(context, (value).toString());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('${_cores.length} 个内核')),
              prism.OutlinedButton.icon(
                onPressed: _busy ? null : _editSettings,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('全局设置'),
              ),
              const SizedBox(width: 8),
              prism.OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.manage_search, size: 18),
                label: const Text('扫描'),
              ),
              const SizedBox(width: 8),
              prism.OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('导入本地'),
              ),
              const SizedBox(width: 8),
              prism.OutlinedButton.icon(
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加路径'),
              ),
              const SizedBox(width: 8),
              prism.FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('下载内核'),
              ),
            ],
          ),
          if (_downloadProgress != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_downloadProgress!['message'] ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: prism.LinearProgressIndicator(
                    value: _progressValue(_downloadProgress!['progress']),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : _cores.isEmpty
                ? const Center(child: Text('暂未配置浏览器内核'))
                : ListView.separated(
                    itemCount: _cores.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final core = _cores[index];
                      final colors = prism.Theme.of(context).colorScheme;
                      final validation = core['validation'] is Map
                          ? Map<String, dynamic>.from(core['validation'] as Map)
                          : const <String, dynamic>{};
                      final valid = validation['valid'] == true;
                      return PrismCard(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: core['isDefault'] == true
                                ? colors.primary
                                : colors.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 17,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: colors.secondaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.memory,
                                  color: colors.onSecondaryContainer,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            '${core['coreName'] ?? '未命名内核'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (core['isDefault'] == true) ...[
                                          const SizedBox(width: 8),
                                          const _CoreTag(label: '默认'),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${core['corePath'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      valid
                                          ? '可用 · Chrome ${core['chromeVersion'] ?? '版本未知'}'
                                          : '${validation['message'] ?? '路径无效'}',
                                      style: TextStyle(
                                        color: valid
                                            ? colors.tertiary
                                            : colors.error,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (core['isDefault'] != true)
                                prism.TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _setDefault(
                                          '${core['coreId'] ?? ''}',
                                        ),
                                  child: const Text('设为默认'),
                                ),
                              prism.IconButton(
                                tooltip: '打开所在位置',
                                onPressed: () async {
                                  try {
                                    await WailsBridge.call('OpenCorePath', [
                                      '${core['corePath'] ?? ''}',
                                    ]);
                                  } catch (error) {
                                    _message('$error');
                                  }
                                },
                                icon: const Icon(
                                  Icons.folder_open_outlined,
                                  size: 19,
                                ),
                              ),
                              prism.IconButton(
                                tooltip: '重新下载',
                                onPressed: _busy
                                    ? null
                                    : () => _redownload(core),
                                icon: const Icon(
                                  Icons.download_outlined,
                                  size: 19,
                                ),
                              ),
                              prism.IconButton(
                                tooltip: '编辑',
                                onPressed: _busy ? null : () => _edit(core),
                                icon: const Icon(Icons.edit_outlined, size: 19),
                              ),
                              prism.IconButton(
                                tooltip: '删除',
                                onPressed: _busy ? null : () => _delete(core),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 19,
                                ),
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

  double? _progressValue(dynamic value) {
    final progress = double.tryParse('$value');
    return progress == null || progress <= 0
        ? null
        : (progress / 100).clamp(0, 1).toDouble();
  }
}

class _CoreTag extends StatelessWidget {
  const _CoreTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(color: colors.onSecondaryContainer, fontSize: 11),
        ),
      ),
    );
  }
}
