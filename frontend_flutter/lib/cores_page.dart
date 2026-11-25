import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

class CoresPage extends StatefulWidget {
  const CoresPage({super.key});

  @override
  State<CoresPage> createState() => _CoresPageState();
}

class _CoresPageState extends State<CoresPage> {
  List<Map<String, dynamic>> _cores = [];
  List<Map<String, dynamic>> _proxies = [];
  Map<String, dynamic> _settings = {};
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _downloadProgress;
  late final void Function() _removeDownloadListener;
  late final void Function() _removeImportListener;

  @override
  void initState() {
    super.initState();
    _removeDownloadListener = AppBridge.onEvent('download:progress', (payload) {
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
    _removeImportListener = AppBridge.onEvent('core-import:progress', (
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
        AppBridge.call('BrowserCoreList'),
        AppBridge.call('BrowserCoreExtendedInfo'),
        AppBridge.call('GetBrowserSettings'),
      ]);
      final cores = (values[0] is List ? values[0] as List : const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      var proxies = <Map<String, dynamic>>[];
      try {
        final proxyResult = await AppBridge.call('BrowserProxyList');
        proxies = (proxyResult as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } catch (_) {}
      final extended = <String, Map<String, dynamic>>{};
      for (final item in (values[1] is List ? values[1] as List : const [])) {
        if (item is Map) {
          extended['${item['coreId'] ?? ''}'] = Map<String, dynamic>.from(item);
        }
      }
      final checks = await Future.wait(
        cores.map((core) async {
          try {
            return await AppBridge.call('BrowserCoreValidate', [
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
        _proxies = proxies;
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
      await AppBridge.call('BrowserCoreScan');
      await _load();
      _message('内核扫描完成');
    } catch (error) {
      _message('扫描失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSettings() async {
    if (_settings.isEmpty) {
      try {
        final settings = await AppBridge.call('GetBrowserSettings');
        if (mounted && settings is Map) {
          setState(() => _settings = Map<String, dynamic>.from(settings));
        }
      } catch (error) {
        if (mounted) _message('读取浏览器设置失败：$error');
      }
      if (_settings.isEmpty) {
        if (mounted) _message('浏览器设置尚未加载，请刷新后重试');
        return;
      }
    }
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
                  const SizedBox(height: 10),
                  PrismTextField(
                    controller: fingerprint,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const PrismInputDecoration(
                      labelText: '默认指纹参数（每行一个）',
                    ),
                  ),
                  const SizedBox(height: 10),
                  PrismTextField(
                    controller: launchArgs,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const PrismInputDecoration(
                      labelText: '默认启动参数（每行一个）',
                    ),
                  ),
                  const SizedBox(height: 10),
                  PrismTextField(
                    controller: startUrls,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const PrismInputDecoration(
                      labelText: '默认启动页面（每行一个 URL）',
                    ),
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
                  PrismTextField(
                    controller: readyTimeout,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '启动就绪超时（毫秒）',
                    ),
                  ),
                  const SizedBox(height: 10),
                  PrismTextField(
                    controller: stableWindow,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '启动稳定窗口（毫秒）',
                    ),
                  ),
                  const SizedBox(height: 10),
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
      await AppBridge.call('SaveBrowserSettings', [result]);
      await _load();
      _message('浏览器全局设置已保存');
    } catch (error) {
      _message('保存失败：$error');
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await AppBridge.call('BrowserCoreImportLocal');
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
    Timer? debounceTimer;
    var validating = false;
    bool? pathValid;
    var validationMessage = '';
    var validationSeq = 0;

    final result = await showPrismDialog<Map<String, String>>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          Future<void> runValidation(String rawPath) async {
            final target = rawPath.trim();
            if (target.isEmpty) {
              setDialog(() {
                validating = false;
                pathValid = null;
                validationMessage = '';
              });
              return;
            }
            final seq = ++validationSeq;
            setDialog(() {
              validating = true;
              validationMessage = '正在验证路径…';
            });
            try {
              final validation = await AppBridge.call('BrowserCoreValidate', [
                target,
              ]);
              if (!dialogContext.mounted || seq != validationSeq) return;
              if (validation is Map) {
                final valid = validation['valid'] == true;
                setDialog(() {
                  validating = false;
                  pathValid = valid;
                  validationMessage =
                      (validation['message'] ?? (valid ? '路径有效' : '路径无效'))
                          .toString();
                });
              }
            } catch (error) {
              if (!dialogContext.mounted || seq != validationSeq) return;
              setDialog(() {
                validating = false;
                pathValid = false;
                validationMessage = '$error';
              });
            }
          }

          void scheduleValidation(String value) {
            debounceTimer?.cancel();
            debounceTimer = Timer(
              const Duration(milliseconds: 450),
              () => runValidation(value),
            );
          }

          return PrismDialog(
            title: Text(core == null ? '添加浏览器内核' : '编辑浏览器内核'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrismTextField(
                    controller: name,
                    decoration: const PrismInputDecoration(labelText: '内核名称'),
                  ),
                  const SizedBox(height: 10),
                  PrismTextField(
                    controller: path,
                    onChanged: scheduleValidation,
                    decoration: const PrismInputDecoration(
                      labelText: '可执行文件路径',
                      hintText: '例如 C:\\...\\chrome.exe',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      prism.TextButton.icon(
                        onPressed: validating
                            ? null
                            : () {
                                debounceTimer?.cancel();
                                runValidation(path.text);
                              },
                        icon: validating
                            ? const SizedBox.square(
                                dimension: 14,
                                child: PrismProgressIndicator(size: 14),
                              )
                            : const PrismGlyph(
                                AntGlyphs.checkCircle,
                                size: 16,
                              ),
                        label: Text(validating ? '验证中…' : '验证路径'),
                      ),
                      const SizedBox(width: 8),
                      if (pathValid != null)
                        PrismBadge(
                          label: pathValid! ? '路径有效' : '路径无效',
                          tone: pathValid!
                              ? PrismTone.success
                              : PrismTone.danger,
                        ),
                    ],
                  ),
                  if (validationMessage.isNotEmpty && !validating) ...[
                    const SizedBox(height: 6),
                    PrismBanner(
                      tone: pathValid == true
                          ? PrismTone.success
                          : PrismTone.danger,
                      message: validationMessage,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              prism.FilledButton(
                onPressed: () => Navigator.pop(dialogContext, {
                  'name': name.text.trim(),
                  'path': path.text.trim(),
                }),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    debounceTimer?.cancel();
    name.dispose();
    path.dispose();
    if (result == null) return;
    if (result['name']!.isEmpty || result['path']!.isEmpty) {
      _message('请填写内核名称和路径');
      return;
    }
    setState(() => _busy = true);
    try {
      await AppBridge.call('BrowserCoreSave', [
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
      await AppBridge.call('BrowserCoreSetDefault', [id]);
      await _load();
      _message('默认内核已更新');
    } catch (error) {
      _message('设置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _coreDeleteReason(Map<String, dynamic> core) {
    final instanceCount = (core['instanceCount'] as num?)?.toInt() ?? 0;
    if (instanceCount > 0) {
      return '已有 $instanceCount 个实例使用此内核，不能删除';
    }
    if (core['isDefault'] == true) {
      return '默认内核不能删除';
    }
    return null;
  }

  Future<void> _delete(Map<String, dynamic> core) async {
    final deleteReason = _coreDeleteReason(core);
    if (deleteReason != null) {
      _message(deleteReason);
      return;
    }
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
      await AppBridge.call('BrowserCoreDelete', ['${core['coreId'] ?? ''}']);
      await _load();
      _message('内核已删除');
    } catch (error) {
      _message('删除失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDownloadModal({Map<String, dynamic>? redownloadCore}) async {
    final isRedownload = redownloadCore != null;
    final coreName = isRedownload
        ? (redownloadCore['coreName'] ?? '内核').toString()
        : null;
    final name = TextEditingController(text: coreName ?? '');
    final url = TextEditingController();
    var proxyMode = 'system';
    String? proxyId = _proxies.isEmpty
        ? null
        : (_proxies.first['proxyId'] ?? '').toString();
    var recommendationLoading = false;
    var recommendationError = '';
    var recommendation = <String, String>{};
    var autoFetched = false;
    var downloading = false;
    var downloadError = '';
    var downloadDone = false;
    Map<String, dynamic>? modalProgress;

    void Function()? removeModalProgressListener;

    await showPrismDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          final colors = prism.Theme.of(dialogContext).colorScheme;

          Future<void> fetchRecommendation() async {
            if (recommendationLoading) return;
            setDialog(() {
              recommendationLoading = true;
              recommendationError = '';
            });
            try {
              final result = await _fetchCoreRecommendation();
              if (!dialogContext.mounted) return;
              setDialog(() {
                recommendation = result;
                if (url.text.trim().isEmpty) {
                  url.text = result['downloadUrl'] ?? '';
                }
                if (!isRedownload && name.text.trim().isEmpty) {
                  name.text = result['name'] ?? '';
                }
              });
            } catch (error) {
              if (dialogContext.mounted) {
                setDialog(() => recommendationError = '$error');
              }
            } finally {
              if (dialogContext.mounted) {
                setDialog(() => recommendationLoading = false);
              }
            }
          }

          if (!autoFetched) {
            autoFetched = true;
            Future.microtask(fetchRecommendation);
          }

          Future<void> startDownload() async {
            final targetName = name.text.trim();
            final targetUrl = url.text.trim();
            if (!isRedownload && targetName.isEmpty) {
              setDialog(() => downloadError = '请填写内核名称');
              return;
            }
            if (targetUrl.isEmpty) {
              setDialog(() => downloadError = '请填写下载地址');
              return;
            }
            final selectedProxy = _proxies.where(
              (proxy) => proxy['proxyId'] == proxyId,
            );
            final proxyConfig = switch (proxyMode) {
              'direct' => '__direct__',
              'custom' => selectedProxy.isEmpty
                  ? ''
                  : ((selectedProxy.first['proxyConfig'] ?? proxyId ?? '')
                        .toString()),
              _ => '__system__',
            };
            if (proxyConfig.isEmpty) {
              setDialog(() => downloadError = '请选择有效的下载代理节点');
              return;
            }

            setDialog(() {
              downloading = true;
              downloadError = '';
              downloadDone = false;
              modalProgress = {
                'phase': 'starting',
                'progress': 0,
                'message': isRedownload ? '准备重新下载…' : '正在启动下载…',
              };
            });
            setState(() {
              _busy = true;
              _downloadProgress = modalProgress;
            });

            removeModalProgressListener?.call();
            removeModalProgressListener = AppBridge.onEvent(
              'download:progress',
              (payload) {
                if (!dialogContext.mounted || payload is! Map) return;
                final progress = Map<String, dynamic>.from(payload);
                final phase = (progress['phase'] ?? '').toString();
                setDialog(() {
                  modalProgress = progress;
                  if (phase == 'done') {
                    downloading = false;
                    downloadDone = true;
                  } else if (phase == 'error') {
                    downloading = false;
                    downloadError =
                        (progress['message'] ?? '下载失败').toString();
                  }
                });
              },
            );

            try {
              if (isRedownload) {
                await AppBridge.call('BrowserCoreRedownload', [
                  redownloadCore['coreId'],
                  targetUrl,
                  proxyConfig,
                ]);
              } else {
                await AppBridge.call('BrowserCoreDownload', [
                  targetName,
                  targetUrl,
                  proxyConfig,
                ]);
              }
              await _load();
              if (dialogContext.mounted) {
                setDialog(() {
                  downloading = false;
                  downloadDone = true;
                  modalProgress = {
                    'phase': 'done',
                    'progress': 100,
                    'message': isRedownload ? '内核重新下载完成' : '内核下载完成',
                  };
                });
              }
            } catch (error) {
              if (dialogContext.mounted) {
                setDialog(() {
                  downloading = false;
                  downloadError = '${isRedownload ? '重新下载' : '下载'}失败：$error';
                  modalProgress = null;
                });
              }
              if (mounted) setState(() => _downloadProgress = null);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          }

          return PrismDialog(
            title: Text(isRedownload ? '重新下载 $coreName' : '下载浏览器内核'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isRedownload) ...[
                      const PrismBanner(
                        tone: PrismTone.warning,
                        title: '目录替换与回滚说明',
                        message:
                            '重新下载将替换当前内核目录；若下载、校验或解压失败，系统会自动回滚到原有内核，不会影响已配置的实例。',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!isRedownload) ...[
                      PrismTextField(
                        controller: name,
                        enabled: !downloading,
                        decoration: const PrismInputDecoration(
                          labelText: '内核名称',
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    PrismTextField(
                      controller: url,
                      enabled: !downloading,
                      decoration: const PrismInputDecoration(
                        labelText: '下载地址',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        prism.TextButton.icon(
                          onPressed: (recommendationLoading || downloading)
                              ? null
                              : () {
                                  url.clear();
                                  fetchRecommendation();
                                },
                          icon: recommendationLoading
                              ? const SizedBox.square(
                                  dimension: 15,
                                  child: PrismProgressIndicator(size: 15),
                                )
                              : const PrismGlyph(
                                  AntGlyphs.sparkles,
                                  size: 16,
                                ),
                          label: Text(
                            recommendationLoading ? '正在匹配最新 Release…' : '匹配最新内核版本',
                          ),
                        ),
                        prism.TextButton.icon(
                          onPressed: () => _openExternalUrl(
                            recommendation['releasesUrl'] ??
                                'https://github.com/adryfish/fingerprint-chromium/releases',
                          ),
                          icon: const PrismGlyph(
                            AntGlyphs.openInNew,
                            size: 15,
                          ),
                          label: const Text('打开 Releases'),
                        ),
                      ],
                    ),
                    if (recommendation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '已匹配 ${recommendation['assetName']}（${recommendation['releaseTag']}）',
                        style: prism.AppTextStyle.caption1
                            .of(dialogContext)
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                    if (recommendationError.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      PrismBanner(
                        tone: PrismTone.warning,
                        message: '自动匹配最新内核失败：$recommendationError',
                      ),
                    ],
                    const SizedBox(height: 10),
                    PrismDropdownField<String>(
                      initialValue: proxyMode,
                      decoration: const PrismInputDecoration(labelText: '下载代理'),
                      items: [
                        const PrismDropdownItem(
                          value: 'system',
                          child: Text('跟随系统代理'),
                        ),
                        const PrismDropdownItem(
                          value: 'direct',
                          child: Text('直连，不使用代理'),
                        ),
                        if (_proxies.isNotEmpty)
                          const PrismDropdownItem(
                            value: 'custom',
                            child: Text('使用指定代理节点'),
                          ),
                      ],
                      onChanged: downloading
                          ? null
                          : (value) =>
                                setDialog(() => proxyMode = value ?? 'system'),
                    ),
                    if (proxyMode == 'custom') ...[
                      const SizedBox(height: 10),
                      PrismDropdownField<String>(
                        initialValue:
                            _proxies.any((proxy) => proxy['proxyId'] == proxyId)
                            ? proxyId
                            : null,
                        decoration: const PrismInputDecoration(
                          labelText: '代理节点',
                        ),
                        items: [
                          for (final proxy in _proxies)
                            PrismDropdownItem(
                              value: (proxy['proxyId'] ?? '').toString(),
                              child: Text(
                                '${proxy['proxyName'] ?? '未命名代理'} · ${proxy['proxyConfig'] ?? ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: downloading
                            ? null
                            : (value) => setDialog(() => proxyId = value),
                      ),
                    ],
                    if (modalProgress != null) ...[
                      const SizedBox(height: 14),
                      PrismProgressPanel(
                        title: downloading
                            ? (isRedownload ? '正在重新下载内核' : '正在下载内核')
                            : (downloadDone ? '下载完成' : '下载状态'),
                        subtitle: (modalProgress!['message'] ?? '').toString(),
                        progress: _progressValue(modalProgress!['progress']),
                      ),
                    ],
                    if (downloadError.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      PrismBanner(
                        tone: PrismTone.danger,
                        message: downloadError,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: downloading
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(downloadDone ? '完成' : '关闭'),
              ),
              if (!downloadDone)
                prism.FilledButton(
                  onPressed: downloading ? null : startDownload,
                  child: Text(
                    downloading
                        ? '下载中…'
                        : (isRedownload ? '开始重新下载' : '开始下载'),
                  ),
                ),
            ],
          );
        },
      ),
    );

    removeModalProgressListener?.call();
    name.dispose();
    url.dispose();
  }

  Future<Map<String, String>> _fetchCoreRecommendation() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/adryfish/fingerprint-chromium/releases/latest',
        ),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'AntBrowser');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub Releases 请求失败：${response.statusCode}');
      }
      final release = jsonDecode(await response.transform(utf8.decoder).join());
      if (release is! Map) throw const FormatException('Releases 返回内容无效');
      final platform = Platform.operatingSystem;
      final architecture = await _currentArchitecture();
      if (architecture.isEmpty) {
        throw const FormatException('无法识别当前设备架构');
      }
      final assets = (release['assets'] as List? ?? []).whereType<Map>().where((
        asset,
      ) {
        final assetName = (asset['name'] ?? '').toString().toLowerCase();
        final archive = [
          '.zip',
          '.tar.xz',
          '.txz',
          '.tar.gz',
          '.tgz',
          '.tar.bz2',
          '.tbz2',
          '.tar',
        ].any(assetName.endsWith);
        final platformMatches = switch (platform) {
          'windows' => assetName.contains('windows'),
          'linux' => assetName.contains('linux'),
          'macos' =>
            assetName.contains('macos') || assetName.contains('darwin'),
          _ => false,
        };
        final architectureMatches = architecture == 'arm64'
            ? assetName.contains('arm64') || assetName.contains('aarch64')
            : assetName.contains('amd64') ||
                  assetName.contains('x64') ||
                  assetName.contains('x86_64');
        return archive &&
            platformMatches &&
            architectureMatches &&
            (asset['browser_download_url'] ?? '').toString().isNotEmpty;
      }).toList();
      if (assets.isEmpty) throw const FormatException('没有找到适配当前系统和架构的内核包');
      assets.sort((left, right) {
        final leftName = (left['name'] ?? '').toString().toLowerCase();
        final rightName = (right['name'] ?? '').toString().toLowerCase();
        final preferredSuffix = platform == 'windows'
            ? '.zip'
            : platform == 'linux'
            ? '.tar.xz'
            : '';
        final leftScore =
            preferredSuffix.isNotEmpty && leftName.endsWith(preferredSuffix)
            ? 1
            : 0;
        final rightScore =
            preferredSuffix.isNotEmpty && rightName.endsWith(preferredSuffix)
            ? 1
            : 0;
        return rightScore.compareTo(leftScore);
      });
      final asset = assets.first;
      final releaseTag = (release['tag_name'] ?? '').toString();
      final major = releaseTag.split('.').first;
      return {
        'assetName': (asset['name'] ?? '').toString(),
        'downloadUrl': (asset['browser_download_url'] ?? '').toString(),
        'releaseTag': releaseTag,
        'releasesUrl':
            (release['html_url'] ??
                    'https://github.com/adryfish/fingerprint-chromium/releases')
                .toString(),
        'name': major.isEmpty ? 'chrome-latest' : 'chrome-$major',
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _currentArchitecture() async {
    var value =
        (Platform.environment['PROCESSOR_ARCHITEW6432'] ??
                Platform.environment['PROCESSOR_ARCHITECTURE'] ??
                '')
            .toLowerCase();
    if (value.isEmpty && !Platform.isWindows) {
      try {
        final result = await Process.run('uname', ['-m']);
        value = result.stdout.toString().trim().toLowerCase();
      } catch (_) {}
    }
    if (value.contains('arm64') || value.contains('aarch64')) return 'arm64';
    if (value.contains('amd64') ||
        value.contains('x64') ||
        value.contains('x86_64')) {
      return 'amd64';
    }
    return '';
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
      _message('打开链接失败：$error');
    }
  }

  void _message(String value) {
    if (mounted) showPrismNotice(context, value);
  }

  Widget _buildCoreSettingsCard(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final userDataRoot = (_settings['userDataRoot'] ?? '').toString().trim();
    final restoreLastSession = _settings['restoreLastSession'] == true;
    final lightStartEnabled = _settings['lightStartEnabled'] != false;
    final readyTimeout =
        (_settings['startReadyTimeoutMs'] as num?)?.toInt() ?? 3000;
    final stableWindow =
        (_settings['startStableWindowMs'] as num?)?.toInt() ?? 1200;
    final startUrls = (_settings['defaultStartUrls'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final fingerprintArgs = (_settings['defaultFingerprintArgs'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final launchArgs = (_settings['defaultLaunchArgs'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    Widget kvRow(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: prism.AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: prism.AppTextStyle.caption1.of(context),
            ),
          ),
        ],
      ),
    );

    return PrismSectionCard(
      title: '全局浏览器设置',
      glyph: AntGlyphs.tune,
      actions: [
        prism.OutlinedButton.icon(
          onPressed: _busy ? null : _editSettings,
          icon: const PrismGlyph(AntGlyphs.edit, size: 14),
          label: const Text('编辑设置'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              PrismBadge(
                label: lightStartEnabled ? '轻启动：开启' : '轻启动：关闭',
                tone: lightStartEnabled ? PrismTone.success : PrismTone.neutral,
              ),
              PrismBadge(
                label: restoreLastSession ? '恢复上次标签页：开启' : '恢复上次标签页：关闭',
                tone: restoreLastSession ? PrismTone.info : PrismTone.neutral,
              ),
              PrismBadge(
                label: '就绪超时 ${readyTimeout}ms',
                tone: PrismTone.neutral,
              ),
              PrismBadge(
                label: '稳定窗口 ${stableWindow}ms',
                tone: PrismTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 10),
          kvRow('用户数据目录', userDataRoot.isEmpty ? '默认目录' : userDataRoot),
          kvRow(
            '默认启动页',
            startUrls.isEmpty ? '未配置' : startUrls.join(' · '),
          ),
          kvRow(
            '默认指纹参数',
            fingerprintArgs.isEmpty
                ? '未配置'
                : '${fingerprintArgs.length} 项（${fingerprintArgs.take(2).join(', ')}${fingerprintArgs.length > 2 ? '…' : ''}）',
          ),
          kvRow(
            '默认启动参数',
            launchArgs.isEmpty
                ? '未配置'
                : '${launchArgs.length} 项（${launchArgs.take(2).join(', ')}${launchArgs.length > 2 ? '…' : ''}）',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '浏览器内核管理',
                      style: prism.AppTextStyle.title2.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '共 ${_cores.length} 个内核',
                      style: prism.AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              prism.TonalButtonGroup(
                size: prism.TonalButtonSize.section,
                children: [
                  prism.IconButton(
                    tooltip: '扫描本地内核',
                    onPressed: _busy ? null : _scan,
                    icon: const PrismGlyph(AntGlyphs.search, size: 18),
                  ),
                  prism.IconButton(
                    tooltip: '导入本地内核',
                    onPressed: _busy ? null : _import,
                    icon: const PrismGlyph(AntGlyphs.folder, size: 18),
                  ),
                  prism.IconButton(
                    tooltip: '添加内核路径',
                    onPressed: _busy ? null : () => _edit(),
                    icon: const PrismGlyph(AntGlyphs.add, size: 18),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              prism.FilledButton.icon(
                onPressed: _busy ? null : () => _openDownloadModal(),
                icon: const PrismGlyph(AntGlyphs.download, size: 16),
                label: const Text('下载内核'),
              ),
            ],
          ),
          if (_downloadProgress != null) ...[
            const SizedBox(height: 12),
            PrismProgressPanel(
              title: '内核处理进度',
              subtitle: '${_downloadProgress!['message'] ?? ''}',
              progress: _progressValue(_downloadProgress!['progress']),
            ),
          ],
          const SizedBox(height: 14),
          _buildCoreSettingsCard(context),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : _cores.isEmpty
                ? PrismEmptyState(
                    title: '暂未配置浏览器内核',
                    subtitle: '可以自动扫描本机内核、手动添加路径或直接下载最新指纹浏览器内核。',
                    glyph: AntGlyphs.cpu,
                    action: prism.FilledButton.icon(
                      onPressed: _busy ? null : () => _openDownloadModal(),
                      icon: const PrismGlyph(AntGlyphs.download, size: 16),
                      label: const Text('下载内核'),
                    ),
                  )
                : ListView.separated(
                    itemCount: _cores.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final core = _cores[index];
                      final validation = core['validation'] is Map
                          ? Map<String, dynamic>.from(core['validation'] as Map)
                          : const <String, dynamic>{};
                      final valid = validation['valid'] == true;
                      final isDefault = core['isDefault'] == true;
                      final iconTone = PrismToneColors.of(
                        context,
                        isDefault ? PrismTone.primary : PrismTone.info,
                      );
                      final statusTone = PrismToneColors.of(
                        context,
                        valid ? PrismTone.success : PrismTone.danger,
                      );
                      return PrismCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 17,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            prism.Surface(
                              color: iconTone.bg,
                              shape: prism.AppShape.md,
                              child: SizedBox(
                                width: 42,
                                height: 42,
                                child: Center(
                                  child: PrismGlyph(
                                    AntGlyphs.cpu,
                                    size: 20,
                                    color: iconTone.fg,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '${core['coreName'] ?? '未命名内核'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: prism.AppTextStyle.subheadline
                                            .of(context, emphasized: true),
                                      ),
                                      if (isDefault)
                                        const PrismBadge(
                                          label: '默认',
                                          tone: PrismTone.primary,
                                        ),
                                      PrismBadge(
                                        label: valid ? '可用' : '路径无效',
                                        tone: valid
                                            ? PrismTone.success
                                            : PrismTone.danger,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${core['corePath'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: prism.AppTextStyle.caption1
                                        .of(context)
                                        .copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '使用实例 ${((core['instanceCount'] as num?) ?? 0).toInt()} 个'
                                    ' · Chrome ${core['chromeVersion'] ?? '版本未知'}',
                                    style: prism.AppTextStyle.caption2
                                        .of(context)
                                        .copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                  if (!valid) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '${validation['message'] ?? '路径无效'}',
                                      style: prism.AppTextStyle.caption2
                                          .of(context)
                                          .copyWith(color: statusTone.fg),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (!isDefault)
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
                                  await AppBridge.call('OpenCorePath', [
                                    '${core['corePath'] ?? ''}',
                                  ]);
                                } catch (error) {
                                  _message('$error');
                                }
                              },
                              icon: const PrismGlyph(
                                AntGlyphs.folder,
                                size: 18,
                              ),
                            ),
                            prism.IconButton(
                              tooltip: '重新下载',
                              onPressed: _busy
                                  ? null
                                  : () => _openDownloadModal(
                                      redownloadCore: core,
                                    ),
                              icon: const PrismGlyph(
                                AntGlyphs.download,
                                size: 18,
                              ),
                            ),
                            prism.IconButton(
                              tooltip: '编辑',
                              onPressed: _busy ? null : () => _edit(core),
                              icon: const PrismGlyph(AntGlyphs.edit, size: 18),
                            ),
                            prism.IconButton(
                              tooltip: _coreDeleteReason(core) ?? '删除',
                              onPressed:
                                  _busy || _coreDeleteReason(core) != null
                                  ? null
                                  : () => _delete(core),
                              icon: const PrismGlyph(
                                AntGlyphs.delete,
                                size: 18,
                              ),
                            ),
                          ],
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
