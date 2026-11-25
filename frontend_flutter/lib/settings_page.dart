import 'dart:convert';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';
import 'theme_state.dart';

const _defaultAppSettings = <String, dynamic>{
  'appName': 'Ant Browser',
  'appDescription': '基于 Flutter 与 Go 的桌面应用',
  'theme': 'light',
  'themeColor': 'forest',
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

const _numberBounds = <String, (int min, int max)>{
  'autoSaveInterval': (5, 300),
  'maxUploadSize': (1, 1024),
  'sessionTimeout': (1, 1440),
  'maxMemoryMB': (128, 32768),
  'gcPercent': (10, 1000),
};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _launchPortController = TextEditingController(text: '19876');
  final _systemNodePathController = TextEditingController();
  final _appNameController = TextEditingController();
  final _appDescriptionController = TextEditingController();
  final Map<String, TextEditingController> _numberControllers = {};
  final Map<String, FocusNode> _numberFocusNodes = {};

  Map<String, dynamic> _settings = Map<String, dynamic>.from(
    _defaultAppSettings,
  );
  Map<String, dynamic> _savedSettings = Map<String, dynamic>.from(
    _defaultAppSettings,
  );
  Map<String, dynamic> _automation = {};
  Map<String, dynamic> _launchServer = {};
  Map<String, dynamic>? _runtimeCheck;
  Map<String, dynamic>? _nodeProbe;
  Map<String, dynamic>? _runtimeProgress;

  String _nodeSource = 'auto';
  String _savedNodeSource = 'auto';
  String _savedSystemNodePath = '';
  bool _loading = true;
  bool _saving = false;
  String _busy = '';
  void Function()? _unsubscribeRuntimeProgress;

  @override
  void initState() {
    super.initState();
    for (final entry in _numberBounds.entries) {
      final key = entry.key;
      final (min, max) = entry.value;
      _numberControllers[key] = TextEditingController(
        text: '${_defaultAppSettings[key]}',
      );
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) {
          _commitNumberField(key, min: min, max: max);
        }
      });
      _numberFocusNodes[key] = node;
    }
    _systemNodePathController.addListener(_onRuntimeInputChanged);
    _unsubscribeRuntimeProgress = AppBridge.onEvent(
      'automation:runtime:progress',
      _handleRuntimeProgress,
    );
    _load();
  }

  @override
  void dispose() {
    _unsubscribeRuntimeProgress?.call();
    _systemNodePathController.removeListener(_onRuntimeInputChanged);
    _launchPortController.dispose();
    _systemNodePathController.dispose();
    _appNameController.dispose();
    _appDescriptionController.dispose();
    for (final controller in _numberControllers.values) {
      controller.dispose();
    }
    for (final node in _numberFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onRuntimeInputChanged() {
    if (mounted) setState(() {});
  }

  void _handleRuntimeProgress(dynamic payload) {
    if (!mounted) return;
    final map = _asMap(payload);
    if (map.isEmpty) return;
    setState(() => _runtimeProgress = map);
    final phase = '${map['phase'] ?? ''}'.toLowerCase();
    if (phase == 'done' || phase == 'error') {
      _refreshAutomationState();
    }
  }

  Future<void> _refreshAutomationState() async {
    try {
      final result = await AppBridge.call('GetAutomationState');
      if (!mounted) return;
      final automation = _asMap(result);
      final rtSettings = _nested(automation, 'settings');
      setState(() {
        _automation = automation;
        _savedNodeSource = '${rtSettings['nodeSource'] ?? 'auto'}';
        _savedSystemNodePath = '${rtSettings['systemNodePath'] ?? ''}';
      });
    } catch (_) {}
  }

  bool get _hasChanges =>
      jsonEncode(_settings) != jsonEncode(_savedSettings);

  bool get _automationRuntimeDirty =>
      _nodeSource != _savedNodeSource ||
      _systemNodePathController.text.trim() != _savedSystemNodePath.trim();

  void _syncControllersFromSettings() {
    _appNameController.text = '${_settings['appName'] ?? ''}';
    _appDescriptionController.text = '${_settings['appDescription'] ?? ''}';
    for (final entry in _numberBounds.entries) {
      final key = entry.key;
      final (min, _) = entry.value;
      _numberControllers[key]?.text = '${_int(key, min)}';
    }
  }

  void _commitNumberField(String key, {required int min, required int max}) {
    final controller = _numberControllers[key];
    if (controller == null) return;
    final parsed = int.tryParse(controller.text.trim());
    final clamped = (parsed ?? _int(key, min)).clamp(min, max).toInt();
    if (controller.text != '$clamped') {
      controller.text = '$clamped';
    }
    if (_settings[key] != clamped) {
      setState(() => _settings = {..._settings, key: clamped});
    }
  }

  void _commitAllNumberFields() {
    for (final entry in _numberBounds.entries) {
      final (min, max) = entry.value;
      _commitNumberField(entry.key, min: min, max: max);
    }
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
      if (results[2] is String && '${results[2]}'.isNotEmpty) {
        settings['logLevel'] = '${results[2]}'.toLowerCase();
      }
      if (!mounted) return;
      final rtSettings = _nested(automation, 'settings');
      final nodeSource = '${rtSettings['nodeSource'] ?? 'auto'}';
      final sysNodePath = '${rtSettings['systemNodePath'] ?? ''}';
      setState(() {
        _settings = settings;
        _savedSettings = Map<String, dynamic>.from(settings);
        _automation = automation;
        _launchServer = launchServer;
        _nodeSource = nodeSource;
        _savedNodeSource = nodeSource;
        _savedSystemNodePath = sysNodePath;
        _systemNodePathController.text = sysNodePath;
        _launchPortController.text =
            '${launchServer['preferredPort'] ?? launchServer['port'] ?? 19876}';
        _syncControllersFromSettings();
      });
      setAppThemeMode('${settings['theme'] ?? 'light'}');
      setAppThemeColor('${settings['themeColor'] ?? 'forest'}');
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
    _commitAllNumberFields();
    final updated = <String, dynamic>{
      ..._settings,
      'appName': _appNameController.text,
      'appDescription': _appDescriptionController.text,
    };
    setState(() {
      _settings = updated;
      _saving = true;
    });
    try {
      AppBridge.writeStorage('app_settings', jsonEncode(updated));
      await AppBridge.call('SetLogLevel', [
        '${updated['logLevel'] ?? 'info'}',
      ]);
      setAppThemeMode('${updated['theme'] ?? 'light'}');
      setAppThemeColor('${updated['themeColor'] ?? 'forest'}');
      if (mounted) {
        setState(() => _savedSettings = Map<String, dynamic>.from(updated));
      }
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
      setState(() {
        _settings = Map<String, dynamic>.from(_defaultAppSettings);
        _savedSettings = Map<String, dynamic>.from(_defaultAppSettings);
        _syncControllersFromSettings();
      });
      setAppThemeMode('light');
      setAppThemeColor('forest');
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
      final sysPath = _systemNodePathController.text.trim();
      final result = await AppBridge.call('SaveAutomationRuntimeSettings', [
        _nodeSource,
        sysPath,
      ]);
      if (mounted) {
        final map = _asMap(result);
        setState(() {
          _automation = map;
          _savedNodeSource = _nodeSource;
          _savedSystemNodePath = sysPath;
        });
      }
      _message('运行时设置已保存');
    } catch (error) {
      _message('保存运行时设置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _installRuntime() async {
    setState(() {
      _busy = 'install';
      _runtimeProgress = {
        'phase': 'starting',
        'progress': 0.0,
        'component': 'runtime',
        'message': '正在准备安装自动化运行时…',
      };
    });
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
      if (mounted) {
        setState(() => _runtimeCheck = {'ok': false, 'error': '$error'});
      }
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
      if (mounted) {
        setState(() => _nodeProbe = {'ok': false, 'error': '$error'});
      }
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
    if (mounted) showPrismNotice(context, value);
  }

  double? _parseProgress(dynamic raw) {
    if (raw is num) {
      final d = raw.toDouble();
      if (d > 1.0) return (d / 100.0).clamp(0.0, 1.0);
      return d.clamp(0.0, 1.0);
    }
    final parsed = double.tryParse('$raw');
    if (parsed == null) return null;
    return parsed > 1.0
        ? (parsed / 100.0).clamp(0.0, 1.0)
        : parsed.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final automationSettings = _nested(_automation, 'settings');
    final automationStatus = _nested(_automation, 'status');
    final automationEnabled = automationSettings['enabled'] == true;
    final automationReady = automationStatus['ready'] == true;
    final automationInstalled = automationStatus['installed'] == true;
    final automationInstalling = automationStatus['installing'] == true;
    final bundledOnly = _nodeSource == 'bundled';
    final launchReady = _launchServer['ready'] == true;

    if (_loading) return const Center(child: PrismProgressIndicator());

    final runtimeDetails = <(String, String)>[
      if ('${automationStatus['runtimeVersion'] ?? ''}'.isNotEmpty)
        ('运行时版本', '${automationStatus['runtimeVersion']}'),
      if ('${automationStatus['nodeVersion'] ?? ''}'.isNotEmpty)
        ('Node 版本', '${automationStatus['nodeVersion']}'),
      if ('${automationStatus['playwrightVersion'] ?? ''}'.isNotEmpty)
        ('Playwright 版本', '${automationStatus['playwrightVersion']}'),
      if ('${automationStatus['nodeResolution'] ?? ''}'.isNotEmpty)
        ('Node 解析来源', '${automationStatus['nodeResolution']}'),
      if ('${automationStatus['nodePath'] ?? ''}'.isNotEmpty)
        ('Node 路径', '${automationStatus['nodePath']}'),
      if ('${automationStatus['runtimeDir'] ?? ''}'.isNotEmpty)
        ('运行时目录', '${automationStatus['runtimeDir']}'),
      if (automationStatus.containsKey('systemNodeDetected'))
        (
          '系统 Node 检测',
          automationStatus['systemNodeDetected'] == true ? '已检测到' : '未检测到',
        ),
      if ('${automationStatus['systemNodePath'] ?? ''}'.isNotEmpty)
        ('系统 Node 路径', '${automationStatus['systemNodePath']}'),
      if ('${automationStatus['systemNodeError'] ?? ''}'.isNotEmpty)
        ('系统 Node 错误', '${automationStatus['systemNodeError']}'),
    ];

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
                  Expanded(
                    child: Text(
                      '配置应用外观、功能和本地服务。',
                      style: prism.AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  if (_hasChanges) ...[
                    const PrismBadge(
                      label: '有未保存更改',
                      tone: PrismTone.warning,
                      dot: true,
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  prism.OutlinedButton.icon(
                    onPressed: _saving ? null : _reset,
                    icon: const PrismGlyph(AntGlyphs.restore, size: 17),
                    label: const Text('恢复默认'),
                  ),
                  prism.FilledButton.icon(
                    onPressed: _saving || !_hasChanges ? null : _save,
                    icon: const PrismGlyph(AntGlyphs.save, size: 17),
                    label: Text(_saving ? '保存中' : '保存'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              PrismSectionCard(
                title: '外观与应用信息',
                glyph: AntGlyphs.tune,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _textField(
                            '应用名称',
                            'appName',
                            _appNameController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrismDropdownField<String>(
                            value: '${_settings['language']}',
                            decoration: const PrismInputDecoration(
                              labelText: '界面语言',
                              isDense: true,
                            ),
                            items: const [
                              PrismDropdownItem(
                                value: 'zh-CN',
                                child: Text('简体中文'),
                              ),
                              PrismDropdownItem(
                                value: 'en-US',
                                child: Text('English'),
                              ),
                            ],
                            onChanged: (value) =>
                                _change('language', value ?? 'zh-CN'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrismDropdownField<String>(
                            value: '${_settings['theme'] ?? 'light'}',
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
                            onChanged: (value) {
                              final theme = value ?? 'light';
                              _change('theme', theme);
                              setAppThemeMode(theme);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    PrismDropdownField<String>(
                      value: '${_settings['themeColor'] ?? 'forest'}',
                      decoration: const PrismInputDecoration(
                        labelText: '主题配色',
                        isDense: true,
                      ),
                      items: const [
                        PrismDropdownItem(value: 'forest', child: Text('森林绿')),
                        PrismDropdownItem(value: 'ocean', child: Text('海洋蓝')),
                        PrismDropdownItem(value: 'violet', child: Text('薰衣草紫')),
                        PrismDropdownItem(value: 'rose', child: Text('玫瑰粉')),
                        PrismDropdownItem(value: 'amber', child: Text('琥珀橙')),
                        PrismDropdownItem(value: 'teal', child: Text('青碧色')),
                        PrismDropdownItem(value: 'slate', child: Text('石墨灰')),
                        PrismDropdownItem(value: 'red', child: Text('中国红')),
                      ],
                      onChanged: (value) {
                        final color = value ?? 'forest';
                        _change('themeColor', color);
                        setAppThemeColor(color);
                      },
                    ),
                    const SizedBox(height: 10),
                    _textField(
                      '应用说明',
                      'appDescription',
                      _appDescriptionController,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrismSectionCard(
                title: '基础功能',
                glyph: AntGlyphs.settings,
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
                    if (_bool('enableAutoSave')) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Text('自动保存间隔（秒）')),
                          SizedBox(
                            width: 140,
                            child: _numberField('autoSaveInterval'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(child: Text('最大上传大小（MB）')),
                        SizedBox(
                          width: 140,
                          child: _numberField('maxUploadSize'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrismSectionCard(
                title: '运行与日志',
                glyph: AntGlyphs.logs,
                child: Column(
                  children: [
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用本地缓存'),
                      value: _bool('cacheEnabled'),
                      onChanged: (value) => _change('cacheEnabled', value),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(child: Text('会话超时（分钟）')),
                        SizedBox(
                          width: 140,
                          child: _numberField('sessionTimeout'),
                        ),
                        const SizedBox(width: 22),
                        const Expanded(child: Text('最大内存（MB）')),
                        SizedBox(
                          width: 140,
                          child: _numberField('maxMemoryMB'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(child: Text('垃圾回收阈值')),
                        SizedBox(
                          width: 140,
                          child: _numberField('gcPercent'),
                        ),
                        const SizedBox(width: 22),
                        const Expanded(child: Text('日志级别')),
                        Expanded(
                          child: PrismDropdownField<String>(
                            value: '${_settings['logLevel'] ?? 'info'}',
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
              PrismSectionCard(
                title: '自动化运行时',
                glyph: AntGlyphs.robot,
                actions: [
                  if (_automationRuntimeDirty)
                    const PrismBadge(
                      label: '配置已修改',
                      tone: PrismTone.warning,
                      dot: true,
                    ),
                  PrismBadge(
                    label: automationReady
                        ? '就绪'
                        : automationInstalling
                        ? '安装中'
                        : '未就绪',
                    tone: automationReady
                        ? PrismTone.success
                        : automationInstalling
                        ? PrismTone.warning
                        : PrismTone.danger,
                    dot: true,
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: PrismDropdownField<String>(
                            value: _nodeSource,
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
                            enabled: !bundledOnly && _busy.isEmpty,
                            decoration: PrismInputDecoration(
                              labelText: '系统 Node 路径（可选）',
                              hintText: bundledOnly ? '内置运行时模式无需填写' : null,
                              isDense: true,
                              enabled: !bundledOnly && _busy.isEmpty,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        prism.OutlinedButton.icon(
                          onPressed:
                              _busy.isEmpty && !bundledOnly ? _probeNode : null,
                          icon: const PrismGlyph(AntGlyphs.search, size: 15),
                          label: const Text('检测'),
                        ),
                      ],
                    ),
                    if (_nodeProbe != null) ...[
                      const SizedBox(height: 10),
                      PrismBanner(
                        tone: _nodeProbe!['ok'] == true
                            ? PrismTone.success
                            : PrismTone.danger,
                        title: _nodeProbe!['ok'] == true
                            ? 'Node 可用：${_nodeProbe!['version'] ?? ''}'
                            : '系统 Node 检测失败',
                        message: _nodeProbe!['ok'] == true
                            ? ('${_nodeProbe!['path'] ?? ''}'.isNotEmpty
                                  ? '路径：${_nodeProbe!['path']}'
                                  : '已通过系统 Node 探测')
                            : '${_nodeProbe!['error'] ?? '未检测到 Node'}',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        PrismTonalButton.icon(
                          onPressed: _busy.isEmpty && _automationRuntimeDirty
                              ? _saveRuntime
                              : null,
                          icon: const PrismGlyph(AntGlyphs.save, size: 16),
                          child: const Text('保存运行时配置'),
                        ),
                        prism.OutlinedButton.icon(
                          onPressed:
                              _busy.isEmpty && !automationInstalling
                                  ? _installRuntime
                                  : null,
                          icon: const PrismGlyph(AntGlyphs.download, size: 16),
                          label: Text(
                            automationInstalling || _busy == 'install'
                                ? '安装中'
                                : automationInstalled
                                ? '修复/重装运行时'
                                : '安装运行时',
                          ),
                        ),
                        prism.OutlinedButton.icon(
                          onPressed: _busy.isEmpty && automationReady
                              ? _checkRuntime
                              : null,
                          icon: const PrismGlyph(AntGlyphs.factCheck, size: 16),
                          label: const Text('运行自检'),
                        ),
                      ],
                    ),
                    if (_runtimeProgress != null) ...[
                      const SizedBox(height: 12),
                      _buildRuntimeProgressPanel(_runtimeProgress!),
                    ],
                    if (_runtimeCheck != null) ...[
                      const SizedBox(height: 10),
                      PrismBanner(
                        tone: _runtimeCheck!['ok'] == true
                            ? PrismTone.success
                            : PrismTone.danger,
                        message: _runtimeCheck!['ok'] == true
                            ? '自检通过：Node ${_runtimeCheck!['nodeVersion'] ?? ''}，Playwright ${_runtimeCheck!['playwrightVersion'] ?? ''}'
                            : '${_runtimeCheck!['error'] ?? '自检未通过'}',
                      ),
                    ],
                    if ('${automationStatus['lastError'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      PrismBanner(
                        tone: PrismTone.danger,
                        title: '运行时错误',
                        message: '${automationStatus['lastError']}',
                      ),
                    ],
                    if (runtimeDetails.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      prism.Surface(
                        color: colors.surfaceContainerLow,
                        shape: prism.AppShape.lg,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '运行时详情',
                                style: prism.AppTextStyle.footnote
                                    .of(context, emphasized: true)
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 8),
                              for (final (label, value) in runtimeDetails)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 120,
                                        child: Text(
                                          label,
                                          style: prism.AppTextStyle.caption1
                                              .of(context)
                                              .copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      Expanded(
                                        child: prism.SelectableText(
                                          value,
                                          style: prism.AppTextStyle.caption1
                                              .of(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrismSectionCard(
                title: '本地启动接口',
                glyph: AntGlyphs.api,
                actions: [
                  PrismBadge(
                    label: launchReady
                        ? '${_launchServer['baseUrl'] ?? ''} 已启动'
                        : '未启动',
                    tone: launchReady ? PrismTone.success : PrismTone.neutral,
                    dot: true,
                  ),
                ],
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

  Widget _buildRuntimeProgressPanel(Map<String, dynamic> event) {
    final phase = '${event['phase'] ?? ''}'.trim();
    final component = '${event['component'] ?? ''}'.trim();
    final message = '${event['message'] ?? ''}'.trim();
    final progress = _parseProgress(event['progress']);
    final phaseLabel = switch (phase.toLowerCase()) {
      'done' => '安装完成',
      'error' => '安装失败',
      'download' || 'downloading' => '正在下载',
      'extract' || 'extracting' => '正在解压',
      'install' || 'installing' => '正在安装',
      'verify' || 'verifying' => '正在校验',
      _ => phase.isEmpty ? '运行时任务' : '阶段：$phase',
    };
    final title = component.isNotEmpty ? '$phaseLabel · $component' : phaseLabel;
    final tone = switch (phase.toLowerCase()) {
      'done' => PrismTone.success,
      'error' => PrismTone.danger,
      _ => PrismTone.info,
    };
    return PrismProgressPanel(
      title: title,
      subtitle: message.isNotEmpty ? message : null,
      progress: progress,
      trailing: PrismBadge(label: phase.isEmpty ? '进行中' : phase, tone: tone),
    );
  }

  Widget _textField(
    String label,
    String key,
    TextEditingController controller, {
    int maxLines = 1,
  }) => PrismTextField(
    controller: controller,
    maxLines: maxLines,
    decoration: PrismInputDecoration(labelText: label, isDense: true),
    onChanged: (value) => _change(key, value),
  );

  Widget _numberField(String key) {
    final (min, max) = _numberBounds[key]!;
    return PrismTextField(
      controller: _numberControllers[key],
      focusNode: _numberFocusNodes[key],
      keyboardType: TextInputType.number,
      decoration: const PrismInputDecoration(isDense: true),
      onChanged: (value) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) {
          _change(key, parsed);
        }
      },
      onSubmitted: (_) => _commitNumberField(key, min: min, max: max),
    );
  }
}
