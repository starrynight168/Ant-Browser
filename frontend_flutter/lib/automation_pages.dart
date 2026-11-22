import 'dart:convert';

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'wails_bridge.dart';

class AutomationPage extends StatefulWidget {
  const AutomationPage({
    super.key,
    required this.onOpen,
    required this.onCreate,
  });
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;
  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<AutomationPage> {
  List<Map<String, dynamic>> _scripts = [];
  List<Map<String, dynamic>> _runs = [];
  final Set<String> _selectedScriptIds = {};
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
      final result = await Future.wait([
        WailsBridge.call('AutomationScriptList'),
        WailsBridge.call('AutomationScriptRunList', [100]),
      ]);
      _scripts = (result[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _runs = (result[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _import(String mode) async {
    if (mode == 'remote' || mode == 'git') {
      await _importFromSource(mode);
      return;
    }
    setState(() => _busy = mode);
    try {
      if (mode == 'library') {
        await WailsBridge.call('AutomationScriptImportLocalLibrary');
      } else {
        await WailsBridge.call(
          mode == 'directory'
              ? 'AutomationScriptImportLocalDirectory'
              : 'AutomationScriptImportLocalFile',
        );
      }
      await _refresh();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrismTextField(
              controller: url,
              decoration: PrismInputDecoration(
                labelText: mode == 'git' ? 'Git 仓库地址' : '脚本网址',
              ),
            ),
            if (mode == 'git') ...[
              PrismTextField(
                controller: ref,
                decoration: const PrismInputDecoration(labelText: '分支或标签'),
              ),
              PrismTextField(
                controller: scriptPath,
                decoration: const PrismInputDecoration(labelText: '脚本目录（可留空）'),
              ),
            ],
          ],
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
      await WailsBridge.call(
        mode == 'git'
            ? 'AutomationScriptImportGit'
            : 'AutomationScriptImportRemote',
        mode == 'git'
            ? [source, selectedValues[1], selectedValues[2]]
            : [source],
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
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
      await WailsBridge.call('AutomationScriptDelete', [id]);
      await _refresh();
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
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
      final result = await WailsBridge.call(method, [id]);
      final message = result is Map ? result['message'] : null;
      if (mounted && message != null) {
        showPrismNotice(context, (message.toString()).toString());
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    }
  }

  Future<void> _exportSelectedScripts() async {
    final ids = _selectedScriptIds.toList();
    if (ids.isEmpty) return;
    setState(() => _busy = 'export');
    try {
      final result = await WailsBridge.call('AutomationScriptExportBatchZip', [
        ids,
      ]);
      final value = result is Map ? result['message'] : null;
      if (mounted) {
        showPrismNotice(
          context,
          ((value ?? '已导出 ${ids.length} 个脚本').toString()).toString(),
        );
        setState(() => _selectedScriptIds.clear());
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _showRunDetails(Map<String, dynamic> run) async {
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text(
          (run['scriptName'] ?? run['scriptId'] ?? '运行记录').toString(),
        ),
        content: SizedBox(
          width: 680,
          height: 520,
          child: ListView(
            children: [
              Text('状态：${run['status'] ?? ''}'),
              Text('开始时间：${run['startedAt'] ?? ''}'),
              Text('耗时：${run['durationMs'] ?? 0} ms'),
              if ((run['summary'] ?? '').toString().isNotEmpty)
                Text('摘要：${run['summary']}'),
              if ((run['error'] ?? '').toString().isNotEmpty)
                prism.SelectableText('错误：\n${run['error']}'),
              if ((run['resultText'] ?? '').toString().isNotEmpty)
                prism.SelectableText('运行结果：\n${run['resultText']}'),
              if ((run['logText'] ?? '').toString().isNotEmpty)
                prism.SelectableText('运行日志：\n${run['logText']}'),
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '自动化脚本',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            prism.FilledButton.icon(
              onPressed: _busy.isEmpty ? widget.onCreate : null,
              icon: const Icon(Icons.add),
              label: const Text('新建脚本'),
            ),
            if (_selectedScriptIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty ? _exportSelectedScripts : null,
                icon: const Icon(Icons.download_outlined),
                label: Text('导出 ${_selectedScriptIds.length} 个'),
              ),
            ],
            prism.IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
            PrismPopupMenuButton<String>(
              tooltip: '导入脚本',
              enabled: _busy.isEmpty,
              icon: const Icon(Icons.upload_file),
              onSelected: _import,
              itemBuilder: (_) => const [
                PrismMenuItem(value: 'file', child: Text('从文件导入')),
                PrismMenuItem(value: 'directory', child: Text('从文件夹导入')),
                PrismMenuItem(value: 'library', child: Text('导入内置脚本库')),
                PrismMenuItem(value: 'remote', child: Text('从网址导入')),
                PrismMenuItem(value: 'git', child: Text('从 Git 仓库导入')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _loading
              ? const Center(child: PrismProgressIndicator())
              : ListView(
                  children: [
                    const Text(
                      '脚本列表',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (_scripts.isEmpty)
                      const PrismCard(
                        child: PrismListTile(title: Text('还没有脚本，请导入脚本包')),
                      ),
                    for (final script in _scripts)
                      PrismCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: PrismListTile(
                          onTap: () =>
                              widget.onOpen((script['id'] ?? '').toString()),
                          title: Text((script['name'] ?? '未命名脚本').toString()),
                          subtitle: Text(
                            '${script['description'] ?? ''}\n${script['type'] ?? ''} · ${script['status'] ?? 'draft'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          leading: prism.Checkbox(
                            value: _selectedScriptIds.contains(
                              (script['id'] ?? '').toString(),
                            ),
                            onChanged: (selected) => setState(() {
                              final id = (script['id'] ?? '').toString();
                              if (selected == true) {
                                _selectedScriptIds.add(id);
                              } else {
                                _selectedScriptIds.remove(id);
                              }
                            }),
                          ),
                          trailing: PrismPopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'open') {
                                widget.onOpen((script['id'] ?? '').toString());
                              } else if (action.startsWith('export-')) {
                                _exportScript(
                                  (script['id'] ?? '').toString(),
                                  action.substring('export-'.length),
                                );
                              } else if (action == 'delete') {
                                _deleteScript(
                                  (script['id'] ?? '').toString(),
                                  (script['name'] ?? '未命名脚本').toString(),
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PrismMenuItem(value: 'open', child: Text('编辑')),
                              PrismMenuItem(
                                value: 'export-json',
                                child: Text('导出 JSON 模板'),
                              ),
                              PrismMenuItem(
                                value: 'export-directory',
                                child: Text('导出目录'),
                              ),
                              PrismMenuItem(
                                value: 'export-zip',
                                child: Text('导出 ZIP'),
                              ),
                              PrismMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    const Text(
                      '最近运行',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (_runs.isEmpty)
                      const PrismCard(
                        child: PrismListTile(title: Text('暂无运行记录')),
                      ),
                    for (final run in _runs)
                      PrismCard(
                        child: PrismListTile(
                          onTap: () => _showRunDetails(run),
                          leading: Icon(
                            run['status'] == 'success'
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: run['status'] == 'success'
                                ? prism.Theme.of(context).colorScheme.tertiary
                                : prism.Theme.of(context).colorScheme.error,
                          ),
                          title: Text(
                            (run['scriptName'] ?? run['scriptId'] ?? '')
                                .toString(),
                          ),
                          subtitle: Text(
                            '${run['summary'] ?? run['error'] ?? ''} · ${run['startedAt'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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

class AutomationScriptDetailPage extends StatefulWidget {
  const AutomationScriptDetailPage({
    super.key,
    required this.scriptId,
    required this.onBack,
    required this.onCreated,
  });
  final String scriptId;
  final VoidCallback onBack;
  final ValueChanged<String> onCreated;
  @override
  State<AutomationScriptDetailPage> createState() =>
      _AutomationScriptDetailPageState();
}

class _AutomationScriptDetailPageState
    extends State<AutomationScriptDetailPage> {
  Map<String, dynamic>? _record;
  List<Map<String, dynamic>> _profiles = [];
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _script = TextEditingController();
  final _selector = TextEditingController();
  final _params = TextEditingController();
  final _apiPath = TextEditingController();
  final _apiRequest = TextEditingController();
  final _apiResponse = TextEditingController();
  final _apiVariables = TextEditingController(text: '[]');
  final _apiTimeout = TextEditingController(text: '300000');
  bool _loading = true;
  bool _apiEnabled = false;
  String _apiRequestMode = 'standard';
  String _apiResponseMode = 'envelope';
  String _busy = '';
  String _runOutput = '';
  String? _targetProfileId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _script.dispose();
    _selector.dispose();
    _params.dispose();
    _apiPath.dispose();
    _apiRequest.dispose();
    _apiResponse.dispose();
    _apiVariables.dispose();
    _apiTimeout.dispose();
    super.dispose();
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
        'paramsText': '{\n  "url": "https://www.baidu.com",\n  "keyword": "OpenAI",\n  "timeoutMs": 30000\n}',
        'scriptText': "module.exports.run = async ({ useBrowser, selector, params, log }) => {\n  const url = params.url || 'https://www.baidu.com'\n  const runtime = await useBrowser({ selector, startUrls: [url], skipDefaultStartUrls: true })\n  const page = runtime.page\n  const keyword = params.keyword || 'OpenAI'\n  const input = page.locator('textarea[name=wd], input[name=wd]').first()\n  await input.fill(keyword)\n  await input.press('Enter')\n  const title = await page.title()\n  log('title', title)\n  return { ok: true, summary: `已搜索 \${keyword}`, url: page.url(), title }\n} ",
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
        final value = await WailsBridge.call('AutomationScriptGet', [
          widget.scriptId,
        ]);
        _record = Map<String, dynamic>.from(value as Map);
      } catch (error) {
        _runOutput = error.toString();
      }
    }
    if (_record != null) {
      _name.text = (_record!['name'] ?? '').toString();
      _description.text = (_record!['description'] ?? '').toString();
      _script.text = (_record!['scriptText'] ?? '').toString();
      _selector.text = (_record!['selectorText'] ?? '{}').toString();
      _params.text = (_record!['paramsText'] ?? '{}').toString();
      final publicApi = _record!['publicAPI'] is Map
          ? Map<String, dynamic>.from(_record!['publicAPI'] as Map)
          : <String, dynamic>{};
      _apiEnabled = publicApi['enabled'] == true;
      _apiPath.text = (publicApi['path'] ?? '').toString();
      _apiRequestMode = (publicApi['requestMode'] ?? 'standard').toString();
      _apiResponseMode = (publicApi['responseMode'] ?? 'envelope').toString();
      _apiTimeout.text = (publicApi['timeoutMs'] ?? 300000).toString();
      _apiRequest.text = (publicApi['requestBodyText'] ?? '').toString();
      _apiResponse.text = (publicApi['responseBodyText'] ?? '').toString();
      _apiVariables.text = const JsonEncoder.withIndent('  ')
          .convert(publicApi['variables'] ?? []);
    }
    try {
      final profiles = await WailsBridge.call('BrowserProfileList');
      _profiles = (profiles as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final selector = jsonDecode(_selector.text);
      if (selector is Map && selector['profileId'] is String) {
        _targetProfileId = selector['profileId'] as String;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
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
      record['tags'] = type == 'launch-api' ? ['HTTP'] : ['Playwright', '示例'];
      record['selectorText'] = type == 'launch-api'
          ? '{\n  "code": "BUYER_001"\n}'
          : '';
      record['paramsText'] = type == 'launch-api'
          ? '{\n  "startUrls": ["https://example.com"],\n  "skipDefaultStartUrls": true\n}'
          : '{\n  "url": "https://www.baidu.com",\n  "keyword": "OpenAI",\n  "timeoutMs": 30000,\n  "waitAfterSearchMs": 1500,\n  "captureScreenshot": true\n}';
      record['scriptText'] = type == 'launch-api'
          ? "export async function run({ baseUrl, apiKey, selector, params }) {\n  const response = await fetch(`${r'${baseUrl}'}/api/launch`, {\n    method: 'POST',\n    headers: { 'Content-Type': 'application/json', ...(apiKey ? { 'X-Ant-Api-Key': apiKey } : {}) },\n    body: JSON.stringify({ selector, ...(params || {}) }),\n  })\n  if (!response.ok) throw new Error(`launch failed: ${r'${response.status}'}`)\n  return await response.json()\n}"
          : "module.exports.run = async ({ useBrowser, selector, params, log }) => {\n  const url = params.url || 'https://www.baidu.com'\n  const runtime = await useBrowser({ selector, startUrls: [url], skipDefaultStartUrls: true })\n  const page = runtime.page\n  const keyword = params.keyword || 'OpenAI'\n  const input = page.locator('textarea[name=wd], input[name=wd]').first()\n  await input.fill(keyword)\n  await input.press('Enter')\n  const title = await page.title()\n  log('title', title)\n  return { ok: true, summary: `已搜索 \${keyword}`, url: page.url(), title }\n} ";
      _name.text = record['name'].toString();
      _description.text = record['description'].toString();
      _selector.text = record['selectorText'].toString();
      _params.text = record['paramsText'].toString();
      _script.text = record['scriptText'].toString();
    });
  }

  Future<void> _save() async {
    final record = _record;
    if (record == null) return;
    if (_name.text.trim().isEmpty) {
      showPrismNotice(context, ('请先填写脚本名称').toString());
      return;
    }
    if (_script.text.trim().isEmpty) {
      showPrismNotice(
        context,
        ((_record?['type'] ?? '').toString() == 'launch-api'
                ? '固定接口模板不能为空'
                : '脚本内容不能为空')
            .toString(),
      );
      return;
    }
    dynamic apiVariables;
    try {
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
      showPrismNotice(context, ('对外 API 配置无效：$error').toString());
      return;
    }
    setState(() => _busy = 'save');
    try {
      final next = <String, dynamic>{
        ...record,
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'scriptText': _script.text,
        'selectorText': _selector.text,
        'paramsText': _params.text,
        'publicAPI': {
          ...(_record!['publicAPI'] is Map
              ? Map<String, dynamic>.from(_record!['publicAPI'] as Map)
              : <String, dynamic>{}),
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
      final result = await WailsBridge.call('AutomationScriptSave', [next]);
      _record = Map<String, dynamic>.from(result as Map);
      final savedPublicApi = _record!['publicAPI'];
      if (savedPublicApi is Map) {
        _apiPath.text = (savedPublicApi['path'] ?? '').toString();
      }
      if (mounted) showPrismNotice(context, ('已保存').toString());
      final savedId = (_record!['id'] ?? '').toString();
      if (widget.scriptId == 'new' && savedId.isNotEmpty) {
        widget.onCreated(savedId);
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _run() async {
    final record = _record;
    if (record == null) return;
    final scriptId = (record['id'] ?? widget.scriptId).toString();
    if (scriptId.isEmpty || scriptId == 'new') return;
    final target = _profiles.where(
      (item) => item['profileId'] == _targetProfileId,
    );
    final selected = target.isEmpty ? null : target.first;
    const dualInstanceScriptId = 'dual-instance-runtime-switch';
    final targetConfig = record['targetConfig'] is Map
        ? Map<String, dynamic>.from(record['targetConfig'] as Map)
        : <String, dynamic>{};
    final targetMode = selected != null
        ? 'manual'
        : (targetConfig['mode'] ?? 'manual').toString();
    final hasStoredTarget =
        targetMode != 'manual' ||
        (_selector.text.trim().isNotEmpty && _selector.text.trim() != '{}');
    if (selected == null &&
        scriptId != dualInstanceScriptId &&
        !hasStoredTarget) {
      showPrismNotice(context, ('请先选择运行目标实例，或填写目标选择器 JSON').toString());
      return;
    }
    setState(() {
      _busy = 'run';
      _runOutput = '正在运行…';
    });
    try {
      final launchCode = (selected?['launchCode'] ?? '').toString();
      if (selected != null &&
          selected['running'] != true &&
          launchCode.isNotEmpty) {
        await WailsBridge.call('BrowserInstanceStartByCode', [launchCode]);
      }
      final targetSelector = selected == null
          ? null
          : <String, dynamic>{
              'profileId': selected['profileId'],
              'profileName': selected['profileName'],
              if (launchCode.isNotEmpty) 'code': launchCode,
            };
      final result = await WailsBridge.call('AutomationScriptRunWithOptions', [
        {
          'scriptId': scriptId,
          'selectorText': selected == null
              ? _selector.text
              : jsonEncode(targetSelector),
          'targetMode': targetMode,
          if (targetSelector != null) 'targetInput': targetSelector,
          'paramsText': _params.text,
          'useScriptSelector':
              selected == null &&
              _selector.text == (record['selectorText'] ?? '{}').toString(),
          'useScriptParams': false,
        },
      ]);
      final value = Map<String, dynamic>.from(result as Map);
      _runOutput =
          (value['summary'] ?? value['error'] ?? value['resultText'] ?? '运行完成')
              .toString();
    } catch (error) {
      _runOutput = error.toString();
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _testPublicAPI() async {
    if (widget.scriptId == 'new' || (_record?['id'] ?? '').toString().isEmpty) {
      showPrismNotice(context, ('请先保存脚本，再测试对外接口').toString());
      return;
    }
    if (!_apiEnabled) {
      showPrismNotice(context, ('请先启用对外 API').toString());
      return;
    }
    try {
      final variables = _apiVariables.text.trim().isEmpty
          ? <dynamic>[]
          : jsonDecode(_apiVariables.text);
      if (variables is! List) throw const FormatException('变量必须是 JSON 数组');
      if (_apiRequest.text.trim().isNotEmpty &&
          jsonDecode(_apiRequest.text) is! Map) {
        throw const FormatException('请求 Body 必须是 JSON 对象');
      }
    } catch (error) {
      showPrismNotice(context, ('对外 API 配置无效：$error').toString());
      return;
    }
    await _save();
    if (!mounted) return;
    var body = _apiRequest.text.trim().isEmpty ? '{}' : _apiRequest.text.trim();
    try {
      final variables = jsonDecode(_apiVariables.text);
      if (variables is List) {
        for (final variable in variables.whereType<Map>()) {
          final name = (variable['name'] ?? '').toString().trim();
          final value = (variable['defaultValue'] ?? '').toString();
          if (name.isNotEmpty) {
            body = body.replaceAll('{{$name}}', value);
          }
        }
      }
    } catch (_) {}
    setState(() {
      _busy = 'public-api';
      _runOutput = '正在测试对外 API…';
    });
    try {
      final info = await WailsBridge.call('GetLaunchServerInfo');
      final baseUrl = info is Map
          ? (info['baseUrl'] ?? '').toString().replaceAll(RegExp(r'/+$'), '')
          : '';
      final path = _normalizePublicApiPath(_apiPath.text);
      if (baseUrl.isEmpty || path.isEmpty) {
        throw StateError('请确认 Launch Server 已启动，并填写接口路径');
      }
      final result = await WailsBridge.call('AutomationScriptInvokePublicAPI', [
        {
          'url': '$baseUrl/api/automation/hooks/$path',
          'method': 'POST',
          'bodyText': body,
          'apiKey': '',
          'authHeader': '',
          'timeoutMs': (int.tryParse(_apiTimeout.text) ?? 300000).clamp(
            1000,
            1800000,
          ),
        },
      ]);
      final value = result is Map ? Map<String, dynamic>.from(result) : {};
      _runOutput =
          'HTTP ${value['status'] ?? ''} ${value['statusText'] ?? ''}\n${value['bodyText'] ?? ''}';
    } catch (error) {
      _runOutput = error.toString();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
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

  @override
  Widget build(BuildContext context) => _loading
      ? const Center(child: PrismProgressIndicator())
      : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                prism.IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                const Expanded(
                  child: Text(
                    '脚本详情',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                PrismPopupMenuButton<String>(
                  enabled: _busy.isEmpty && widget.scriptId != 'new',
                  onSelected: (action) async {
                    if (action.startsWith('export-')) {
                      try {
                        final format = action.substring('export-'.length);
                        final method = switch (format) {
                          'json' => 'AutomationScriptExport',
                          'directory' => 'AutomationScriptExportDirectory',
                          _ => 'AutomationScriptExportZip',
                        };
                        final result = await WailsBridge.call(method, [
                          widget.scriptId,
                        ]);
                        if (mounted &&
                            result is Map &&
                            result['message'] != null) {
                          showPrismNotice(
                            context,
                            (result['message'].toString()).toString(),
                          );
                        }
                      } catch (error) {
                        if (mounted) {
                          showPrismNotice(
                            context,
                            (error.toString()).toString(),
                          );
                        }
                      }
                    } else if (action == 'delete') {
                      final yes = await showPrismDialog<bool>(
                        context: context,
                        useRootNavigator: false,
                        builder: (context) => PrismDialog(
                          title: const Text('删除脚本？'),
                          content: Text('将删除“${_name.text}”及其本地文件。'),
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
                        await WailsBridge.call('AutomationScriptDelete', [
                          widget.scriptId,
                        ]);
                        widget.onBack();
                      }
                    } else if (action == 'refresh') {
                      try {
                        final refreshed = await WailsBridge.call(
                          'AutomationScriptRefresh',
                          [widget.scriptId],
                        );
                        _record = Map<String, dynamic>.from(refreshed as Map);
                        _name.text = (_record!['name'] ?? '').toString();
                        _description.text = (_record!['description'] ?? '')
                            .toString();
                        _selector.text = (_record!['selectorText'] ?? '{}')
                            .toString();
                        _params.text = (_record!['paramsText'] ?? '{}')
                            .toString();
                        _script.text = (_record!['scriptText'] ?? '')
                            .toString();
                        final publicApi = _record!['publicAPI'] is Map
                            ? Map<String, dynamic>.from(
                                _record!['publicAPI'] as Map,
                              )
                            : <String, dynamic>{};
                        _apiEnabled = publicApi['enabled'] == true;
                        _apiPath.text = (publicApi['path'] ?? '').toString();
                        _apiRequestMode =
                            (publicApi['requestMode'] ?? 'standard').toString();
                        _apiResponseMode =
                            (publicApi['responseMode'] ?? 'envelope')
                                .toString();
                        _apiTimeout.text = (publicApi['timeoutMs'] ?? 300000)
                            .toString();
                        _apiRequest.text = (publicApi['requestBodyText'] ?? '')
                            .toString();
                        _apiResponse.text =
                            (publicApi['responseBodyText'] ?? '').toString();
                        _apiVariables.text = const JsonEncoder.withIndent('  ')
                            .convert(publicApi['variables'] ?? []);
                        if (mounted) setState(() {});
                      } catch (error) {
                        if (mounted) {
                          showPrismNotice(
                            context,
                            (error.toString()).toString(),
                          );
                        }
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PrismMenuItem(
                      value: 'export-json',
                      child: Text('导出 JSON 模板'),
                    ),
                    PrismMenuItem(
                      value: 'export-directory',
                      child: Text('导出目录'),
                    ),
                    PrismMenuItem(value: 'export-zip', child: Text('导出 ZIP')),
                    PrismMenuItem(value: 'refresh', child: Text('按来源重新导入')),
                    PrismMenuItem(value: 'delete', child: Text('删除脚本')),
                  ],
                ),
                prism.OutlinedButton.icon(
                  onPressed:
                      _busy.isEmpty &&
                          (_record?['id'] ?? widget.scriptId) != '' &&
                          (_record?['id'] ?? widget.scriptId) != 'new'
                      ? _run
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_busy == 'run' ? '运行中' : '试运行'),
                ),
                const SizedBox(width: 8),
                prism.FilledButton.icon(
                  onPressed: _busy.isEmpty ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_busy == 'save' ? '保存中' : '保存'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            PrismTextField(
              controller: _name,
              decoration: const PrismInputDecoration(labelText: '脚本名称'),
            ),
            if (widget.scriptId == 'new')
              PrismDropdownField<String>(
                initialValue: (_record?['type'] ?? 'playwright-cdp').toString(),
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
            PrismTextField(
              controller: _description,
              decoration: const PrismInputDecoration(labelText: '说明'),
            ),
            PrismDropdownField<String>(
              initialValue:
                  _profiles.any(
                    (profile) => profile['profileId'] == _targetProfileId,
                  )
                  ? _targetProfileId
                  : null,
              decoration: const PrismInputDecoration(labelText: '试运行目标实例'),
              items: [
                for (final profile in _profiles)
                  PrismDropdownItem(
                    value: profile['profileId']?.toString(),
                    child: Text(
                      '${profile['profileName'] ?? '未命名实例'}${profile['running'] == true ? ' · 运行中' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _targetProfileId = value),
            ),
            PrismTextField(
              controller: _selector,
              minLines: 2,
              maxLines: 6,
              decoration: const PrismInputDecoration(labelText: '目标选择器 JSON'),
            ),
            PrismTextField(
              controller: _params,
              minLines: 2,
              maxLines: 8,
              decoration: const PrismInputDecoration(labelText: '运行参数 JSON'),
            ),
            const SizedBox(height: 12),
            PrismTextField(
              controller: _script,
              minLines: 12,
              maxLines: 30,
              decoration: const PrismInputDecoration(labelText: '脚本内容'),
            ),
            const SizedBox(height: 14),
            PrismCard(
              child: Padding(
                padding: const EdgeInsets.all(14),
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
                                _apiPath.text = _name.text
                                    .trim()
                                    .toLowerCase()
                                    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
                                    .replaceAll(RegExp(r'^-+|-+$'), '');
                              }
                            })
                          : null,
                    ),
                    if (_apiEnabled) ...[
                      PrismTextField(
                        controller: _apiPath,
                        decoration: const PrismInputDecoration(
                          labelText: '接口路径',
                        ),
                      ),
                      PrismDropdownField<String>(
                        initialValue: _apiRequestMode,
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
                      PrismDropdownField<String>(
                        initialValue: _apiResponseMode,
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
                      PrismTextField(
                        controller: _apiTimeout,
                        keyboardType: TextInputType.number,
                        decoration: const PrismInputDecoration(
                          labelText: '超时（毫秒）',
                        ),
                      ),
                      PrismTextField(
                        controller: _apiRequest,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const PrismInputDecoration(
                          labelText: '请求 Body JSON',
                        ),
                      ),
                      PrismTextField(
                        controller: _apiResponse,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const PrismInputDecoration(
                          labelText: '响应示例 JSON（可选）',
                        ),
                      ),
                      PrismTextField(
                        controller: _apiVariables,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const PrismInputDecoration(
                          labelText: '变量配置 JSON 数组',
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: prism.OutlinedButton.icon(
                          onPressed: _busy.isEmpty ? _testPublicAPI : null,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            _busy == 'public-api' ? '测试中…' : '保存并测试接口',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_runOutput.isNotEmpty) ...[
              const SizedBox(height: 12),
              PrismCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: prism.SelectableText(_runOutput),
                ),
              ),
            ],
          ],
        );
}
