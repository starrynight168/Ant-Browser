import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

const _dualInstanceScriptId = 'dual-instance-runtime-switch';
const _refreshableSourceTypes = {
  'builtin',
  'local-file',
  'local-dir',
  'remote-url',
  'git',
};

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String _formatDateTime(dynamic raw) {
  final text = '${raw ?? ''}'.trim();
  if (text.isEmpty) return '-';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final local = parsed.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:${_twoDigits(local.second)}';
}

String _formatVersionTime(dynamic raw) {
  final text = '${raw ?? ''}'.trim();
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return '';
  final local = parsed.toLocal();
  return 'V ${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _formatDuration(dynamic rawMs) {
  final ms = (rawMs is num)
      ? rawMs.toInt()
      : int.tryParse('${rawMs ?? ''}') ?? 0;
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}

String _normalizePublicApiPath(String value) {
  var source = value.trim().replaceAll('\\', '/');
  const basePath = '/api/automation/hooks';
  if (source.toLowerCase().startsWith('$basePath/')) {
    source = source.substring(basePath.length + 1);
  } else if (source.toLowerCase().startsWith('${basePath.substring(1)}/')) {
    source = source.substring(basePath.length);
  }
  return source
      .split('/')
      .map(
        (segment) => segment
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), ''),
      )
      .where((segment) => segment.isNotEmpty)
      .join('/');
}

String _recommendedApiPath(String name, String id) {
  final candidate = _normalizePublicApiPath(name);
  if (candidate.isNotEmpty) return candidate;
  final fromId = _normalizePublicApiPath(id);
  if (fromId.isNotEmpty) return fromId;
  return 'custom-script';
}

String _prettyJson(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  try {
    final decoded = jsonDecode(trimmed);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return trimmed;
  }
}

Map<String, dynamic> _tryDecodeMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _parseVariables(dynamic raw) {
  dynamic source = raw;
  if (source is String && source.trim().isNotEmpty) {
    try {
      source = jsonDecode(source);
    } catch (_) {
      return [];
    }
  }
  if (source is! List) return [];
  return source
      .whereType<Map>()
      .map(
        (item) => <String, dynamic>{
          'name': '${item['name'] ?? ''}',
          'defaultValue': '${item['defaultValue'] ?? ''}',
          'description': '${item['description'] ?? ''}',
          'required': item['required'] == true,
        },
      )
      .toList();
}

String _resolveLaunchCode(
  Map<String, dynamic> script,
  List<Map<String, dynamic>> profiles,
) {
  final selector = _tryDecodeMap(script['selectorText']);
  final targetConfig = _tryDecodeMap(script['targetConfig']);
  final targetSelector = _tryDecodeMap(targetConfig['selector']);

  final directCode = '${selector['code'] ?? targetSelector['code'] ?? ''}'
      .trim();
  if (directCode.isNotEmpty) return directCode;

  final profileId =
      '${selector['profileId'] ?? targetSelector['profileId'] ?? ''}'.trim();
  final profileName =
      '${selector['profileName'] ?? targetSelector['profileName'] ?? ''}'
          .trim();

  for (final profile in profiles) {
    final pid = '${profile['profileId'] ?? ''}'.trim();
    final pname = '${profile['profileName'] ?? ''}'.trim();
    final code = '${profile['launchCode'] ?? ''}'.trim();
    if (code.isEmpty) continue;
    if (profileId.isNotEmpty && pid == profileId) return code;
    if (profileName.isNotEmpty && pname == profileName) return code;
  }
  return '';
}

bool _isInterfaceMode(Map<String, dynamic> script) {
  if ('${script['type'] ?? ''}' == 'launch-api') return true;
  final publicApi = _tryDecodeMap(script['publicAPI']);
  return publicApi['enabled'] == true;
}

bool _isRefreshableSource(Map<String, dynamic>? record) {
  if (record == null) return false;
  final source = _tryDecodeMap(record['source']);
  final type = '${source['type'] ?? ''}'.trim();
  return _refreshableSourceTypes.contains(type);
}

String _formatSourceLabel(Map<String, dynamic>? record) {
  if (record == null) return '';
  final source = _tryDecodeMap(record['source']);
  final type = '${source['type'] ?? ''}'.trim();
  if (type.isEmpty) return '';
  final typeLabel = switch (type) {
    'builtin' => '内置脚本库',
    'local-file' => '本地文件',
    'local-dir' => '本地目录',
    'remote-url' => '远程 URL',
    'git' => 'Git 仓库',
    'text' => '文本导入',
    'manual' => '手动创建',
    _ => type,
  };
  final detail =
      '${source['label'] ?? source['uri'] ?? source['path'] ?? ''}'.trim();
  final ref = '${source['ref'] ?? ''}'.trim();
  if (detail.isEmpty) return typeLabel;
  return ref.isEmpty ? '$typeLabel · $detail' : '$typeLabel · $detail ($ref)';
}

String _statusLabel(String status) => switch (status) {
  'ready' => '就绪',
  'disabled' => '已禁用',
  _ => '草稿',
};

PrismTone _statusTone(String status) => switch (status) {
  'ready' => PrismTone.success,
  'disabled' => PrismTone.danger,
  _ => PrismTone.warning,
};

String _buildScriptApiUrl(
  Map<String, dynamic> script,
  String baseUrl,
) {
  final cleanBase = baseUrl.isEmpty
      ? 'http://127.0.0.1:19876'
      : baseUrl.replaceAll(RegExp(r'/+$'), '');
  final publicApi = _tryDecodeMap(script['publicAPI']);
  final path = _normalizePublicApiPath('${publicApi['path'] ?? ''}');
  if (publicApi['enabled'] == true && path.isNotEmpty) {
    return '$cleanBase/api/automation/hooks/$path';
  }
  if ('${script['type'] ?? ''}' == 'launch-api') {
    return '$cleanBase/api/launch';
  }
  return '$cleanBase/api/automation/scripts/${script['id'] ?? ''}/run';
}

String _buildScriptRequestJson(
  Map<String, dynamic> script, {
  String launchCode = '',
}) {
  final publicApi = _tryDecodeMap(script['publicAPI']);
  final reqBody = '${publicApi['requestBodyText'] ?? ''}'.trim();
  if (publicApi['enabled'] == true && reqBody.isNotEmpty) {
    var body = reqBody;
    for (final v in _parseVariables(publicApi['variables'])) {
      final name = '${v['name'] ?? ''}'.trim();
      final defVal = '${v['defaultValue'] ?? ''}';
      if (name.isNotEmpty) {
        body = body.replaceAll('{{$name}}', defVal);
      }
    }
    return _prettyJson(body);
  }
  final selector = _tryDecodeMap(script['selectorText']);
  if (launchCode.isNotEmpty && selector['code'] == null) {
    selector['code'] = launchCode;
  }
  final params = _tryDecodeMap(script['paramsText']);
  if ('${script['type'] ?? ''}' == 'launch-api') {
    return const JsonEncoder.withIndent('  ').convert({
      if (selector.isNotEmpty) 'selector': selector,
      ...params,
    });
  }
  return const JsonEncoder.withIndent('  ').convert({
    if (selector.isNotEmpty) 'selector': selector,
    if (params.isNotEmpty) 'params': params,
  });
}

String _buildCurlCommand({
  required String url,
  required String bodyJson,
  required String authHeader,
  String apiKey = '',
}) {
  final headerName = authHeader.trim().isEmpty
      ? 'X-Ant-Api-Key'
      : authHeader.trim();
  final escapedBody = bodyJson.replaceAll("'", "'\\''");
  final buffer = StringBuffer()
    ..writeln("curl -X POST '$url' \\")
    ..writeln("  -H 'Content-Type: application/json' \\");
  if (apiKey.trim().isNotEmpty) {
    buffer.writeln("  -H '$headerName: ${apiKey.trim()}' \\");
  } else {
    buffer.writeln("  -H '$headerName: <YOUR_API_KEY>' \\");
  }
  buffer.write("  -d '$escapedBody'");
  return buffer.toString();
}

List<String> _extractOutputPaths(String resultText) {
  final paths = <String>{};
  void collect(dynamic node, [String keyHint = '']) {
    if (node is Map) {
      for (final entry in node.entries) {
        collect(entry.value, entry.key.toString().toLowerCase());
      }
    } else if (node is List) {
      for (final item in node) {
        collect(item, keyHint);
      }
    } else if (node is String) {
      final value = node.trim();
      if (value.isEmpty || value.length > 500) return;
      final isPathKey =
          keyHint.contains('path') ||
          keyHint.contains('file') ||
          keyHint.contains('dir') ||
          keyHint.contains('screenshot') ||
          keyHint.contains('output') ||
          keyHint.contains('artifact');
      final looksLikeAbsPath =
          RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
          (value.startsWith('/') &&
              !value.startsWith('//') &&
              value.contains('/'));
      if (looksLikeAbsPath &&
          (isPathKey ||
              RegExp(
                r'\.(png|jpe?g|webp|pdf|json|csv|txt|html|zip|mp4|log)$',
                caseSensitive: false,
              ).hasMatch(value))) {
        paths.add(value);
      }
    }
  }

  try {
    final decoded = jsonDecode(resultText);
    collect(decoded);
  } catch (_) {}
  return paths.toList();
}

Future<void> _showLogViewerDialog(
  BuildContext context, {
  required String title,
  required String logText,
}) async {
  await showPrismDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (context) => PrismDialog(
      title: Text('执行日志 · $title'),
      content: SizedBox(
        width: 780,
        height: 480,
        child: logText.trim().isEmpty
            ? const PrismEmptyState(
                glyph: AntGlyphs.logs,
                title: '暂无执行日志',
              )
            : PrismCodeSurface(
                code: logText,
                language: 'log',
                maxHeight: 440,
                showCopy: true,
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

Future<void> _showPublicApiQuickDialog(
  BuildContext context, {
  required Map<String, dynamic> script,
  required String baseUrl,
  required String authHeader,
  required bool authEnabled,
  required String launchCode,
}) async {
  final url = _buildScriptApiUrl(script, baseUrl);
  final publicApi = _tryDecodeMap(script['publicAPI']);
  final apiEnabled = publicApi['enabled'] == true;
  final timeoutMs =
      ((publicApi['timeoutMs'] as num?)?.toInt() ?? 300000).clamp(
        1000,
        1800000,
      );
  final bodyController = TextEditingController(
    text: _buildScriptRequestJson(script, launchCode: launchCode),
  );
  final apiKeyController = TextEditingController();
  var invoking = false;
  var output = '';

  await showPrismDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) {
        final curl = _buildCurlCommand(
          url: url,
          bodyJson: bodyController.text.trim().isEmpty
              ? '{}'
              : bodyController.text.trim(),
          authHeader: authHeader,
          apiKey: apiKeyController.text,
        );
        return PrismDialog(
          title: Text('接口调用 · ${script['name'] ?? script['id'] ?? ''}'),
          content: SizedBox(
            width: 740,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!apiEnabled && '${script['type'] ?? ''}' != 'launch-api')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: PrismBanner(
                        tone: PrismTone.warning,
                        message: '该脚本尚未启用对外 API，当前显示内部脚本触发地址。可在编辑页开启对外 API。',
                      ),
                    ),
                  Row(
                    children: [
                      const PrismBadge(label: 'POST', tone: PrismTone.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: prism.SelectableText(
                          url,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      prism.OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          showPrismNotice(context, '已复制接口 URL');
                        },
                        icon: const PrismGlyph(AntGlyphs.copy, size: 14),
                        label: const Text('复制 URL'),
                      ),
                      const SizedBox(width: 6),
                      prism.OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: curl));
                          showPrismNotice(context, '已复制 cURL 命令');
                        },
                        icon: const PrismGlyph(AntGlyphs.code, size: 14),
                        label: const Text('复制 cURL'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PrismTextField(
                    controller: apiKeyController,
                    onChanged: (_) => setDialog(() {}),
                    decoration: PrismInputDecoration(
                      labelText:
                          'API Key（请求头：$authHeader${authEnabled ? ' · 已启用鉴权' : ' · 可留空自动解析'}）',
                      hintText: '输入 Launch Server API Key',
                    ),
                  ),
                  const SizedBox(height: 10),
                  PrismTextField(
                    controller: bodyController,
                    minLines: 4,
                    maxLines: 10,
                    onChanged: (_) => setDialog(() {}),
                    decoration: const PrismInputDecoration(
                      labelText: '请求 Body JSON',
                    ),
                  ),
                  const SizedBox(height: 10),
                  PrismCodeSurface(
                    code: curl,
                    language: 'bash',
                    maxHeight: 130,
                    showCopy: true,
                  ),
                  if (output.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    PrismCodeSurface(
                      code: output,
                      language: 'json',
                      maxHeight: 180,
                      showCopy: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            prism.FilledButton.icon(
              onPressed: invoking
                  ? null
                  : () async {
                      setDialog(() {
                        invoking = true;
                        output = '正在请求接口…';
                      });
                      try {
                        final res = await AppBridge.call(
                          'AutomationScriptInvokePublicAPI',
                          [
                            {
                              'url': url,
                              'method': 'POST',
                              'bodyText': bodyController.text.trim().isEmpty
                                  ? '{}'
                                  : bodyController.text.trim(),
                              'apiKey': apiKeyController.text.trim(),
                              'authHeader': authHeader,
                              'timeoutMs': timeoutMs,
                            },
                          ],
                        );
                        final map = res is Map
                            ? Map<String, dynamic>.from(res)
                            : <String, dynamic>{};
                        final bodyText = _prettyJson('${map['bodyText'] ?? ''}');
                        if (context.mounted) {
                          setDialog(() {
                            output =
                                'HTTP ${map['status'] ?? ''} ${map['statusText'] ?? ''}\n$bodyText';
                          });
                        }
                      } catch (error) {
                        if (context.mounted) {
                          setDialog(() => output = error.toString());
                        }
                      } finally {
                        if (context.mounted) {
                          setDialog(() => invoking = false);
                        }
                      }
                    },
              icon: invoking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: PrismProgressIndicator(size: 14),
                    )
                  : const PrismGlyph(AntGlyphs.play, size: 15),
              label: Text(invoking ? '调用中…' : '测试调用'),
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
  bodyController.dispose();
  apiKeyController.dispose();
}

/// 自动化脚本运行弹窗（支持目标选择、Public API 变量替换、按 Code 码启动、结构化结果面板与输出目录打开）。
class AutomationScriptRunModal extends StatefulWidget {
  const AutomationScriptRunModal({
    super.key,
    required this.script,
    required this.profiles,
    this.onCompleted,
  });

  final Map<String, dynamic> script;
  final List<Map<String, dynamic>> profiles;
  final VoidCallback? onCompleted;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> script,
    required List<Map<String, dynamic>> profiles,
    VoidCallback? onCompleted,
  }) {
    return showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AutomationScriptRunModal(
        script: script,
        profiles: profiles,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<AutomationScriptRunModal> createState() =>
      _AutomationScriptRunModalState();
}

class _AutomationScriptRunModalState extends State<AutomationScriptRunModal> {
  late final String _targetMode;
  String? _selectedProfileId;
  late final TextEditingController _launchCode;
  late final TextEditingController _params;
  bool _startByCodeBeforeRun = true;
  late final List<Map<String, dynamic>> _variables;
  final Map<String, TextEditingController> _varControllers = {};

  bool _running = false;
  Map<String, dynamic>? _result;
  String _runError = '';

  @override
  void initState() {
    super.initState();
    final targetConfig = _tryDecodeMap(widget.script['targetConfig']);
    final storedMode = '${targetConfig['mode'] ?? 'manual'}';
    _targetMode = storedMode == 'existing' ? 'manual' : storedMode;

    final selector = _tryDecodeMap(widget.script['selectorText']);
    final targetSelector = _tryDecodeMap(targetConfig['selector']);
    final initProfileId =
        '${selector['profileId'] ?? targetSelector['profileId'] ?? ''}'.trim();
    if (initProfileId.isNotEmpty &&
        widget.profiles.any((p) => '${p['profileId']}' == initProfileId)) {
      _selectedProfileId = initProfileId;
    }

    final resolvedCode = _resolveLaunchCode(widget.script, widget.profiles);
    _launchCode = TextEditingController(text: resolvedCode);
    _params = TextEditingController(
      text: '${widget.script['paramsText'] ?? '{}'}',
    );

    final publicApi = _tryDecodeMap(widget.script['publicAPI']);
    _variables = _parseVariables(publicApi['variables']);
    for (final v in _variables) {
      final name = '${v['name'] ?? ''}'.trim();
      if (name.isNotEmpty) {
        _varControllers[name] = TextEditingController(
          text: '${v['defaultValue'] ?? ''}',
        );
      }
    }
  }

  @override
  void dispose() {
    _launchCode.dispose();
    _params.dispose();
    for (final c in _varControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _resolvedParamsText() {
    var text = _params.text;
    for (final entry in _varControllers.entries) {
      text = text.replaceAll('{{${entry.key}}}', entry.value.text);
    }
    return text;
  }

  Future<void> _execute() async {
    final scriptId = '${widget.script['id'] ?? ''}'.trim();
    if (scriptId.isEmpty) {
      showPrismNotice(context, '请先保存脚本后再运行');
      return;
    }
    if ('${widget.script['status'] ?? ''}' == 'disabled') {
      showPrismNotice(context, '该脚本已禁用，无法运行');
      return;
    }

    for (final v in _variables) {
      final name = '${v['name'] ?? ''}'.trim();
      if (v['required'] == true &&
          name.isNotEmpty &&
          (_varControllers[name]?.text.trim() ?? '').isEmpty) {
        showPrismNotice(context, '请填写必填变量：$name');
        return;
      }
    }

    Map<String, dynamic>? selectedProfile;
    if (_selectedProfileId != null) {
      for (final p in widget.profiles) {
        if ('${p['profileId']}' == _selectedProfileId) {
          selectedProfile = p;
          break;
        }
      }
    }

    final manualCode = _launchCode.text.trim().toUpperCase();
    final effectiveCode = manualCode.isNotEmpty
        ? manualCode
        : '${selectedProfile?['launchCode'] ?? ''}'.trim().toUpperCase();

    final hasStoredSelector =
        '${widget.script['selectorText'] ?? ''}'.trim().isNotEmpty &&
        '${widget.script['selectorText'] ?? ''}'.trim() != '{}';

    if (_targetMode == 'manual' &&
        selectedProfile == null &&
        effectiveCode.isEmpty &&
        scriptId != _dualInstanceScriptId &&
        !hasStoredSelector) {
      showPrismNotice(context, '请先选择目标实例或填写启动码（Code 码）');
      return;
    }

    setState(() {
      _running = true;
      _result = null;
      _runError = '';
    });

    try {
      if (_targetMode == 'manual' &&
          _startByCodeBeforeRun &&
          effectiveCode.isNotEmpty) {
        final alreadyRunning =
            selectedProfile != null && selectedProfile['running'] == true;
        if (!alreadyRunning) {
          await AppBridge.call('BrowserInstanceStartByCode', [effectiveCode]);
        }
      }

      String selectorText = '${widget.script['selectorText'] ?? ''}';
      if (_targetMode == 'manual') {
        if (selectedProfile != null || effectiveCode.isNotEmpty) {
          final selectorMap = <String, dynamic>{
            if (selectedProfile != null)
              'profileId': selectedProfile['profileId'],
            if (selectedProfile != null)
              'profileName': selectedProfile['profileName'],
            if (effectiveCode.isNotEmpty) 'code': effectiveCode,
          };
          selectorText = jsonEncode(selectorMap);
        }
      }

      final targetConfig = _tryDecodeMap(widget.script['targetConfig']);
      final targetInput = _targetMode == 'create'
          ? {
              'templateSelector': targetConfig['templateSelector'] ?? {},
              if ('${targetConfig['createNameTemplate'] ?? ''}'
                  .trim()
                  .isNotEmpty)
                'createNameTemplate': targetConfig['createNameTemplate'],
            }
          : _targetMode == 'rotate'
          ? _tryDecodeMap(targetConfig['selector'])
          : <String, dynamic>{};

      final res = await AppBridge.call('AutomationScriptRunWithOptions', [
        {
          'scriptId': scriptId,
          'selectorText': _targetMode != 'manual' ? '' : selectorText,
          'targetMode': _targetMode,
          if (_targetMode != 'manual') 'targetInput': targetInput,
          'paramsText': _resolvedParamsText(),
          if (effectiveCode.isNotEmpty) 'launchCode': effectiveCode,
          'startByCodeBeforeRun': _startByCodeBeforeRun,
          'useScriptSelector':
              _targetMode != 'manual' ||
              (selectedProfile == null && effectiveCode.isEmpty),
          'useScriptParams': false,
        },
      ]);
      if (!mounted) return;
      setState(() {
        _result = res is Map ? Map<String, dynamic>.from(res) : {'raw': res};
      });
      widget.onCompleted?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _runError = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _openOutputPath(String path) async {
    try {
      await AppBridge.call('OpenCorePath', [path]);
    } catch (error) {
      if (mounted) showPrismNotice(context, '打开路径失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final scriptName =
        '${widget.script['name'] ?? widget.script['id'] ?? '运行脚本'}';
    final result = _result;
    final resultText = '${result?['resultText'] ?? ''}'.trim();
    final formattedResult = _prettyJson(resultText);
    final logText = '${result?['logText'] ?? ''}'.trim();
    final summary = '${result?['summary'] ?? ''}'.trim();
    final errorMsg = '${result?['error'] ?? _runError}'.trim();
    final status = _running
        ? 'running'
        : result != null
        ? '${result['status'] ?? 'success'}'
        : _runError.isNotEmpty
        ? 'failed'
        : '';
    final outputPaths = resultText.isEmpty
        ? const <String>[]
        : _extractOutputPaths(resultText);

    return PrismDialog(
      title: Text('运行脚本 · $scriptName'),
      content: SizedBox(
        width: 780,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_targetMode == 'manual') ...[
                PrismDropdownField<String>(
                  value: _selectedProfileId,
                  decoration: const PrismInputDecoration(
                    labelText: '目标浏览器实例',
                    hintText: '选择实例（或下方手动输入启动码）',
                  ),
                  items: [
                    for (final p in widget.profiles)
                      PrismDropdownItem(
                        value: '${p['profileId'] ?? ''}',
                        child: Text(
                          '${p['profileName'] ?? '未命名实例'}'
                          '${'${p['launchCode'] ?? ''}'.trim().isNotEmpty ? ' · ${p['launchCode']}' : ''}'
                          '${p['running'] == true ? ' · 运行中' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _running
                      ? null
                      : (value) {
                          setState(() {
                            _selectedProfileId = value;
                            for (final p in widget.profiles) {
                              if ('${p['profileId']}' == value) {
                                final code = '${p['launchCode'] ?? ''}'.trim();
                                if (code.isNotEmpty) {
                                  _launchCode.text = code;
                                }
                                break;
                              }
                            }
                          });
                        },
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: PrismTextField(
                        controller: _launchCode,
                        enabled: !_running,
                        decoration: const PrismInputDecoration(
                          labelText: '手动启动码（Code 码）',
                          hintText: '如 BUYER_001，留空使用所选实例默认码',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrismSwitchTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('运行前按 Code 码启动'),
                        subtitle: const Text('若实例未运行则先自动拉起'),
                        value: _startByCodeBeforeRun,
                        onChanged: _running
                            ? null
                            : (v) => setState(() => _startByCodeBeforeRun = v),
                      ),
                    ),
                  ],
                ),
              ] else
                PrismBanner(
                  tone: PrismTone.info,
                  message: _targetMode == 'create'
                      ? '当前脚本使用“按模板新建实例”模式，运行时将自动创建新实例。'
                      : '当前脚本使用“按条件轮询实例”模式，运行时将按条件自动匹配实例。',
                ),
              if (_variables.isNotEmpty) ...[
                const SizedBox(height: 12),
                PrismSectionCard(
                  title: '变量参数（替换 {{变量名}}）',
                  glyph: AntGlyphs.tune,
                  padding: const EdgeInsets.all(12),
                  staggerIndex: 0,
                  staggerDelay: const Duration(milliseconds: 45),
                  child: Column(
                    children: [
                      for (final v in _variables)
                        if ('${v['name'] ?? ''}'.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: PrismTextField(
                              controller:
                                  _varControllers['${v['name']}'.trim()],
                              enabled: !_running,
                              decoration: PrismInputDecoration(
                                labelText:
                                    '${v['name']}${v['required'] == true ? ' *' : ''}',
                                hintText:
                                    '${v['description'] ?? ''}'.trim().isNotEmpty
                                    ? '${v['description']}'
                                    : '默认值：${v['defaultValue'] ?? ''}',
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              PrismTextField(
                controller: _params,
                enabled: !_running,
                minLines: 3,
                maxLines: 8,
                decoration: const PrismInputDecoration(
                  labelText: '运行参数 JSON',
                  helperText: '支持使用 {{变量名}} 占位符，运行时将自动替换为上方变量值。',
                ),
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 14),
                PrismSectionCard(
                  title: '执行结果',
                  glyph: AntGlyphs.factCheck,
                  staggerIndex: 1,
                  staggerDelay: const Duration(milliseconds: 45),
                  actions: [
                    PrismBadge(
                      label: status == 'success'
                          ? '成功'
                          : status == 'running'
                          ? '运行中'
                          : '失败',
                      tone: status == 'success'
                          ? PrismTone.success
                          : status == 'running'
                          ? PrismTone.info
                          : PrismTone.danger,
                      dot: true,
                    ),
                    if (result != null)
                      PrismBadge(
                        label: _formatDuration(result['durationMs']),
                        glyph: AntGlyphs.schedule,
                        tone: PrismTone.neutral,
                      ),
                    if (logText.isNotEmpty)
                      prism.OutlinedButton.icon(
                        onPressed: () => _showLogViewerDialog(
                          context,
                          title: scriptName,
                          logText: logText,
                        ),
                        icon: const PrismGlyph(AntGlyphs.logs, size: 14),
                        label: const Text('查看日志'),
                      ),
                    if (formattedResult.isNotEmpty)
                      prism.OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: formattedResult),
                          );
                          showPrismNotice(context, '已复制运行结果');
                        },
                        icon: const PrismGlyph(AntGlyphs.copy, size: 14),
                        label: const Text('复制结果'),
                      ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_running)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PrismProgressIndicator(size: 18),
                              SizedBox(width: 10),
                              Text('正在执行自动化脚本，请稍候…'),
                            ],
                          ),
                        ),
                      if (summary.isNotEmpty) ...[
                        Text(
                          summary,
                          style: prism.AppTextStyle.subheadline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (errorMsg.isNotEmpty) ...[
                        PrismBanner(
                          tone: PrismTone.danger,
                          title: '执行失败',
                          message: errorMsg,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (outputPaths.isNotEmpty) ...[
                        Text(
                          '输出文件',
                          style: prism.AppTextStyle.footnote
                              .of(context, emphasized: true)
                              .copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        for (final path in outputPaths)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: prism.Surface(
                              color: colors.surfaceContainerLow,
                              shape: prism.AppShape.md,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    const PrismGlyph(
                                      AntGlyphs.folder,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: prism.SelectableText(
                                        path,
                                        style: const TextStyle(
                                          fontFamily: 'Consolas',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    prism.OutlinedButton.icon(
                                      onPressed: () => _openOutputPath(path),
                                      icon: const PrismGlyph(
                                        AntGlyphs.openInNew,
                                        size: 13,
                                      ),
                                      label: const Text('打开文件夹'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                      if (formattedResult.isNotEmpty)
                        PrismCodeSurface(
                          code: formattedResult,
                          language: 'json',
                          maxHeight: 200,
                          showCopy: true,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        prism.FilledButton.icon(
          onPressed: _running ? null : _execute,
          icon: _running
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: PrismProgressIndicator(size: 14),
                )
              : const PrismGlyph(AntGlyphs.play, size: 15),
          label: Text(_running ? '运行中…' : '开始运行'),
        ),
        prism.TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class AutomationPage extends StatefulWidget {
  const AutomationPage({
    super.key,
    required this.onOpen,
    required this.onRun,
    required this.onCreate,
  });
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onRun;
  final VoidCallback onCreate;
  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<AutomationPage> {
  List<Map<String, dynamic>> _scripts = [];
  List<Map<String, dynamic>> _runs = [];
  List<Map<String, dynamic>> _profiles = [];
  String _launchBaseUrl = 'http://127.0.0.1:19876';
  String _apiAuthHeader = 'X-Ant-Api-Key';
  bool _apiAuthEnabled = false;
  final Set<String> _selectedScriptIds = {};
  final _searchController = TextEditingController();
  String _modeFilter = 'all';
  bool _loading = true;
  String _busy = '';

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

  List<Map<String, dynamic>> _filteredScripts() {
    final query = _searchController.text.trim().toLowerCase();
    return _scripts.where((script) {
      final interfaceMode = _isInterfaceMode(script);
      final status = '${script['status'] ?? 'draft'}';
      final matchesMode = switch (_modeFilter) {
        'script' => !interfaceMode,
        'api' => interfaceMode,
        'ready' => status == 'ready',
        _ => true,
      };
      if (!matchesMode) return false;
      if (query.isEmpty) return true;
      final name = '${script['name'] ?? ''}'.toLowerCase();
      final desc = '${script['description'] ?? ''}'.toLowerCase();
      final id = '${script['id'] ?? ''}'.toLowerCase();
      final code = _resolveLaunchCode(script, _profiles).toLowerCase();
      return name.contains(query) ||
          desc.contains(query) ||
          id.contains(query) ||
          code.contains(query);
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final result = await Future.wait([
        AppBridge.call('AutomationScriptList'),
        AppBridge.call('AutomationScriptRunList', [100]),
        AppBridge.call('BrowserProfileList').catchError((_) => const []),
        AppBridge.call('GetLaunchServerInfo').catchError((_) => const {}),
      ]);
      final loadedScripts = (result[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      loadedScripts.sort((a, b) {
        final aPinned = '${a['id'] ?? ''}' == _dualInstanceScriptId ? 0 : 1;
        final bPinned = '${b['id'] ?? ''}' == _dualInstanceScriptId ? 0 : 1;
        if (aPinned != bPinned) return aPinned - bPinned;
        return 0;
      });
      _scripts = loadedScripts;
      _runs = (result[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _profiles = (result[2] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final serverInfo = _tryDecodeMap(result[3]);
      final baseUrl = '${serverInfo['baseUrl'] ?? ''}'.trim();
      if (baseUrl.isNotEmpty) {
        _launchBaseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
      }
      final apiAuth = _tryDecodeMap(serverInfo['apiAuth']);
      final header = '${apiAuth['header'] ?? ''}'.trim();
      if (header.isNotEmpty) _apiAuthHeader = header;
      _apiAuthEnabled = apiAuth['enabled'] == true;
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openRunModal(Map<String, dynamic> script) async {
    if ('${script['status'] ?? ''}' == 'disabled') {
      showPrismNotice(context, '该脚本已禁用，请先在详情页启用后再运行');
      return;
    }
    await AutomationScriptRunModal.show(
      context,
      script: script,
      profiles: _profiles,
      onCompleted: _refresh,
    );
  }

  Future<void> _import(String mode) async {
    if (mode == 'remote' || mode == 'git') {
      await _importFromSource(mode);
      return;
    }
    if (mode == 'text') {
      await _importFromText();
      return;
    }
    setState(() => _busy = mode);
    try {
      if (mode == 'library') {
        await AppBridge.call('AutomationScriptImportLocalLibrary');
      } else {
        await AppBridge.call(
          mode == 'directory'
              ? 'AutomationScriptImportLocalDirectory'
              : 'AutomationScriptImportLocalFile',
        );
      }
      await _refresh();
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _importFromText() async {
    final input = TextEditingController();
    final text = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('粘贴文本导入'),
        content: SizedBox(
          width: 520,
          child: PrismTextField(
            controller: input,
            minLines: 8,
            maxLines: 16,
            decoration: const PrismInputDecoration(
              labelText: '脚本 JSON 文本',
              hintText: '粘贴脚本包 JSON 内容（automation-template 格式）',
            ),
          ),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    input.dispose();
    if (text == null || text.trim().isEmpty) return;
    setState(() => _busy = 'text');
    try {
      await AppBridge.call('AutomationScriptImportText', [text]);
      await _refresh();
      if (mounted) showPrismNotice(context, '文本导入完成');
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _importFromSource(String mode) async {
    final url = TextEditingController();
    final ref = TextEditingController(text: 'main');
    final scriptPath = TextEditingController();
    final values = await showPrismDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text(mode == 'git' ? '从 Git 仓库导入' : '从网址导入'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismTextField(
                controller: url,
                decoration: PrismInputDecoration(
                  labelText: mode == 'git' ? 'Git 仓库地址' : '脚本网址',
                ),
              ),
              if (mode == 'git') ...[
                const SizedBox(height: 10),
                PrismTextField(
                  controller: ref,
                  decoration: const PrismInputDecoration(labelText: '分支或标签'),
                ),
                const SizedBox(height: 10),
                PrismTextField(
                  controller: scriptPath,
                  decoration: const PrismInputDecoration(
                    labelText: '脚本目录（可留空）',
                  ),
                ),
              ],
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
              url.text.trim(),
              ref.text.trim(),
              scriptPath.text.trim(),
            ]),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    final selectedValues = values ?? const <String>[];
    final source = selectedValues.isEmpty ? '' : selectedValues.first;
    url.dispose();
    ref.dispose();
    scriptPath.dispose();
    if (source.isEmpty || (mode == 'git' && selectedValues.length < 3)) return;
    setState(() => _busy = mode);
    try {
      await AppBridge.call(
        mode == 'git'
            ? 'AutomationScriptImportGit'
            : 'AutomationScriptImportRemote',
        mode == 'git'
            ? [source, selectedValues[1], selectedValues[2]]
            : [source],
      );
      await _refresh();
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _deleteScript(String id, String name) async {
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除脚本？'),
        destructive: true,
        content: Text('将删除“$name”及其本地文件。'),
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
    setState(() => _busy = id);
    try {
      await AppBridge.call('AutomationScriptDelete', [id]);
      await _refresh();
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _exportScript(String id, String format) async {
    try {
      final method = switch (format) {
        'json' => 'AutomationScriptExport',
        'directory' => 'AutomationScriptExportDirectory',
        _ => 'AutomationScriptExportZip',
      };
      final result = await AppBridge.call(method, [id]);
      final message = result is Map ? result['message'] : null;
      if (mounted && message != null) {
        showPrismNotice(context, message.toString());
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    }
  }

  Future<void> _exportSelectedScripts() async {
    final ids = _selectedScriptIds.toList();
    if (ids.isEmpty) return;
    setState(() => _busy = 'export');
    try {
      final result = await AppBridge.call('AutomationScriptExportBatchZip', [
        ids,
      ]);
      final value = result is Map ? result['message'] : null;
      if (mounted) {
        showPrismNotice(context, (value ?? '已导出 ${ids.length} 个脚本').toString());
        setState(() => _selectedScriptIds.clear());
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _showRunDetails(Map<String, dynamic> run) async {
    final success = run['status'] == 'success';
    final logText = '${run['logText'] ?? ''}'.trim();
    final resultText = _prettyJson('${run['resultText'] ?? ''}');
    final errorText = '${run['error'] ?? ''}'.trim();
    final summary = '${run['summary'] ?? ''}'.trim();
    final scriptTitle =
        '${run['scriptName'] ?? run['scriptId'] ?? '运行记录'}';

    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text(scriptTitle),
        content: SizedBox(
          width: 720,
          height: 520,
          child: ListView(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PrismBadge(
                    label: success
                        ? '成功'
                        : run['status'] == 'running'
                        ? '运行中'
                        : '失败',
                    tone: success
                        ? PrismTone.success
                        : run['status'] == 'running'
                        ? PrismTone.info
                        : PrismTone.danger,
                    dot: true,
                  ),
                  PrismBadge(
                    label: '耗时 ${_formatDuration(run['durationMs'])}',
                    glyph: AntGlyphs.schedule,
                  ),
                  if ('${run['id'] ?? ''}'.trim().isNotEmpty)
                    PrismBadge(
                      label: '记录 ID：${run['id']}',
                      tone: PrismTone.neutral,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '开始时间：${_formatDateTime(run['startedAt'])} · 结束时间：${_formatDateTime(run['finishedAt'])}',
                style: prism.AppTextStyle.footnote.of(context),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                PrismBanner(
                  tone: PrismTone.info,
                  title: '详细摘要',
                  message: summary,
                ),
              ],
              if (errorText.isNotEmpty) ...[
                const SizedBox(height: 10),
                PrismBanner(
                  tone: PrismTone.danger,
                  title: '错误信息',
                  message: errorText,
                ),
              ],
              if (resultText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '运行结果',
                  style: prism.AppTextStyle.footnote.of(
                    context,
                    emphasized: true,
                  ),
                ),
                const SizedBox(height: 6),
                PrismCodeSurface(
                  code: resultText,
                  language: 'json',
                  maxHeight: 220,
                  showCopy: true,
                ),
              ],
              if (logText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '执行日志',
                        style: prism.AppTextStyle.footnote.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    prism.OutlinedButton.icon(
                      onPressed: () => _showLogViewerDialog(
                        context,
                        title: scriptTitle,
                        logText: logText,
                      ),
                      icon: const PrismGlyph(AntGlyphs.logs, size: 14),
                      label: const Text('独立窗口查看日志'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                PrismCodeSurface(
                  code: logText,
                  language: 'log',
                  maxHeight: 160,
                  showCopy: true,
                ),
              ],
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

  Future<void> _showHistory() async {
    var runs = List<Map<String, dynamic>>.from(_runs);
    var refreshing = false;
    var expandedId = '';
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          final colors = prism.Theme.of(context).colorScheme;
          final successful = runs
              .where((run) => run['status'] == 'success')
              .length;
          final failed = runs.where((run) => run['status'] == 'failed').length;
          final scriptCount = runs
              .map((run) => (run['scriptId'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toSet()
              .length;
          return PrismDialog(
            title: const Text('脚本调用记录'),
            content: SizedBox(
              width: 940,
              height: 620,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '共 ${runs.length} 条记录 · 覆盖 $scriptCount 个脚本',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: prism.AppTextStyle.subheadline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      prism.OutlinedButton.icon(
                        onPressed: refreshing
                            ? null
                            : () async {
                                setDialog(() => refreshing = true);
                                try {
                                  final value = await AppBridge.call(
                                    'AutomationScriptRunList',
                                    [200],
                                  );
                                  if (context.mounted) {
                                    setDialog(() {
                                      runs = (value as List? ?? [])
                                          .whereType<Map>()
                                          .map(
                                            (row) =>
                                                Map<String, dynamic>.from(row),
                                          )
                                          .toList();
                                      _runs = runs;
                                    });
                                  }
                                } catch (error) {
                                  if (context.mounted) {
                                    showPrismNotice(context, '刷新调用记录失败：$error');
                                  }
                                } finally {
                                  if (context.mounted) {
                                    setDialog(() => refreshing = false);
                                  }
                                }
                              },
                        icon: refreshing
                            ? const SizedBox.square(
                                dimension: 15,
                                child: PrismProgressIndicator(size: 15),
                              )
                            : const PrismGlyph(AntGlyphs.refresh, size: 15),
                        label: const Text('刷新'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: PrismMetricTile(
                          label: '成功次数',
                          value: '$successful',
                          glyph: AntGlyphs.checkCircle,
                          tone: PrismTone.success,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PrismMetricTile(
                          label: '失败次数',
                          value: '$failed',
                          glyph: AntGlyphs.error,
                          tone: PrismTone.danger,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PrismMetricTile(
                          label: '最近调用',
                          value: runs.isEmpty
                              ? '暂无'
                              : _formatDateTime(runs.first['startedAt']),
                          glyph: AntGlyphs.schedule,
                          tone: PrismTone.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: runs.isEmpty
                        ? const PrismEmptyState(
                            glyph: AntGlyphs.history,
                            title: '还没有调用记录',
                            subtitle: '运行任意脚本或调用对外 API 后会在这里展示记录',
                          )
                        : ListView.builder(
                            padding: kPrismListPadding,
                            itemCount: runs.length,
                            itemBuilder: (context, index) {
                              final run = runs[index];
                              final id = (run['id'] ?? '').toString();
                              final expanded =
                                  id.isNotEmpty && expandedId == id;
                              final success = run['status'] == 'success';
                              final isRunning = run['status'] == 'running';
                              final summary = '${run['summary'] ?? ''}'.trim();
                              final errorMsg = '${run['error'] ?? ''}'.trim();
                              final logText = '${run['logText'] ?? ''}'.trim();
                              final resultText = _prettyJson(
                                '${run['resultText'] ?? ''}',
                              );
                              final statusTone = success
                                  ? PrismTone.success
                                  : isRunning
                                  ? PrismTone.info
                                  : PrismTone.danger;
                              final statusColors = PrismToneColors.of(
                                context,
                                statusTone,
                              );
                              return PrismCard(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  children: [
                                    PrismListTile(
                                      onTap: () => setDialog(
                                        () => expandedId = expanded ? '' : id,
                                      ),
                                      leading: PrismGlyph(
                                        success
                                            ? AntGlyphs.checkCircle
                                            : isRunning
                                            ? AntGlyphs.pending
                                            : AntGlyphs.error,
                                        size: 18,
                                        color: statusColors.fg,
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              (run['scriptName'] ??
                                                      run['scriptId'] ??
                                                      '未命名脚本')
                                                  .toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: prism
                                                  .AppTextStyle
                                                  .subheadline
                                                  .of(
                                                    context,
                                                    emphasized: true,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          PrismBadge(
                                            label: _formatDuration(
                                              run['durationMs'],
                                            ),
                                            tone: PrismTone.neutral,
                                          ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        '${_formatDateTime(run['startedAt'])}'
                                        '${id.isNotEmpty ? ' · ID: $id' : ''}\n'
                                        '${summary.isNotEmpty ? summary : errorMsg}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      isThreeLine: true,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          if (logText.isNotEmpty) ...[
                                            prism.OutlinedButton.icon(
                                              onPressed: () =>
                                                  _showLogViewerDialog(
                                                    context,
                                                    title:
                                                        '${run['scriptName'] ?? run['scriptId'] ?? ''}',
                                                    logText: logText,
                                                  ),
                                              icon: const PrismGlyph(
                                                AntGlyphs.logs,
                                                size: 14,
                                              ),
                                              label: const Text('执行日志'),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          PrismGlyph(
                                            expanded
                                                ? AntGlyphs.chevronUp
                                                : AntGlyphs.chevronDown,
                                            size: 16,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (expanded)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          14,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const prism.Divider(height: 1),
                                            const SizedBox(height: 10),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              children: [
                                                PrismBadge(
                                                  label: '记录 ID：${id.isEmpty ? '-' : id}',
                                                  tone: PrismTone.neutral,
                                                ),
                                                PrismBadge(
                                                  label:
                                                      '类型：${run['scriptType'] ?? '-'}',
                                                  tone: PrismTone.info,
                                                ),
                                                PrismBadge(
                                                  label:
                                                      '耗时：${_formatDuration(run['durationMs'])}',
                                                  tone: PrismTone.neutral,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '开始：${_formatDateTime(run['startedAt'])} · '
                                              '结束：${_formatDateTime(run['finishedAt'])}',
                                              style: prism
                                                  .AppTextStyle
                                                  .caption1
                                                  .of(context)
                                                  .copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                            ),
                                            if (summary.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              PrismBanner(
                                                tone: PrismTone.info,
                                                title: '详细摘要',
                                                message: summary,
                                              ),
                                            ],
                                            if (errorMsg.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              PrismBanner(
                                                tone: PrismTone.danger,
                                                title: '错误信息',
                                                message: errorMsg,
                                              ),
                                            ],
                                            if (resultText.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              PrismCodeSurface(
                                                code: resultText,
                                                language: 'json',
                                                maxHeight: 160,
                                                showCopy: true,
                                              ),
                                            ],
                                          ],
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
  }

  Widget _buildScriptCard(
    BuildContext context,
    Map<String, dynamic> script, {
    int index = 0,
  }) {
    final colors = prism.Theme.of(context).colorScheme;
    final id = '${script['id'] ?? ''}';
    final name = '${script['name'] ?? '未命名脚本'}';
    final desc = '${script['description'] ?? ''}'.trim();
    final status = '${script['status'] ?? 'draft'}';
    final isDisabled = status == 'disabled';
    final isLaunchApi = '${script['type'] ?? ''}' == 'launch-api';
    final interfaceMode = _isInterfaceMode(script);
    final launchCode = _resolveLaunchCode(script, _profiles);
    final versionTime = _formatVersionTime(
      script['updatedAt'] ?? script['createdAt'],
    );
    final pinned = id == _dualInstanceScriptId;

    return PrismHoverCard(
      staggerIndex: index.clamp(0, 6),
      staggerDelay: const Duration(milliseconds: 35),
      radius: prism.AppCorner.xl,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                prism.Checkbox(
                  value: _selectedScriptIds.contains(id),
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      _selectedScriptIds.add(id);
                    } else {
                      _selectedScriptIds.remove(id);
                    }
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: prism.PressRegion(
                    onTap: () => widget.onOpen(id),
                    shape: prism.AppShape.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (pinned)
                              const PrismBadge(
                                label: '置顶',
                                glyph: AntGlyphs.pin,
                                tone: PrismTone.primary,
                              ),
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: prism.AppTextStyle.headline.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                            PrismBadge(
                              label: interfaceMode ? '接口模式' : '脚本模式',
                              glyph: interfaceMode
                                  ? AntGlyphs.api
                                  : AntGlyphs.code,
                              tone: interfaceMode
                                  ? PrismTone.primary
                                  : PrismTone.info,
                            ),
                            PrismBadge(
                              label: _statusLabel(status),
                              tone: _statusTone(status),
                              dot: true,
                            ),
                            if (launchCode.isNotEmpty)
                              PrismBadge(
                                label: 'Code 码：$launchCode',
                                glyph: AntGlyphs.bolt,
                                tone: PrismTone.neutral,
                              ),
                            if (versionTime.isNotEmpty)
                              PrismBadge(
                                label: versionTime,
                                tone: PrismTone.neutral,
                              ),
                          ],
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: prism.AppTextStyle.footnote
                                .of(context)
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PrismPopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'open') {
                      widget.onOpen(id);
                    } else if (action == 'run') {
                      _openRunModal(script);
                    } else if (action.startsWith('export-')) {
                      _exportScript(id, action.substring('export-'.length));
                    } else if (action == 'delete') {
                      _deleteScript(id, name);
                    }
                  },
                  itemBuilder: (_) => [
                    const PrismMenuItem(value: 'open', child: Text('编辑')),
                    if (!isLaunchApi)
                      PrismMenuItem(
                        value: 'run',
                        enabled: !isDisabled,
                        child: const Text('运行脚本'),
                      ),
                    const PrismMenuItem(
                      value: 'export-json',
                      child: Text('导出 JSON 模板'),
                    ),
                    const PrismMenuItem(
                      value: 'export-directory',
                      child: Text('导出目录'),
                    ),
                    const PrismMenuItem(
                      value: 'export-zip',
                      child: Text('导出 ZIP'),
                    ),
                    const PrismMenuItem(
                      value: 'delete',
                      danger: true,
                      child: Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            const prism.Divider(height: 1),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!isLaunchApi)
                  PrismTonalButton.icon(
                    onPressed: isDisabled ? null : () => _openRunModal(script),
                    icon: const PrismGlyph(AntGlyphs.play, size: 14),
                    child: const Text('运行脚本'),
                  ),
                prism.TextButton.icon(
                  onPressed: () => widget.onOpen(id),
                  icon: const PrismGlyph(AntGlyphs.edit, size: 14),
                  label: const Text('编辑'),
                ),
                // 接口调试工具收进菜单，保持卡片操作行克制。
                PrismPopupMenuButton<String>(
                  tooltip: '接口调试',
                  icon: const PrismGlyph(AntGlyphs.api, size: 16),
                  onSelected: (action) {
                    final url = _buildScriptApiUrl(script, _launchBaseUrl);
                    final body = _buildScriptRequestJson(
                      script,
                      launchCode: launchCode,
                    );
                    if (action == 'curl') {
                      final curl = _buildCurlCommand(
                        url: url,
                        bodyJson: body,
                        authHeader: _apiAuthHeader,
                      );
                      Clipboard.setData(ClipboardData(text: curl));
                      showPrismNotice(context, '已复制 cURL 命令');
                    } else if (action == 'json') {
                      Clipboard.setData(ClipboardData(text: body));
                      showPrismNotice(context, '已复制 JSON 请求体');
                    } else if (action == 'api') {
                      _showPublicApiQuickDialog(
                        context,
                        script: script,
                        baseUrl: _launchBaseUrl,
                        authHeader: _apiAuthHeader,
                        authEnabled: _apiAuthEnabled,
                        launchCode: launchCode,
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PrismMenuItem(
                      value: 'curl',
                      child: Text('复制 cURL 命令'),
                    ),
                    PrismMenuItem(
                      value: 'json',
                      child: Text('复制 JSON 请求体'),
                    ),
                    PrismMenuItem(
                      value: 'api',
                      child: Text('接口调试窗口'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
    );
  }

  Widget _buildOverviewStrip(BuildContext context) {
    final readyCount = _scripts
        .where((s) => '${s['status'] ?? 'draft'}' == 'ready')
        .length;
    final draftCount = _scripts.length - readyCount;
    final apiModeCount = _scripts.where(_isInterfaceMode).length;
    final successRuns = _runs.where((r) => r['status'] == 'success').length;
    final failedRuns = _runs.length - successRuns;
    final runningProfiles = _profiles
        .where((p) => p['running'] == true)
        .length;

    final tiles = [
      PrismMetricTile(
        label: '脚本总数',
        value: '${_scripts.length}',
        subtitle: _scripts.isEmpty
            ? '支持 Playwright 与 API 模式'
            : '就绪 $readyCount · 草稿 $draftCount',
        glyph: AntGlyphs.robot,
        tone: PrismTone.primary,
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '接口模式',
        value: '$apiModeCount',
        subtitle: _apiAuthEnabled ? 'API 鉴权已开启' : 'Launch Server 就绪',
        glyph: AntGlyphs.api,
        tone: PrismTone.info,
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '近期运行',
        value: '${_runs.length}',
        subtitle: _runs.isEmpty
            ? '暂无执行记录'
            : '成功 $successRuns · 失败 $failedRuns',
        glyph: AntGlyphs.history,
        tone: failedRuns > 0 ? PrismTone.warning : PrismTone.success,
        onPressed: _showHistory,
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '可用实例',
        value: '${_profiles.length}',
        subtitle: '运行中 $runningProfiles 个',
        glyph: AntGlyphs.browser,
        tone: PrismTone.neutral,
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
                if (i > 0) const SizedBox(width: 12),
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
                const SizedBox(width: 10),
                Expanded(child: tiles[1]),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: tiles[2]),
                const SizedBox(width: 10),
                Expanded(child: tiles[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final filterControl = SizedBox(
      width: 280,
      child: prism.SegmentedControl<String>(
        value: _modeFilter,
        onChanged: (value) => setState(() => _modeFilter = value),
        segments: const [
          ('all', '全部'),
          ('script', '脚本'),
          ('api', '接口'),
          ('ready', '就绪'),
        ],
      ),
    );
    final actionWidgets = <Widget>[
      if (_selectedScriptIds.isNotEmpty)
        PrismTonalButton.icon(
          onPressed: _busy.isEmpty ? _exportSelectedScripts : null,
          icon: const PrismGlyph(AntGlyphs.download, size: 15),
          child: Text('导出 (${_selectedScriptIds.length})'),
        ),
      PrismHoverMotion(
        enabled: _busy.isEmpty,
        child: prism.FilledButton.icon(
          onPressed: _busy.isEmpty ? widget.onCreate : null,
          icon: const PrismGlyph(AntGlyphs.add, size: 15),
          label: const Text('新建脚本'),
        ),
      ),
      PrismPopupMenuButton<String>(
        tooltip: '导入脚本',
        enabled: _busy.isEmpty,
        icon: const PrismGlyph(AntGlyphs.upload, size: 17),
        onSelected: _import,
        itemBuilder: (_) => const [
          PrismMenuItem(value: 'file', child: Text('从文件导入')),
          PrismMenuItem(value: 'directory', child: Text('从文件夹导入')),
          PrismMenuItem(value: 'library', child: Text('导入内置脚本库')),
          PrismMenuItem(value: 'remote', child: Text('从网址导入')),
          PrismMenuItem(value: 'git', child: Text('从 Git 仓库导入')),
          PrismMenuItem(value: 'text', child: Text('粘贴文本导入')),
        ],
      ),
      prism.IconButton(
        tooltip: '刷新',
        onPressed: _refresh,
        icon: const PrismGlyph(AntGlyphs.refresh, size: 17),
      ),
    ];

    return PrismHoverCard(
      staggerIndex: 4,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          if (wide) {
            return Row(
              children: [
                Expanded(
                  child: PrismSearchBar(
                    controller: _searchController,
                    hintText: '搜索脚本名称、说明或启动码…',
                    height: 36,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                filterControl,
                const SizedBox(width: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
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
                      controller: _searchController,
                      hintText: '搜索脚本名称、说明或启动码…',
                      height: 36,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  filterControl,
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actionWidgets,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScriptsSection(
    BuildContext context,
    List<Map<String, dynamic>> filteredScripts,
  ) {
    final queryText = _searchController.text.trim();
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
            info: const prism.Info(label: '脚本列表', glyph: AntGlyphs.code),
            actions: [
              if (_selectedScriptIds.isNotEmpty)
                prism.TextButton(
                  onPressed: () => setState(() => _selectedScriptIds.clear()),
                  child: const Text('取消选择'),
                ),
              PrismBadge(
                label: '${filteredScripts.length} 个',
                tone: filteredScripts.isEmpty
                    ? PrismTone.neutral
                    : PrismTone.primary,
              ),
            ],
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
          ),
          const prism.Divider(height: 1),
          Expanded(
            child: prism.PageTransitionSwitcher(
              duration: PrismMotionSpec.current.pageDuration,
              transitionBuilder: PrismSlideThroughTransition.builder,
              child: KeyedSubtree(
                key: ValueKey(
                  '$_modeFilter-$queryText-${filteredScripts.isEmpty}',
                ),
                child: filteredScripts.isEmpty
                    ? (_scripts.isEmpty
                          ? PrismEmptyState(
                              glyph: AntGlyphs.robot,
                              title: '还没有自动化脚本',
                              subtitle: '创建第一个 Playwright / Launch API 脚本，或直接导入内置脚本库快速上手。',
                              action: Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  PrismHoverMotion(
                                    child: prism.FilledButton.icon(
                                      onPressed: widget.onCreate,
                                      icon: const PrismGlyph(
                                        AntGlyphs.add,
                                        size: 15,
                                      ),
                                      label: const Text('新建脚本'),
                                    ),
                                  ),
                                  PrismHoverMotion(
                                    child: prism.OutlinedButton.icon(
                                      onPressed: _busy.isEmpty
                                          ? () => _import('library')
                                          : null,
                                      icon: const PrismGlyph(
                                        AntGlyphs.download,
                                        size: 15,
                                      ),
                                      label: const Text('导入内置脚本库'),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : PrismEmptyState(
                              glyph: AntGlyphs.search,
                              title: '没有匹配的脚本',
                              subtitle: '尝试调整关键词或切换上方筛选分类。',
                              action: prism.OutlinedButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _modeFilter = 'all');
                                },
                                child: const Text('重置筛选'),
                              ),
                            ))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredScripts.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) => _buildScriptCard(
                          context,
                          filteredScripts[index],
                          index: index,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRunsSection(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final recentRuns = _runs.take(15).toList();
    return PrismHoverCard(
      staggerIndex: 6,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: false,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          prism.InfoHeader(
            info: const prism.Info(label: '最近运行', glyph: AntGlyphs.history),
            actions: [
              prism.TextButton(
                onPressed: _showHistory,
                child: const Text('全部记录'),
              ),
            ],
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
          ),
          const prism.Divider(height: 1),
          Expanded(
            child: recentRuns.isEmpty
                ? const PrismEmptyState(
                    glyph: AntGlyphs.history,
                    title: '暂无运行记录',
                    subtitle: '运行脚本或通过对外接口触发后，调用记录会显示在这里。',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: recentRuns.length,
                    separatorBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: prism.Divider(height: 1),
                    ),
                    itemBuilder: (context, index) {
                      final run = recentRuns[index];
                      final success = run['status'] == 'success';
                      final tone = PrismToneColors.of(
                        context,
                        success ? PrismTone.success : PrismTone.danger,
                      );
                      return PrismListTile(
                        onTap: () => _showRunDetails(run),
                        leading: prism.Surface(
                          color: tone.bg,
                          shape: prism.AppShape.md,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: PrismGlyph(
                              success ? AntGlyphs.checkCircle : AntGlyphs.error,
                              size: 16,
                              color: tone.fg,
                            ),
                          ),
                        ),
                        title: Text(
                          (run['scriptName'] ?? run['scriptId'] ?? '')
                              .toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: prism.AppTextStyle.subheadline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        subtitle: Text(
                          '${_formatDateTime(run['startedAt'])} · '
                          '${_formatDuration(run['durationMs'])}'
                          '${'${run['summary'] ?? run['error'] ?? ''}'.trim().isNotEmpty ? '\n${run['summary'] ?? run['error']}' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: prism.AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: colors.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredScripts = _filteredScripts();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewStrip(context),
          const SizedBox(height: 12),
          _buildToolbar(context),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final scriptsSection = _buildScriptsSection(
                        context,
                        filteredScripts,
                      );
                      final recentRunsSection = _buildRecentRunsSection(
                        context,
                      );
                      if (constraints.maxWidth >= 960) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: scriptsSection),
                            const SizedBox(width: 14),
                            SizedBox(width: 340, child: recentRunsSection),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: scriptsSection),
                          const SizedBox(height: 12),
                          Expanded(flex: 2, child: recentRunsSection),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ApiVarRow {
  _ApiVarRow({
    String name = '',
    String defaultValue = '',
    String description = '',
    this.required = false,
  }) : name = TextEditingController(text: name),
       defaultValue = TextEditingController(text: defaultValue),
       description = TextEditingController(text: description);

  final TextEditingController name;
  final TextEditingController defaultValue;
  final TextEditingController description;
  bool required;

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'defaultValue': defaultValue.text,
    'description': description.text.trim(),
    'required': required,
  };

  void dispose() {
    name.dispose();
    defaultValue.dispose();
    description.dispose();
  }
}

class AutomationScriptDetailPage extends StatefulWidget {
  const AutomationScriptDetailPage({
    super.key,
    required this.scriptId,
    required this.onBack,
    required this.onCreated,
    this.autoRun = false,
  });
  final String scriptId;
  final VoidCallback onBack;
  final ValueChanged<String> onCreated;
  final bool autoRun;
  @override
  State<AutomationScriptDetailPage> createState() =>
      _AutomationScriptDetailPageState();
}

class _AutomationScriptDetailPageState
    extends State<AutomationScriptDetailPage> {
  Map<String, dynamic>? _record;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _groups = [];

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _script = TextEditingController();
  final _selector = TextEditingController();
  final _params = TextEditingController();
  final _apiPath = TextEditingController();
  final _apiKey = TextEditingController();
  final _apiRequest = TextEditingController();
  final _apiResponse = TextEditingController();
  final _apiVariables = TextEditingController(text: '[]');
  final _apiTimeout = TextEditingController(text: '300000');
  final _createNameTemplate = TextEditingController();
  final _targetSelector = TextEditingController(text: '{}');

  // Structured TargetSelectorEditor fields for rotate mode
  final _rotCode = TextEditingController();
  final _rotProfileId = TextEditingController();
  final _rotProfileName = TextEditingController();
  final _rotTags = TextEditingController();
  final _rotKeywords = TextEditingController();
  String _rotGroupId = '';

  final List<_ApiVarRow> _varRows = [];
  int _apiVarEditorMode = 0; // 0 = visual, 1 = JSON
  bool _obscureApiKey = true;

  String _launchBaseUrl = 'http://127.0.0.1:19876';
  String _apiAuthHeader = 'X-Ant-Api-Key';
  bool _apiAuthEnabled = false;

  bool _loading = true;
  bool _apiEnabled = false;
  String _status = 'ready';
  String _apiRequestMode = 'standard';
  String _apiResponseMode = 'envelope';
  String _savedDraftSnapshot = '';
  String _busy = '';
  String _runOutput = '';
  String? _targetProfileId;
  String _targetMode = 'manual';
  String? _templateProfileId;

  bool get _isDirty =>
      !_loading && _savedDraftSnapshot != _draftSnapshot();

  bool get _isLaunchApi => '${_record?['type'] ?? ''}' == 'launch-api';

  @override
  void initState() {
    super.initState();
    for (final c in [
      _name,
      _description,
      _script,
      _selector,
      _params,
      _apiPath,
      _apiRequest,
      _apiResponse,
      _apiVariables,
      _apiTimeout,
      _createNameTemplate,
      _targetSelector,
    ]) {
      c.addListener(_onDraftChanged);
    }
    _load();
  }

  void _onDraftChanged() {
    if (!_loading && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _script,
      _selector,
      _params,
      _apiPath,
      _apiKey,
      _apiRequest,
      _apiResponse,
      _apiVariables,
      _apiTimeout,
      _createNameTemplate,
      _targetSelector,
      _rotCode,
      _rotProfileId,
      _rotProfileName,
      _rotTags,
      _rotKeywords,
    ]) {
      c.dispose();
    }
    for (final row in _varRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _syncVarRowsFromJson() {
    for (final row in _varRows) {
      row.dispose();
    }
    _varRows.clear();
    for (final item in _parseVariables(_apiVariables.text)) {
      _varRows.add(
        _ApiVarRow(
          name: '${item['name'] ?? ''}',
          defaultValue: '${item['defaultValue'] ?? ''}',
          description: '${item['description'] ?? ''}',
          required: item['required'] == true,
        ),
      );
    }
  }

  void _syncJsonFromVarRows() {
    final list = _varRows
        .map((r) => r.toJson())
        .where((m) => '${m['name'] ?? ''}'.isNotEmpty)
        .toList();
    _apiVariables.text = const JsonEncoder.withIndent('  ').convert(list);
  }

  void _syncRotateFieldsFromJson() {
    final map = _tryDecodeMap(_targetSelector.text);
    _rotCode.text = '${map['code'] ?? ''}';
    _rotProfileId.text = '${map['profileId'] ?? ''}';
    _rotProfileName.text = '${map['profileName'] ?? ''}';
    _rotGroupId = '${map['groupId'] ?? ''}';
    _rotTags.text = (map['tags'] is List)
        ? (map['tags'] as List).map((e) => '$e').join(', ')
        : '${map['tags'] ?? ''}';
    _rotKeywords.text = (map['keywords'] is List)
        ? (map['keywords'] as List).map((e) => '$e').join(', ')
        : '${map['keywords'] ?? ''}';
  }

  void _syncRotateJsonFromFields() {
    List<String> splitCsv(String raw) => raw
        .split(RegExp(r'[,，\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final map = <String, dynamic>{};
    if (_rotCode.text.trim().isNotEmpty) map['code'] = _rotCode.text.trim();
    if (_rotProfileId.text.trim().isNotEmpty) {
      map['profileId'] = _rotProfileId.text.trim();
    }
    if (_rotProfileName.text.trim().isNotEmpty) {
      map['profileName'] = _rotProfileName.text.trim();
    }
    if (_rotGroupId.trim().isNotEmpty) map['groupId'] = _rotGroupId.trim();
    final tags = splitCsv(_rotTags.text);
    if (tags.isNotEmpty) map['tags'] = tags;
    final keywords = splitCsv(_rotKeywords.text);
    if (keywords.isNotEmpty) map['keywords'] = keywords;

    _targetSelector.text = const JsonEncoder.withIndent('  ').convert(map);
  }

  void _hydrateFromRecord(Map<String, dynamic> record) {
    _name.text = (record['name'] ?? '').toString();
    _description.text = (record['description'] ?? '').toString();
    _status = '${record['status'] ?? 'draft'}';
    if (!const {'draft', 'ready', 'disabled'}.contains(_status)) {
      _status = 'draft';
    }
    _script.text = (record['scriptText'] ?? '').toString();
    _selector.text = (record['selectorText'] ?? '{}').toString();
    _params.text = (record['paramsText'] ?? '{}').toString();

    final publicApi = _tryDecodeMap(record['publicAPI']);
    _apiEnabled = publicApi['enabled'] == true;
    _apiPath.text = (publicApi['path'] ?? '').toString();
    _apiRequestMode = (publicApi['requestMode'] ?? 'standard').toString();
    _apiResponseMode = (publicApi['responseMode'] ?? 'envelope').toString();
    _apiTimeout.text = (publicApi['timeoutMs'] ?? 300000).toString();
    _apiRequest.text = (publicApi['requestBodyText'] ?? '').toString();
    _apiResponse.text = (publicApi['responseBodyText'] ?? '').toString();
    _apiVariables.text = const JsonEncoder.withIndent('  ')
        .convert(publicApi['variables'] ?? []);
    _syncVarRowsFromJson();

    final targetConfig = _tryDecodeMap(record['targetConfig']);
    final storedMode = (targetConfig['mode'] ?? 'manual').toString();
    _targetMode = storedMode == 'existing' ? 'manual' : storedMode;
    _templateProfileId =
        (targetConfig['templateSelector'] is Map
                ? (targetConfig['templateSelector'] as Map)['profileId']
                : null)
            ?.toString();
    _createNameTemplate.text = (targetConfig['createNameTemplate'] ?? '')
        .toString();
    _targetSelector.text = const JsonEncoder.withIndent('  ').convert(
      targetConfig['selector'] is Map
          ? targetConfig['selector']
          : <String, dynamic>{},
    );
    _syncRotateFieldsFromJson();
  }

  Future<void> _load() async {
    if (widget.scriptId == 'new') {
      _record = <String, dynamic>{
        'id': '',
        'name': '百度搜索示例',
        'description': '启动示例实例，打开百度并搜索关键词，用来验证自动化运行。',
        'type': 'playwright-cdp',
        'status': 'ready',
        'entryFile': 'index.cjs',
        'tags': <String>['Playwright', '示例'],
        'selectorText': '',
        'paramsText':
            '{\n  "url": "https://www.baidu.com",\n  "keyword": "OpenAI",\n  "timeoutMs": 30000\n}',
        'scriptText':
            "module.exports.run = async ({ useBrowser, selector, params, log }) => {\n  const url = params.url || 'https://www.baidu.com'\n  const runtime = await useBrowser({ selector, startUrls: [url], skipDefaultStartUrls: true })\n  const page = runtime.page\n  const keyword = params.keyword || 'OpenAI'\n  const input = page.locator('textarea[name=wd], input[name=wd]').first()\n  await input.fill(keyword)\n  await input.press('Enter')\n  const title = await page.title()\n  log('title', title)\n  return { ok: true, summary: `已搜索 \${keyword}`, url: page.url(), title }\n}",
        'publicAPI': {
          'enabled': false,
          'method': 'POST',
          'path': '',
          'requestMode': 'standard',
          'responseMode': 'envelope',
          'timeoutMs': 300000,
          'requestBodyText': '',
          'responseBodyText': '',
          'variables': <Map<String, dynamic>>[],
        },
        'notes': '',
      };
    } else {
      try {
        final value = await AppBridge.call('AutomationScriptGet', [
          widget.scriptId,
        ]);
        _record = Map<String, dynamic>.from(value as Map);
      } catch (error) {
        _runOutput = error.toString();
      }
    }
    if (_record != null) {
      _hydrateFromRecord(_record!);
    }
    try {
      final results = await Future.wait([
        AppBridge.call('BrowserProfileList').catchError((_) => const []),
        AppBridge.call('ListGroups').catchError((_) => const []),
        AppBridge.call('GetLaunchServerInfo').catchError((_) => const {}),
      ]);
      _profiles = (results[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _groups = (results[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final serverInfo = _tryDecodeMap(results[2]);
      final baseUrl = '${serverInfo['baseUrl'] ?? ''}'.trim();
      if (baseUrl.isNotEmpty) {
        _launchBaseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
      }
      final apiAuth = _tryDecodeMap(serverInfo['apiAuth']);
      final header = '${apiAuth['header'] ?? ''}'.trim();
      if (header.isNotEmpty) _apiAuthHeader = header;
      _apiAuthEnabled = apiAuth['enabled'] == true;

      final selector = _tryDecodeMap(_selector.text);
      if (selector['profileId'] is String) {
        _targetProfileId = selector['profileId'] as String;
      } else {
        final targetConfig = _tryDecodeMap(_record?['targetConfig']);
        final targetSelector = _tryDecodeMap(targetConfig['selector']);
        if (targetSelector['profileId'] is String) {
          _targetProfileId = targetSelector['profileId'] as String;
        }
      }
    } catch (_) {}
    _savedDraftSnapshot = _draftSnapshot();
    if (mounted) {
      setState(() => _loading = false);
      if (widget.autoRun) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openRunModal();
        });
      }
    }
  }

  void _changeNewScriptType(String type) {
    final record = _record;
    if (record == null || widget.scriptId != 'new') return;
    setState(() {
      record['type'] = type;
      record['name'] = type == 'launch-api' ? '新建 Launch API 脚本' : '百度搜索示例';
      record['description'] = type == 'launch-api'
          ? ''
          : '启动示例实例，打开百度并搜索关键词，用来验证 Launch API + Playwright CDP 链路。';
      record['status'] = type == 'launch-api' ? 'draft' : 'ready';
      _status = record['status'].toString();
      record['tags'] = type == 'launch-api' ? ['HTTP'] : ['Playwright', '示例'];
      record['selectorText'] = type == 'launch-api'
          ? '{\n  "code": "BUYER_001"\n}'
          : '';
      record['paramsText'] = type == 'launch-api'
          ? '{\n  "startUrls": ["https://example.com"],\n  "skipDefaultStartUrls": true\n}'
          : '{\n  "url": "https://www.baidu.com",\n  "keyword": "OpenAI",\n  "timeoutMs": 30000,\n  "waitAfterSearchMs": 1500,\n  "captureScreenshot": true\n}';
      record['scriptText'] = type == 'launch-api'
          ? "export async function run({ baseUrl, apiKey, selector, params }) {\n  const response = await fetch(`${r'${baseUrl}'}/api/launch`, {\n    method: 'POST',\n    headers: { 'Content-Type': 'application/json', ...(apiKey ? { 'X-Ant-Api-Key': apiKey } : {}) },\n    body: JSON.stringify({ selector, ...(params || {}) }),\n  })\n  if (!response.ok) throw new Error(`launch failed: ${r'${response.status}'}`)\n  return await response.json()\n}"
          : "module.exports.run = async ({ useBrowser, selector, params, log }) => {\n  const url = params.url || 'https://www.baidu.com'\n  const runtime = await useBrowser({ selector, startUrls: [url], skipDefaultStartUrls: true })\n  const page = runtime.page\n  const keyword = params.keyword || 'OpenAI'\n  const input = page.locator('textarea[name=wd], input[name=wd]').first()\n  await input.fill(keyword)\n  await input.press('Enter')\n  const title = await page.title()\n  log('title', title)\n  return { ok: true, summary: `已搜索 \${keyword}`, url: page.url(), title }\n}";
      _name.text = record['name'].toString();
      _description.text = record['description'].toString();
      _selector.text = record['selectorText'].toString();
      _params.text = record['paramsText'].toString();
      _script.text = record['scriptText'].toString();
    });
  }

  String _draftSnapshot() => jsonEncode({
    'type': _record?['type'],
    'status': _status,
    'name': _name.text,
    'description': _description.text,
    'script': _script.text,
    'selector': _selector.text,
    'params': _params.text,
    'targetMode': _targetMode,
    'targetProfileId': _targetProfileId,
    'templateProfileId': _templateProfileId,
    'createNameTemplate': _createNameTemplate.text,
    'targetSelector': _targetSelector.text,
    'apiEnabled': _apiEnabled,
    'apiPath': _apiPath.text,
    'apiRequestMode': _apiRequestMode,
    'apiResponseMode': _apiResponseMode,
    'apiTimeout': _apiTimeout.text,
    'apiRequest': _apiRequest.text,
    'apiResponse': _apiResponse.text,
    'apiVariables': _apiVariables.text,
  });

  Future<void> _leavePage() async {
    if (_savedDraftSnapshot == _draftSnapshot()) {
      widget.onBack();
      return;
    }
    final leave = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('有未保存的修改'),
        content: const Text('离开后，这些脚本修改会丢失。仍要离开吗？'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改并离开'),
          ),
        ],
      ),
    );
    if (leave == true) widget.onBack();
  }

  Future<void> _showParamsHelp() async {
    const exampleJson = '''{
  "url": "https://www.baidu.com",
  "keyword": "{{keyword}}",
  "timeoutMs": 30000,
  "startUrls": ["https://example.com"],
  "skipDefaultStartUrls": true
}''';
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('运行参数 JSON 说明'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '• 必须为合法的 JSON 对象，脚本内部通过 params.xxx 读取字段。\n'
                '• 支持使用 {{变量名}} 占位符，在“运行脚本”弹窗或对外 API 调用时自动替换为对应变量值。\n'
                '• 常见参数：url（目标网址）、keyword（搜索关键词）、timeoutMs（超时毫秒）、startUrls（启动页列表）。',
                style: prism.AppTextStyle.footnote.of(context),
              ),
              const SizedBox(height: 12),
              const PrismCodeSurface(
                code: exampleJson,
                language: 'json',
                showCopy: true,
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
      ),
    );
  }

  Future<bool> _save() async {
    final record = _record;
    if (record == null) return false;
    if (_name.text.trim().isEmpty) {
      showPrismNotice(context, '请先填写脚本名称');
      return false;
    }
    if (_script.text.trim().isEmpty) {
      showPrismNotice(
        context,
        _isLaunchApi ? '固定接口模板不能为空' : '脚本内容不能为空',
      );
      return false;
    }
    if (_apiVarEditorMode == 0) {
      _syncJsonFromVarRows();
    }
    dynamic apiVariables;
    Map<String, dynamic>? storedTargetSelector;
    try {
      if (_targetMode == 'create' && (_templateProfileId ?? '').isEmpty) {
        throw const FormatException('按模板新建至少要选择一个模板实例');
      }
      if (_targetMode == 'rotate') {
        final selector = jsonDecode(_targetSelector.text);
        if (selector is! Map || selector.isEmpty) {
          throw const FormatException('按条件轮询至少要填写一个实例条件');
        }
        storedTargetSelector = Map<String, dynamic>.from(selector);
      }
      if (_apiEnabled && _normalizePublicApiPath(_apiPath.text).isEmpty) {
        throw const FormatException('请填写接口路径');
      }
      apiVariables = _apiVariables.text.trim().isEmpty
          ? <dynamic>[]
          : jsonDecode(_apiVariables.text);
      if (apiVariables is! List) {
        throw const FormatException('变量必须是 JSON 数组');
      }
      if (_apiEnabled &&
          _apiRequest.text.trim().isNotEmpty &&
          jsonDecode(_apiRequest.text) is! Map) {
        throw const FormatException('请求 Body 必须是 JSON 对象');
      }
      if (_apiEnabled &&
          _apiResponse.text.trim().isNotEmpty &&
          jsonDecode(_apiResponse.text) is! Map) {
        throw const FormatException('响应示例必须是 JSON 对象');
      }
    } catch (error) {
      showPrismNotice(context, '配置无效：$error');
      return false;
    }
    setState(() => _busy = 'save');
    try {
      final next = <String, dynamic>{
        ...record,
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'status': _status,
        'scriptText': _script.text,
        'selectorText': _selector.text,
        'paramsText': _params.text,
        'targetConfig': {
          ..._tryDecodeMap(record['targetConfig']),
          'mode': _targetMode,
          'selector':
              storedTargetSelector ??
              (_tryDecodeMap(record['targetConfig'])['selector'] ?? {}),
          'templateSelector': _targetMode == 'create'
              ? {'profileId': _templateProfileId}
              : (_tryDecodeMap(record['targetConfig'])['templateSelector'] ??
                    {}),
          'createNameTemplate': _createNameTemplate.text.trim(),
        },
        'publicAPI': {
          ..._tryDecodeMap(record['publicAPI']),
          'enabled': _apiEnabled,
          'method': 'POST',
          'path': _normalizePublicApiPath(_apiPath.text),
          'requestMode': _apiRequestMode,
          'responseMode': _apiResponseMode,
          'timeoutMs': (int.tryParse(_apiTimeout.text) ?? 300000).clamp(
            1000,
            1800000,
          ),
          'requestBodyText': _apiRequest.text.trim(),
          'responseBodyText': _apiResponse.text.trim(),
          'variables': apiVariables,
        },
      };
      final result = await AppBridge.call('AutomationScriptSave', [next]);
      _record = Map<String, dynamic>.from(result as Map);
      final savedPublicApi = _tryDecodeMap(_record!['publicAPI']);
      _apiPath.text = (savedPublicApi['path'] ?? '').toString();
      _savedDraftSnapshot = _draftSnapshot();
      if (mounted) showPrismNotice(context, '已保存');
      final savedId = (_record!['id'] ?? '').toString();
      if (widget.scriptId == 'new' && savedId.isNotEmpty) {
        widget.onCreated(savedId);
      }
      return true;
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _openRunModal() async {
    final record = _record;
    if (record == null) return;
    if (_status == 'disabled') {
      showPrismNotice(context, '当前脚本状态为“已禁用”，无法运行。请先切换状态为就绪或草稿。');
      return;
    }
    final scriptId = '${record['id'] ?? widget.scriptId}';
    if (scriptId.isEmpty || scriptId == 'new') {
      showPrismNotice(context, '请先保存脚本后再运行');
      return;
    }
    if (_apiVarEditorMode == 0) {
      _syncJsonFromVarRows();
    }
    final draftScript = <String, dynamic>{
      ...record,
      'id': scriptId,
      'name': _name.text.trim().isEmpty ? record['name'] : _name.text.trim(),
      'status': _status,
      'selectorText': _selector.text,
      'paramsText': _params.text,
      'targetConfig': {
        ..._tryDecodeMap(record['targetConfig']),
        'mode': _targetMode,
        'selector': _tryDecodeMap(_targetSelector.text),
        'templateSelector': _targetMode == 'create'
            ? {'profileId': _templateProfileId}
            : (_tryDecodeMap(record['targetConfig'])['templateSelector'] ?? {}),
        'createNameTemplate': _createNameTemplate.text.trim(),
      },
      'publicAPI': {
        ..._tryDecodeMap(record['publicAPI']),
        'enabled': _apiEnabled,
        'variables': _parseVariables(_apiVariables.text),
      },
    };
    await AutomationScriptRunModal.show(
      context,
      script: draftScript,
      profiles: _profiles,
    );
  }

  Future<void> _testPublicAPI() async {
    if (widget.scriptId == 'new' || (_record?['id'] ?? '').toString().isEmpty) {
      showPrismNotice(context, '请先保存脚本，再测试对外接口');
      return;
    }
    if (!_apiEnabled) {
      showPrismNotice(context, '请先启用对外 API');
      return;
    }
    if (_status == 'disabled') {
      showPrismNotice(context, '脚本处于“已禁用”状态，请先启用后再测试');
      return;
    }
    final saved = await _save();
    if (!saved || !mounted) return;

    var body = _apiRequest.text.trim().isEmpty ? '{}' : _apiRequest.text.trim();
    for (final variable in _parseVariables(_apiVariables.text)) {
      final name = (variable['name'] ?? '').toString().trim();
      final value = (variable['defaultValue'] ?? '').toString();
      if (name.isNotEmpty) {
        body = body.replaceAll('{{$name}}', value);
      }
    }

    setState(() {
      _busy = 'public-api';
      _runOutput = '正在测试对外 API…';
    });
    try {
      final info = await AppBridge.call('GetLaunchServerInfo');
      final infoMap = _tryDecodeMap(info);
      final baseUrl = (infoMap['baseUrl'] ?? '').toString().replaceAll(
        RegExp(r'/+$'),
        '',
      );
      final apiAuth = _tryDecodeMap(infoMap['apiAuth']);
      final authHeader = '${apiAuth['header'] ?? ''}'.trim().isNotEmpty
          ? '${apiAuth['header']}'.trim()
          : _apiAuthHeader;
      if (baseUrl.isNotEmpty) _launchBaseUrl = baseUrl;
      _apiAuthHeader = authHeader;
      _apiAuthEnabled = apiAuth['enabled'] == true;

      final path = _normalizePublicApiPath(_apiPath.text);
      if (baseUrl.isEmpty || path.isEmpty) {
        throw StateError('请确认 Launch Server 已启动，并填写接口路径');
      }
      final result = await AppBridge.call('AutomationScriptInvokePublicAPI', [
        {
          'url': '$baseUrl/api/automation/hooks/$path',
          'method': 'POST',
          'bodyText': body,
          'apiKey': _apiKey.text.trim(),
          'authHeader': authHeader,
          'timeoutMs': (int.tryParse(_apiTimeout.text) ?? 300000).clamp(
            1000,
            1800000,
          ),
        },
      ]);
      final value = result is Map ? Map<String, dynamic>.from(result) : {};
      final formattedBody = _prettyJson('${value['bodyText'] ?? ''}');
      _runOutput =
          'HTTP ${value['status'] ?? ''} ${value['statusText'] ?? ''}\n$formattedBody';
    } catch (error) {
      _runOutput = error.toString();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  String _fullPublicApiUrl() {
    final normalized = _normalizePublicApiPath(_apiPath.text);
    return '$_launchBaseUrl/api/automation/hooks/$normalized';
  }

  String _openClawTemplate() {
    final selector = _tryDecodeMap(_selector.text);
    final params = _tryDecodeMap(_params.text);
    final body = const JsonEncoder.withIndent('  ').convert({
      if (selector.isNotEmpty) 'selector': selector,
      ...params,
    });
    return _buildCurlCommand(
      url: '$_launchBaseUrl/api/launch',
      bodyJson: body,
      authHeader: _apiAuthHeader,
      apiKey: _apiKey.text,
    );
  }

  Widget _buildRotateTargetEditor(BuildContext context) {
    return PrismSectionCard(
      title: '轮询实例条件（TargetSelectorEditor）',
      glyph: AntGlyphs.tune,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PrismTextField(
                  controller: _rotCode,
                  onChanged: (_) => _syncRotateJsonFromFields(),
                  decoration: const PrismInputDecoration(
                    labelText: '启动码（code）',
                    hintText: '如 BUYER_001',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrismTextField(
                  controller: _rotProfileId,
                  onChanged: (_) => _syncRotateJsonFromFields(),
                  decoration: const PrismInputDecoration(
                    labelText: '实例 ID（profileId）',
                    hintText: '可选',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PrismTextField(
                  controller: _rotProfileName,
                  onChanged: (_) => _syncRotateJsonFromFields(),
                  decoration: const PrismInputDecoration(
                    labelText: '实例名称（profileName）',
                    hintText: '可选',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrismDropdownField<String>(
                  value: _rotGroupId,
                  decoration: const PrismInputDecoration(
                    labelText: '所属分组（groupId）',
                    hintText: '不限分组',
                  ),
                  items: [
                    const PrismDropdownItem(value: '', child: Text('不限分组')),
                    for (final g in _groups)
                      PrismDropdownItem(
                        value: '${g['groupId'] ?? ''}',
                        child: Text('${g['groupName'] ?? g['groupId'] ?? ''}'),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _rotGroupId = value ?? '');
                    _syncRotateJsonFromFields();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PrismTextField(
                  controller: _rotTags,
                  onChanged: (_) => _syncRotateJsonFromFields(),
                  decoration: const PrismInputDecoration(
                    labelText: '标签（tags，逗号分隔）',
                    hintText: '如 电商, 养号',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrismTextField(
                  controller: _rotKeywords,
                  onChanged: (_) => _syncRotateJsonFromFields(),
                  decoration: const PrismInputDecoration(
                    labelText: '关键词（keywords，逗号分隔）',
                    hintText: '如 店铺A, 备用',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PrismTextField(
            controller: _targetSelector,
            minLines: 2,
            maxLines: 6,
            onChanged: (_) => _syncRotateFieldsFromJson(),
            decoration: const PrismInputDecoration(
              labelText: '生成的条件 JSON（可直接微调）',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualVariablesEditor(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '对外 API 变量配置',
                style: prism.AppTextStyle.footnote.of(
                  context,
                  emphasized: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              child: prism.SegmentedControl<int>(
                segments: const [(0, '可视化编辑'), (1, 'JSON')],
                value: _apiVarEditorMode,
                onChanged: (mode) {
                  setState(() {
                    if (mode == 1) {
                      _syncJsonFromVarRows();
                    } else {
                      _syncVarRowsFromJson();
                    }
                    _apiVarEditorMode = mode;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_apiVarEditorMode == 0) ...[
          if (_varRows.isEmpty)
            prism.Surface(
              color: colors.surfaceContainerLow,
              shape: prism.AppShape.lg,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  '暂无变量。点击下方“添加变量”可在请求 Body 中使用 {{变量名}} 占位符。',
                  style: prism.AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          for (var i = 0; i < _varRows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: prism.Surface(
                color: colors.surfaceContainerLow,
                shape: prism.AppShape.lg,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: _varRows[i].name,
                              onChanged: (_) => _syncJsonFromVarRows(),
                              decoration: const PrismInputDecoration(
                                labelText: '变量名',
                                hintText: 'keyword',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrismTextField(
                              controller: _varRows[i].defaultValue,
                              onChanged: (_) => _syncJsonFromVarRows(),
                              decoration: const PrismInputDecoration(
                                labelText: '默认值',
                                hintText: 'OpenAI',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrismTextField(
                              controller: _varRows[i].description,
                              onChanged: (_) => _syncJsonFromVarRows(),
                              decoration: const PrismInputDecoration(
                                labelText: '说明',
                                hintText: '搜索关键词',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          prism.Checkbox(
                            value: _varRows[i].required,
                            onChanged: (v) {
                              setState(() => _varRows[i].required = v == true);
                              _syncJsonFromVarRows();
                            },
                          ),
                          const SizedBox(width: 6),
                          const Text('必填'),
                          const Spacer(),
                          prism.TextButton.icon(
                            onPressed: () {
                              setState(() {
                                final removed = _varRows.removeAt(i);
                                removed.dispose();
                              });
                              _syncJsonFromVarRows();
                            },
                            icon: PrismGlyph(
                              AntGlyphs.delete,
                              size: 14,
                              color: colors.error,
                            ),
                            label: const Text('移除'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: prism.OutlinedButton.icon(
              onPressed: () {
                setState(() => _varRows.add(_ApiVarRow()));
              },
              icon: const PrismGlyph(AntGlyphs.add, size: 15),
              label: const Text('添加变量'),
            ),
          ),
        ] else
          PrismTextField(
            controller: _apiVariables,
            minLines: 3,
            maxLines: 8,
            decoration: const PrismInputDecoration(
              labelText: '变量配置 JSON 数组',
              hintText:
                  '[{"name":"keyword","defaultValue":"OpenAI","description":"关键词","required":true}]',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PrismProgressIndicator());
    final colors = prism.Theme.of(context).colorScheme;
    final refreshable = _isRefreshableSource(_record);
    final sourceLabel = _formatSourceLabel(_record);
    final updatedAt = _formatDateTime(_record?['updatedAt']);
    final canRun =
        _busy.isEmpty &&
        _status != 'disabled' &&
        !_isLaunchApi &&
        (_record?['id'] ?? widget.scriptId) != '' &&
        (_record?['id'] ?? widget.scriptId) != 'new';

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: prism.IconButton(
                tooltip: '返回',
                onPressed: _busy.isEmpty ? _leavePage : null,
                icon: const PrismGlyph(AntGlyphs.arrowBack, size: 18),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PrismPageContextBar(
                glyph: widget.scriptId == 'new'
                    ? AntGlyphs.add
                    : AntGlyphs.code,
                title: widget.scriptId == 'new' ? '新建脚本' : '脚本详情',
                subtitle: sourceLabel.isEmpty
                    ? '脚本与对外 API 配置，更新于 $updatedAt'
                    : '来源：$sourceLabel · 更新于 $updatedAt',
                actions: [
                  if (_isDirty)
                    const PrismBadge(
                      label: '未保存',
                      tone: PrismTone.warning,
                      dot: true,
                    ),
                  PrismBadge(
                    label: _statusLabel(_status),
                    tone: _statusTone(_status),
                  ),
                  if (!_isLaunchApi)
                    prism.OutlinedButton.icon(
                      onPressed: canRun ? _openRunModal : null,
                      icon: const PrismGlyph(AntGlyphs.play, size: 15),
                      label: const Text('运行脚本'),
                    ),
                  PrismHoverMotion(
                    enabled: _busy.isEmpty,
                    child: prism.FilledButton.icon(
                      onPressed: _busy.isEmpty ? _save : null,
                      icon: const PrismGlyph(AntGlyphs.save, size: 15),
                      label: Text(_busy == 'save' ? '保存中…' : '保存'),
                    ),
                  ),
                  PrismPopupMenuButton<String>(
                    tooltip: '更多操作',
                    enabled: _busy.isEmpty && widget.scriptId != 'new',
                    icon: const PrismGlyph(AntGlyphs.more, size: 18),
                    onSelected: (action) async {
                      if (action.startsWith('export-')) {
                        try {
                          final format = action.substring(
                            'export-'.length,
                          );
                          final method = switch (format) {
                            'json' => 'AutomationScriptExport',
                            'directory' => 'AutomationScriptExportDirectory',
                            _ => 'AutomationScriptExportZip',
                          };
                          final result = await AppBridge.call(method, [
                            widget.scriptId,
                          ]);
                          if (mounted &&
                              result is Map &&
                              result['message'] != null) {
                            showPrismNotice(
                              context,
                              result['message'].toString(),
                            );
                          }
                        } catch (error) {
                          if (mounted) {
                            showPrismNotice(context, error.toString());
                          }
                        }
                      } else if (action == 'delete') {
                        final yes = await showPrismDialog<bool>(
                          context: context,
                          useRootNavigator: false,
                          builder: (context) => PrismDialog(
                            title: const Text('删除脚本？'),
                            destructive: true,
                            content: Text('将删除“${_name.text}”及其本地文件。'),
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
                        if (yes == true) {
                          try {
                            await AppBridge.call('AutomationScriptDelete', [
                              widget.scriptId,
                            ]);
                            widget.onBack();
                          } catch (error) {
                            if (mounted) {
                              showPrismNotice(context, '删除脚本失败：$error');
                            }
                          }
                        }
                      } else if (action == 'refresh') {
                        try {
                          final refreshed = await AppBridge.call(
                            'AutomationScriptRefresh',
                            [widget.scriptId],
                          );
                          _record = Map<String, dynamic>.from(
                            refreshed as Map,
                          );
                          _hydrateFromRecord(_record!);
                          _savedDraftSnapshot = _draftSnapshot();
                          if (mounted) {
                            setState(() {});
                            showPrismNotice(context, '已按来源重新导入');
                          }
                        } catch (error) {
                          if (mounted) {
                            showPrismNotice(context, error.toString());
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      const PrismMenuItem(
                        value: 'export-json',
                        child: Text('导出 JSON 模板'),
                      ),
                      const PrismMenuItem(
                        value: 'export-directory',
                        child: Text('导出目录'),
                      ),
                      const PrismMenuItem(
                        value: 'export-zip',
                        child: Text('导出 ZIP'),
                      ),
                      PrismMenuItem(
                        value: 'refresh',
                        enabled: refreshable,
                        child: Text(
                          refreshable
                              ? '按来源重新导入'
                              : '按来源重新导入（当前来源不支持）',
                        ),
                      ),
                      const PrismMenuItem(
                        value: 'delete',
                        danger: true,
                        child: Text('删除脚本'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_status == 'disabled') ...[
          const SizedBox(height: 12),
          const PrismBanner(
            tone: PrismTone.warning,
            title: '脚本已禁用',
            message: '当前状态为“已禁用”，运行与对外 API 触发均会被拦截。切换为“就绪”或“草稿”后即可恢复。',
          ),
        ],
        const SizedBox(height: 14),
        PrismSectionCard(
          title: '基础信息',
          glyph: AntGlyphs.docs,
          staggerIndex: 0,
          staggerDelay: const Duration(milliseconds: 45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: PrismTextField(
                      controller: _name,
                      decoration: const PrismInputDecoration(labelText: '脚本名称'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrismDropdownField<String>(
                      value: _status,
                      decoration: const PrismInputDecoration(labelText: '状态'),
                      items: const [
                        PrismDropdownItem(value: 'draft', child: Text('草稿')),
                        PrismDropdownItem(value: 'ready', child: Text('就绪')),
                        PrismDropdownItem(
                          value: 'disabled',
                          child: Text('已禁用'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _status = value);
                      },
                    ),
                  ),
                ],
              ),
              if (widget.scriptId == 'new') ...[
                const SizedBox(height: 10),
                PrismDropdownField<String>(
                  value: (_record?['type'] ?? 'playwright-cdp').toString(),
                  decoration: const PrismInputDecoration(labelText: '脚本类型'),
                  items: const [
                    PrismDropdownItem(
                      value: 'playwright-cdp',
                      child: Text('Playwright 自动化'),
                    ),
                    PrismDropdownItem(
                      value: 'launch-api',
                      child: Text('Launch API'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) _changeNewScriptType(value);
                  },
                ),
              ],
              const SizedBox(height: 10),
              PrismTextField(
                controller: _description,
                decoration: const PrismInputDecoration(labelText: '说明'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PrismSectionCard(
          title: _isLaunchApi ? '启动配置' : '目标实例与运行参数',
          glyph: AntGlyphs.browser,
          staggerIndex: 1,
          staggerDelay: const Duration(milliseconds: 45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isLaunchApi) ...[
                PrismDropdownField<String>(
                  value: _targetMode,
                  decoration: const PrismInputDecoration(labelText: '实例来源'),
                  items: const [
                    PrismDropdownItem(value: 'manual', child: Text('手动选择实例')),
                    PrismDropdownItem(value: 'create', child: Text('按模板新建实例')),
                    PrismDropdownItem(value: 'rotate', child: Text('按条件轮询实例')),
                  ],
                  onChanged: (value) =>
                      setState(() => _targetMode = value ?? 'manual'),
                ),
                const SizedBox(height: 10),
              ],
              if (_isLaunchApi || _targetMode == 'manual') ...[
                PrismDropdownField<String>(
                  value:
                      _profiles.any(
                        (profile) => profile['profileId'] == _targetProfileId,
                      )
                      ? _targetProfileId
                      : null,
                  decoration: const PrismInputDecoration(
                    labelText: '默认目标实例',
                    hintText: '可选，选择后可同步到选择器',
                  ),
                  items: [
                    for (final profile in _profiles)
                      PrismDropdownItem(
                        value: profile['profileId']?.toString(),
                        child: Text(
                          '${profile['profileName'] ?? '未命名实例'}'
                          '${profile['running'] == true ? ' · 运行中' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _targetProfileId = value),
                ),
                const SizedBox(height: 10),
                PrismTextField(
                  controller: _selector,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const PrismInputDecoration(
                    labelText: '目标选择器 JSON',
                  ),
                ),
              ],
              if (!_isLaunchApi && _targetMode == 'create') ...[
                PrismDropdownField<String>(
                  value:
                      _profiles.any(
                        (profile) =>
                            profile['profileId'] == _templateProfileId,
                      )
                      ? _templateProfileId
                      : null,
                  decoration: const PrismInputDecoration(labelText: '模板实例'),
                  items: [
                    for (final profile in _profiles)
                      PrismDropdownItem(
                        value: profile['profileId']?.toString(),
                        child: Text(
                          profile['profileName']?.toString() ?? '未命名实例',
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _templateProfileId = value),
                ),
                const SizedBox(height: 10),
                PrismTextField(
                  controller: _createNameTemplate,
                  decoration: const PrismInputDecoration(
                    labelText: '新实例名称模板',
                    helperText:
                        '可留空使用默认名称，也可以写 ${r'${templateName}-${timestamp}'}。',
                  ),
                ),
              ],
              if (!_isLaunchApi && _targetMode == 'rotate')
                _buildRotateTargetEditor(context),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '运行参数 JSON',
                      style: prism.AppTextStyle.footnote
                          .of(context, emphasized: true)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 8),
                  prism.IconButton(
                    tooltip: '参数格式说明',
                    onPressed: _showParamsHelp,
                    icon: const PrismGlyph(AntGlyphs.info, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              PrismTextField(
                controller: _params,
                minLines: 3,
                maxLines: 8,
                decoration: const PrismInputDecoration(
                  hintText: '{"url": "https://example.com"}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_isLaunchApi) ...[
          PrismSectionCard(
            title: 'OpenClaw 指令模板',
            glyph: AntGlyphs.sparkles,
            staggerIndex: 2,
            staggerDelay: const Duration(milliseconds: 45),
            child: PrismCodeSurface(
              code: _openClawTemplate(),
              language: 'bash',
              maxHeight: 200,
              showCopy: true,
            ),
          ),
          const SizedBox(height: 14),
          PrismSectionCard(
            title: '固定接口模板（只读预览）',
            glyph: AntGlyphs.code,
            staggerIndex: 3,
            staggerDelay: const Duration(milliseconds: 45),
            child: PrismCodeSurface(
              code: _script.text,
              language: 'javascript',
              maxHeight: 260,
              showCopy: true,
            ),
          ),
        ] else
          PrismSectionCard(
            title: '脚本内容',
            glyph: AntGlyphs.code,
            staggerIndex: 2,
            staggerDelay: const Duration(milliseconds: 45),
            child: PrismTextField(
              controller: _script,
              minLines: 12,
              maxLines: 30,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 14),
        PrismSectionCard(
          title: '对外 API 配置',
          glyph: AntGlyphs.api,
          staggerIndex: _isLaunchApi ? 4 : 3,
          staggerDelay: const Duration(milliseconds: 45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismSwitchTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用对外 API'),
                subtitle: const Text('通过 Launch Server 的 HTTP 接口触发此脚本'),
                value: _apiEnabled,
                onChanged: _busy.isEmpty
                    ? (value) => setState(() {
                        _apiEnabled = value;
                        if (value && _apiPath.text.trim().isEmpty) {
                          _apiPath.text = _recommendedApiPath(
                            _name.text,
                            '${_record?['id'] ?? ''}',
                          );
                        }
                      })
                    : null,
              ),
              if (_apiEnabled) ...[
                const SizedBox(height: 10),
                prism.Surface(
                  color: colors.surfaceContainerLow,
                  shape: prism.AppShape.lg,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const PrismBadge(
                              label: 'POST',
                              tone: PrismTone.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: prism.SelectableText(
                                _fullPublicApiUrl(),
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            prism.OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: _fullPublicApiUrl()),
                                );
                                showPrismNotice(context, '已复制完整接口 URL');
                              },
                              icon: const PrismGlyph(AntGlyphs.copy, size: 14),
                              label: const Text('复制 URL'),
                            ),
                            prism.OutlinedButton.icon(
                              onPressed: () {
                                final body = _apiRequest.text.trim().isEmpty
                                    ? '{}'
                                    : _apiRequest.text.trim();
                                final curl = _buildCurlCommand(
                                  url: _fullPublicApiUrl(),
                                  bodyJson: body,
                                  authHeader: _apiAuthHeader,
                                  apiKey: _apiKey.text,
                                );
                                Clipboard.setData(ClipboardData(text: curl));
                                showPrismNotice(context, '已复制 cURL 命令');
                              },
                              icon: const PrismGlyph(AntGlyphs.code, size: 14),
                              label: const Text('复制 curl'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: PrismTextField(
                        controller: _apiPath,
                        decoration: const PrismInputDecoration(
                          labelText: '接口路径',
                          hintText: 'my-script',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    prism.OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _apiPath.text = _recommendedApiPath(
                          _name.text,
                          '${_record?['id'] ?? ''}',
                        );
                      }),
                      icon: const PrismGlyph(AntGlyphs.sparkles, size: 14),
                      label: const Text('推荐'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: PrismDropdownField<String>(
                        value: _apiRequestMode,
                        decoration: const PrismInputDecoration(
                          labelText: '请求模式',
                        ),
                        items: const [
                          PrismDropdownItem(
                            value: 'standard',
                            child: Text('标准请求'),
                          ),
                          PrismDropdownItem(
                            value: 'params-only',
                            child: Text('只透传 params'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _apiRequestMode = value ?? 'standard',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrismDropdownField<String>(
                        value: _apiResponseMode,
                        decoration: const PrismInputDecoration(
                          labelText: '响应模式',
                        ),
                        items: const [
                          PrismDropdownItem(
                            value: 'envelope',
                            child: Text('标准响应'),
                          ),
                          PrismDropdownItem(
                            value: 'result-only',
                            child: Text('只返回 result'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _apiResponseMode = value ?? 'envelope',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrismTextField(
                        controller: _apiTimeout,
                        keyboardType: TextInputType.number,
                        decoration: const PrismInputDecoration(
                          labelText: '超时（毫秒）',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PrismTextField(
                  controller: _apiKey,
                  obscureText: _obscureApiKey,
                  decoration: PrismInputDecoration(
                    labelText:
                        'API Key（鉴权请求头：$_apiAuthHeader${_apiAuthEnabled ? ' · 已开启鉴权' : ' · 未强制开启'}）',
                    hintText: '填写 API Key 用于测试调用（留空时后端将尝试自动解析本地配置）',
                    suffixIcon: prism.IconButton(
                      tooltip: _obscureApiKey ? '显示 API Key' : '隐藏 API Key',
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                      icon: PrismGlyph(
                        _obscureApiKey ? AntGlyphs.eye : AntGlyphs.eyeOff,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                PrismTextField(
                  controller: _apiRequest,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const PrismInputDecoration(
                    labelText: '请求 Body JSON',
                  ),
                ),
                const SizedBox(height: 10),
                PrismTextField(
                  controller: _apiResponse,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const PrismInputDecoration(
                    labelText: '响应示例 JSON（可选）',
                  ),
                ),
                const SizedBox(height: 12),
                _buildVisualVariablesEditor(context),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: PrismHoverMotion(
                    enabled: _busy.isEmpty,
                    child: prism.FilledButton.icon(
                      onPressed: _busy.isEmpty ? _testPublicAPI : null,
                      icon: const PrismGlyph(AntGlyphs.play, size: 15),
                      label: Text(
                        _busy == 'public-api' ? '测试中…' : '保存并测试接口',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_runOutput.isNotEmpty) ...[
          const SizedBox(height: 14),
          PrismSectionCard(
            title: '接口测试输出',
            glyph: AntGlyphs.logs,
            child: PrismCodeSurface(
              code: _runOutput,
              language: 'json',
              maxHeight: 260,
              showCopy: true,
            ),
          ),
        ],
      ],
    );
  }
}
