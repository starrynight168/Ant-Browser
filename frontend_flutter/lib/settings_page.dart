import 'dart:convert';

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'theme_state.dart';
import 'app_bridge.dart';

const _defaultAppSettings = <String, dynamic>{
  'appName': 'Ant Browser',
  'appDescription': '基于 Flutter 与 Go 的桌面应用',
  'theme': 'light',
  'primaryColor': '#3B82F6',
  'language': 'zh-CN',
  'enableNotifications': true,
  'enableAutoSave': true,
  'autoSaveInterval': 30,
  'maxUploadSize': 10,
  'sessionTimeout': 30,
  'cacheEnabled': true,
  'logLevel': 'info',
  'maxMemoryMB': 1024,
  'gcPercent': 100,
};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _launchPortController = TextEditingController(text: '19876');
  final _systemNodePathController = TextEditingController();
  Map<String, dynamic> _settings = Map<String, dynamic>.from(
    _defaultAppSettings,
  );
  Map<String, dynamic> _automation = {};
  Map<String, dynamic> _launchServer = {};
  Map<String, dynamic>? _runtimeCheck;
  Map<String, dynamic>? _nodeProbe;
  String _nodeSource = 'auto';
  bool _loading = true;
  bool _saving = false;
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _launchPortController.dispose();
    _systemNodePathController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = AppBridge.readStorage('app_settings');
      final stored = raw.isEmpty ? null : jsonDecode(raw);
      final settings = <String, dynamic>{
        ..._defaultAppSettings,
        if (stored is Map) ...Map<String, dynamic>.from(stored),
      };
      final results = await Future.wait([
        AppBridge.call('GetAutomationState'),
        AppBridge.call('GetLaunchServerInfo'),
        AppBridge.call('GetLogLevel'),
      ]);
      final automation = _asMap(results[0]);
      final launchServer = _asMap(results[1]);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _automation = automation;
        _launchServer = launchServer;
        _nodeSource =
            '${_nested(automation, 'settings')['nodeSource'] ?? 'auto'}';
        _systemNodePathController.text =
            '${_nested(automation, 'settings')['systemNodePath'] ?? ''}';
        _launchPortController.text =
            '${launchServer['preferredPort'] ?? launchServer['port'] ?? 19876}';
        if (results[2] is String && '${results[2]}'.isNotEmpty)
          _settings['logLevel'] = '${results[2]}'.toLowerCase();
      });
      setAppThemeMode('${settings['theme'] ?? 'light'}');
    } catch (error) {
      if (mounted) _message('设置加载失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Map<String, dynamic> _nested(Map<String, dynamic> value, String key) =>
      _asMap(value[key]);

  void _change(String key, dynamic value) {
    setState(() => _settings = {..._settings, key: value});
  }

  bool _bool(String key) => _settings[key] == true;

  int _int(String key, int fallback) =>
      int.tryParse('${_settings[key] ?? ''}') ?? fallback;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      AppBridge.writeStorage('app_settings', jsonEncode(_settings));
      await AppBridge.call('SetLogLevel', [
        '${_settings['logLevel'] ?? 'info'}',
      ]);
      setAppThemeMode('${_settings['theme'] ?? 'light'}');
      _message('设置已保存');
    } catch (error) {
      _message('保存设置失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final confirm = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('恢复默认设置？'),
        content: const Text('这会重置应用的托管设置。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await AppBridge.call('ResetManagedSettings');
      AppBridge.removeStorage('app_settings');
      setState(
        () => _settings = Map<String, dynamic>.from(_defaultAppSettings),
      );
      setAppThemeMode('light');
      await _load();
      _message('已恢复默认设置');
    } catch (error) {
      _message('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAutomation(bool enabled, bool headless) async {
    setState(() => _busy = 'automation');
    try {
      final result = await AppBridge.call('SaveAutomationSettings', [
        enabled,
        headless,
      ]);
      if (mounted) setState(() => _automation = _asMap(result));
      _message(enabled ? '自动化支持已开启' : '自动化支持已关闭');
    } catch (error) {
      _message('自动化设置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _saveRuntime() async {
    setState(() => _busy = 'runtime');
    try {
      final result = await AppBridge.call('SaveAutomationRuntimeSettings', [
        _nodeSource,
        _systemNodePathController.text.trim(),
      ]);
      if (mounted) setState(() => _automation = _asMap(result));
      _message('运行时设置已保存');
    } catch (error) {
      _message('保存运行时设置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _installRuntime() async {
    setState(() => _busy = 'install');
    try {
      final result = await AppBridge.call('InstallAutomationRuntime');
      if (mounted) setState(() => _automation = _asMap(result));
      _message('已提交自动化运行时安装');
    } catch (error) {
      _message('安装运行时失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _checkRuntime() async {
    setState(() => _busy = 'check');
    try {
      final result = await AppBridge.call('AutomationRuntimeSelfCheck');
      if (mounted) setState(() => _runtimeCheck = _asMap(result));
    } catch (error) {
      if (mounted)
        setState(() => _runtimeCheck = {'ok': false, 'error': '$error'});
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _probeNode() async {
    setState(() => _busy = 'probe');
    try {
      final result = await AppBridge.call('AutomationProbeSystemNode', [
        _systemNodePathController.text.trim(),
      ]);
      if (mounted) setState(() => _nodeProbe = _asMap(result));
    } catch (error) {
      if (mounted)
        setState(() => _nodeProbe = {'ok': false, 'error': '$error'});
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _saveLaunchServer() async {
    final port = int.tryParse(_launchPortController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      _message('请输入 1 到 65535 之间的端口');
      return;
    }
    setState(() => _busy = 'launch');
    try {
      final result = await AppBridge.call('SaveLaunchServerSettings', [port]);
      if (mounted) setState(() => _launchServer = _asMap(result));
      _message('启动接口设置已保存');
    } catch (error) {
      _message('保存启动接口设置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _toggleTypeScript(bool enabled) async {
    setState(() => _busy = 'package');
    try {
      final result = await AppBridge.call(
        'SaveAutomationScriptPackageSettings',
        [enabled],
      );
      if (mounted) setState(() => _automation = _asMap(result));
      _message(enabled ? '已允许构建 TypeScript 脚本' : '已关闭 TypeScript 构建');
    } catch (error) {
      _message('保存脚本设置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  void _message(String value) {
    if (mounted) showPrismNotice(context, (value).toString());
  }

  @override
  Widget build(BuildContext context) {
    final automationSettings = _nested(_automation, 'settings');
    final automationStatus = _nested(_automation, 'status');
    final automationEnabled = automationSettings['enabled'] == true;
    final automationReady = automationStatus['ready'] == true;
    if (_loading) return const Center(child: PrismProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('配置应用外观、功能和本地服务。')),
                  prism.OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restore, size: 17),
                    label: const Text('恢复默认'),
                  ),
                  const SizedBox(width: 8),
                  prism.FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined, size: 17),
                    label: Text(_saving ? '保存中' : '保存'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                title: '外观与应用信息',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _textField('应用名称', 'appName')),
                        const SizedBox(width: 12),
                        Expanded(child: _textField('界面语言', 'language')),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrismDropdownField<String>(
                            initialValue: '${_settings['theme']}',
                            decoration: const PrismInputDecoration(
                              labelText: '主题',
                              isDense: true,
                            ),
                            items: const [
                              PrismDropdownItem(
                                value: 'light',
                                child: Text('浅色'),
                              ),
                              PrismDropdownItem(
                                value: 'dark',
                                child: Text('深色'),
                              ),
                              PrismDropdownItem(
                                value: 'system',
                                child: Text('跟随系统'),
                              ),
                            ],
                            onChanged: (value) =>
                                _change('theme', value ?? 'light'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _textField('应用说明', 'appDescription', maxLines: 2),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: '基础功能',
                child: Column(
                  children: [
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('保存通知历史'),
                      subtitle: const Text('在通知中心保留错误和运行状态提醒'),
                      value: _bool('enableNotifications'),
                      onChanged: (value) =>
                          _change('enableNotifications', value),
                    ),
                    const prism.Divider(height: 1),
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动保存'),
                      value: _bool('enableAutoSave'),
                      onChanged: (value) => _change('enableAutoSave', value),
                    ),
                    Row(
                      children: [
                        const Expanded(child: Text('自动保存间隔（秒）')),
                        SizedBox(
                          width: 140,
                          child: _numberField(
                            'autoSaveInterval',
                            min: 1,
                            max: 3600,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Expanded(child: Text('最大上传大小（MB）')),
                        SizedBox(
                          width: 140,
                          child: _numberField(
                            'maxUploadSize',
                            min: 1,
                            max: 1024,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: '运行与日志',
                child: Column(
                  children: [
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用本地缓存'),
                      value: _bool('cacheEnabled'),
                      onChanged: (value) => _change('cacheEnabled', value),
                    ),
                    Row(
                      children: [
                        const Expanded(child: Text('会话超时（分钟）')),
                        SizedBox(
                          width: 140,
                          child: _numberField(
                            'sessionTimeout',
                            min: 1,
                            max: 1440,
                          ),
                        ),
                        const SizedBox(width: 22),
                        const Expanded(child: Text('最大内存（MB）')),
                        SizedBox(
                          width: 140,
                          child: _numberField(
                            'maxMemoryMB',
                            min: 128,
                            max: 32768,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(child: Text('垃圾回收阈值')),
                        SizedBox(
                          width: 140,
                          child: _numberField('gcPercent', min: 10, max: 1000),
                        ),
                        const SizedBox(width: 22),
                        const Expanded(child: Text('日志级别')),
                        Expanded(
                          child: PrismDropdownField<String>(
                            initialValue: '${_settings['logLevel']}',
                            decoration: const PrismInputDecoration(
                              isDense: true,
                            ),
                            items: const ['debug', 'info', 'warn', 'error']
                                .map(
                                  (value) => PrismDropdownItem(
                                    value: value,
                                    child: Text(value.toUpperCase()),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                _change('logLevel', value ?? 'info'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: '自动化运行时',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 9,
                      color: automationReady
                          ? prism.Theme.of(context).colorScheme.tertiary
                          : prism.Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      automationReady
                          ? '就绪'
                          : automationStatus['installing'] == true
                          ? '安装中'
                          : '未就绪',
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用自动化脚本支持'),
                      value: automationEnabled,
                      onChanged: _busy.isEmpty
                          ? (value) => _saveAutomation(
                              value,
                              automationSettings['headlessDefault'] == true,
                            )
                          : null,
                    ),
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('默认无头模式'),
                      value: automationSettings['headlessDefault'] == true,
                      onChanged: _busy.isEmpty
                          ? (value) => _saveAutomation(automationEnabled, value)
                          : null,
                    ),
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许构建 TypeScript 脚本'),
                      value: automationSettings['allowTypeScriptBuild'] == true,
                      onChanged: _busy.isEmpty ? _toggleTypeScript : null,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: PrismDropdownField<String>(
                            initialValue: _nodeSource,
                            decoration: const PrismInputDecoration(
                              labelText: 'Node 来源',
                              isDense: true,
                            ),
                            items: const [
                              PrismDropdownItem(
                                value: 'auto',
                                child: Text('自动选择'),
                              ),
                              PrismDropdownItem(
                                value: 'system',
                                child: Text('系统 Node'),
                              ),
                              PrismDropdownItem(
                                value: 'bundled',
                                child: Text('内置运行时'),
                              ),
                            ],
                            onChanged: _busy.isEmpty
                                ? (value) => setState(
                                    () => _nodeSource = value ?? 'auto',
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrismTextField(
                            controller: _systemNodePathController,
                            decoration: const PrismInputDecoration(
                              labelText: '系统 Node 路径（可选）',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        prism.OutlinedButton(
                          onPressed: _busy.isEmpty ? _probeNode : null,
                          child: const Text('检测'),
                        ),
                      ],
                    ),
                    if (_nodeProbe != null)
                      _ResultLine(
                        text: _nodeProbe!['ok'] == true
                            ? 'Node 可用：${_nodeProbe!['version'] ?? ''}'
                            : '${_nodeProbe!['error'] ?? '未检测到 Node'}',
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        prism.OutlinedButton(
                          onPressed: _busy.isEmpty ? _saveRuntime : null,
                          child: const Text('保存运行时配置'),
                        ),
                        prism.OutlinedButton(
                          onPressed: _busy.isEmpty ? _installRuntime : null,
                          child: Text(_busy == 'install' ? '安装中' : '安装运行时'),
                        ),
                        prism.OutlinedButton(
                          onPressed: _busy.isEmpty ? _checkRuntime : null,
                          child: const Text('运行自检'),
                        ),
                      ],
                    ),
                    if (_runtimeCheck != null)
                      _ResultLine(
                        text: _runtimeCheck!['ok'] == true
                            ? '自检通过：Node ${_runtimeCheck!['nodeVersion'] ?? ''}，Playwright ${_runtimeCheck!['playwrightVersion'] ?? ''}'
                            : '${_runtimeCheck!['error'] ?? '自检未通过'}',
                      ),
                    if ('${automationStatus['lastError'] ?? ''}'.isNotEmpty)
                      _ResultLine(
                        text: '${automationStatus['lastError']}',
                        error: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: '本地启动接口',
                trailing: Text(
                  _launchServer['ready'] == true
                      ? '${_launchServer['baseUrl'] ?? ''} 已启动'
                      : '未启动',
                  style: TextStyle(
                    color: _launchServer['ready'] == true
                        ? prism.Theme.of(context).colorScheme.tertiary
                        : prism.Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(child: Text('监听端口')),
                    SizedBox(
                      width: 180,
                      child: PrismTextField(
                        controller: _launchPortController,
                        keyboardType: TextInputType.number,
                        decoration: const PrismInputDecoration(isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PrismTonalButton(
                      onPressed: _busy.isEmpty ? _saveLaunchServer : null,
                      child: Text(_busy == 'launch' ? '保存中' : '保存端口'),
                    ),
                  ],
                ),
              ),
              if (_busy.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: prism.LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField(String label, String key, {int maxLines = 1}) =>
      PrismTextFormField(
        initialValue: '${_settings[key] ?? ''}',
        maxLines: maxLines,
        decoration: PrismInputDecoration(labelText: label, isDense: true),
        onChanged: (value) => _change(key, value),
      );

  Widget _numberField(String key, {required int min, required int max}) =>
      PrismTextFormField(
        key: ValueKey('$key-${_settings[key]}'),
        initialValue: '${_int(key, min)}',
        keyboardType: TextInputType.number,
        decoration: const PrismInputDecoration(isDense: true),
        onChanged: (value) {
          final parsed = int.tryParse(value);
          if (parsed != null) _change(key, parsed.clamp(min, max).toInt());
        },
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return PrismCard(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: prism.Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(
        color: error
            ? prism.Theme.of(context).colorScheme.error
            : prism.Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
    ),
  );
}
