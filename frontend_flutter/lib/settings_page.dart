import 'dart:convert';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:prism_ui/icons/icons.dart' as prism_icons;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';
import 'theme_state.dart';

const _defaultAppSettings = <String, dynamic>{
  'appName': 'Ant Browser',
  'appDescription': '基于 Flutter 与 Go 的桌面应用',
  'theme': 'light',
  'themeColor': 'forest',
  'themeStyle': 'tinted',
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

enum _SettingsSection {
  appearance('外观与主题', '主题模式、Prism 色彩与语言', AntGlyphs.sparkles),
  general('通用与应用', '通知、自动保存与应用信息', AntGlyphs.settings),
  automation('自动化运行时', 'Node.js、Playwright 与自检', AntGlyphs.robot),
  launchApi('本地启动接口', 'HTTP 监听端口与接口状态', AntGlyphs.api),
  performance('性能与日志', '缓存、内存上限与日志级别', AntGlyphs.speed);

  const _SettingsSection(this.title, this.subtitle, this.glyph);

  final String title;
  final String subtitle;
  final prism_icons.Glyph glyph;
}

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

  _SettingsSection _activeSection = _SettingsSection.appearance;

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
  bool _loading = false;
  bool _saving = false;
  String _busy = '';
  void Function()? _unsubscribeRuntimeProgress;

  @override
  void initState() {
    super.initState();
    try {
      final raw = AppBridge.readStorage('app_settings');
      final stored = raw.isEmpty ? null : jsonDecode(raw);
      if (stored is Map) {
        _settings = <String, dynamic>{
          ..._defaultAppSettings,
          ...Map<String, dynamic>.from(stored),
        };
        _savedSettings = Map<String, dynamic>.from(_settings);
      }
    } catch (_) {}
    for (final entry in _numberBounds.entries) {
      final key = entry.key;
      final (min, max) = entry.value;
      _numberControllers[key] = TextEditingController(
        text: '${_int(key, min)}',
      );
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) {
          _commitNumberField(key, min: min, max: max);
        }
      });
      _numberFocusNodes[key] = node;
    }
    _syncControllersFromSettings();
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

  bool get _hasChanges => jsonEncode(_settings) != jsonEncode(_savedSettings);

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

  void _setNumberValue(String key, int value) {
    final bounds = _numberBounds[key]!;
    final clamped = value.clamp(bounds.$1, bounds.$2).toInt();
    final controller = _numberControllers[key];
    if (controller != null && controller.text != '$clamped') {
      controller.text = '$clamped';
    }
    _change(key, clamped);
  }

  void _commitAllNumberFields() {
    for (final entry in _numberBounds.entries) {
      final (min, max) = entry.value;
      _commitNumberField(entry.key, min: min, max: max);
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
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
      final nodeSource = '${rtSettings['nodeSource'] ?? _nodeSource}';
      final sysNodePath =
          '${rtSettings['systemNodePath'] ?? _savedSystemNodePath}';
      setState(() {
        _settings = settings;
        _savedSettings = Map<String, dynamic>.from(settings);
        if (automation.isNotEmpty) _automation = automation;
        if (launchServer.isNotEmpty) _launchServer = launchServer;
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
      setAppThemeStyle('${settings['themeStyle'] ?? 'tinted'}');
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
      await AppBridge.call('SetLogLevel', ['${updated['logLevel'] ?? 'info'}']);
      setAppThemeMode('${updated['theme'] ?? 'light'}');
      setAppThemeColor('${updated['themeColor'] ?? 'forest'}');
      setAppThemeStyle('${updated['themeStyle'] ?? 'tinted'}');
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
        destructive: true,
        content: const Text('这会重置应用的托管设置与外观偏好。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复默认'),
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
      setAppThemeStyle('tinted');
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

  Widget _groupedCard(List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: prism.Divider(height: 1),
          ),
        );
      }
      children.add(rows[i]);
    }
    return RepaintBoundary(
      child: prism.Card(
        radius: prism.AppCorner.xl,
        inert: true,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  Widget _sliderSettingRow({
    required String title,
    required String subtitle,
    required String fieldKey,
    required String unit,
    int? divisions,
  }) {
    final colors = prism.Theme.of(context).colorScheme;
    final (min, max) = _numberBounds[fieldKey]!;
    final current = _int(fieldKey, min).clamp(min, max).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
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
                      title,
                      style: prism.AppTextStyle.subheadline.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: prism.AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PrismBadge(label: '$current $unit', tone: PrismTone.primary),
              const SizedBox(width: 10),
              SizedBox(width: 96, child: _numberField(fieldKey)),
            ],
          ),
          const SizedBox(height: 10),
          prism.Slider(
            value: current.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            label: '$current $unit',
            onChanged: (value) => _setNumberValue(fieldKey, value.round()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final automationStatus = _nested(_automation, 'status');
    final automationReady = automationStatus['ready'] == true;
    final automationInstalling = automationStatus['installing'] == true;
    final launchReady = _launchServer['ready'] == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left Category Rail (macOS / iPadOS Prism Settings) ──
          SizedBox(
            width: 244,
            child: prism.Card(
              radius: prism.AppCorner.xl,
              inert: true,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                    child: Text(
                      '设置分类',
                      style: prism.AppTextStyle.caption1
                          .of(context, emphasized: true)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  for (final section in _SettingsSection.values) ...[
                    _CategoryRailTile(
                      section: section,
                      selected: _activeSection == section,
                      statusTone: switch (section) {
                        _SettingsSection.automation =>
                          automationReady
                              ? PrismTone.success
                              : automationInstalling
                              ? PrismTone.warning
                              : PrismTone.danger,
                        _SettingsSection.launchApi =>
                          launchReady ? PrismTone.success : PrismTone.neutral,
                        _ => null,
                      },
                      onTap: () => setState(() => _activeSection = section),
                    ),
                    const SizedBox(height: 4),
                  ],
                  const Spacer(),
                  const prism.Divider(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _hasChanges ? '有未保存更改' : '配置已同步',
                            style: prism.AppTextStyle.caption1
                                .of(context, emphasized: _hasChanges)
                                .copyWith(
                                  color: _hasChanges
                                      ? PrismToneColors.of(
                                          context,
                                          PrismTone.warning,
                                        ).fg
                                      : colors.onSurfaceVariant,
                                ),
                          ),
                        ),
                        prism.TonalButtonGroup(
                          size: prism.TonalButtonSize.compact,
                          children: [
                            prism.IconButton(
                              tooltip: '恢复默认',
                              onPressed: _saving ? null : _reset,
                              icon: const PrismGlyph(
                                AntGlyphs.restore,
                                size: 16,
                              ),
                            ),
                            prism.IconButton(
                              tooltip: '重新加载',
                              onPressed: _loading || _saving ? null : _load,
                              icon: const PrismGlyph(
                                AntGlyphs.refresh,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          // ── Right Full-Width Detail Pane ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top contextual bar
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      prism.Surface(
                        color: colors.primaryContainer,
                        shape: prism.AppShape.md,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: PrismGlyph(
                            _activeSection.glyph,
                            size: 20,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _activeSection.title,
                              style: prism.AppTextStyle.title3.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                            Text(
                              _activeSection.subtitle,
                              style: prism.AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (_hasChanges) ...[
                        const PrismBadge(
                          label: '未保存',
                          tone: PrismTone.warning,
                          dot: true,
                        ),
                        const SizedBox(width: 10),
                      ],
                      PrismHoverMotion(
                        enabled: !_saving && _hasChanges,
                        child: prism.FilledButton.icon(
                          onPressed: _saving || !_hasChanges ? null : _save,
                          icon: const PrismGlyph(AntGlyphs.save, size: 16),
                          label: Text(_saving ? '保存中…' : '保存更改'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy.isNotEmpty || _loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: prism.LinearProgressIndicator(minHeight: 3),
                  ),
                Expanded(
                  child: prism.PageTransitionSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (entries) => Stack(
                      alignment: Alignment.topLeft,
                      children: entries,
                    ),
                    transitionBuilder: (child, animation, secondaryAnimation) =>
                        prism.FadeThroughTransition(
                          animation: animation,
                          secondaryAnimation: secondaryAnimation,
                          child: child,
                        ),
                    child: SizedBox.expand(
                      key: ValueKey(_activeSection),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: switch (_activeSection) {
                          _SettingsSection.appearance =>
                            _buildAppearanceSection(context),
                          _SettingsSection.general => _buildGeneralSection(
                            context,
                          ),
                          _SettingsSection.automation =>
                            _buildAutomationSection(context),
                          _SettingsSection.launchApi => _buildLaunchApiSection(
                            context,
                          ),
                          _SettingsSection.performance =>
                            _buildPerformanceSection(context),
                        },
                      ),
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

  Widget _buildAppearanceSection(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final currentColorId = '${_settings['themeColor'] ?? 'forest'}';
    final currentTheme = '${_settings['theme'] ?? 'light'}';
    final currentStyle = '${_settings['themeStyle'] ?? 'tinted'}';
    final currentLang = '${_settings['language'] ?? 'zh-CN'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Live Prism Theme Showcase Card
        prism.Card(
          radius: prism.AppCorner.xl,
          inert: true,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        const PrismBadge(
                          label: 'Prism UI 实时预览',
                          glyph: AntGlyphs.sparkles,
                          tone: PrismTone.primary,
                        ),
                        PrismBadge(
                          label: switch (currentStyle) {
                            'vivid' => '鲜明 Vivid',
                            'soft' => '柔和 Soft',
                            'monochrome' => '单色 Monochrome',
                            _ => '浸润 Tinted',
                          },
                          tone: PrismTone.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '所有页面、卡片、按钮与图标均随你选择的主色与色彩风格自动联动。',
                      style: prism.AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PrismHoverMotion(
                    child: prism.FilledButton(
                      onPressed: () {},
                      child: const Text('主按钮'),
                    ),
                  ),
                  PrismTonalButton(onPressed: () {}, child: const Text('柔和按钮')),
                  PrismHoverMotion(
                    child: prism.OutlinedButton(
                      onPressed: () {},
                      child: const Text('次按钮'),
                    ),
                  ),
                  prism.Switch(value: true, onChanged: (_) {}),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _groupedCard([
          prism.ListRow(
            title: const Text('外观模式'),
            subtitle: const Text('切换浅色、深色或自动跟随 Windows 系统主题'),
            trailing: SizedBox(
              width: 260,
              child: prism.SegmentedControl<String>(
                segments: const [
                  ('light', '浅色'),
                  ('dark', '深色'),
                  ('system', '跟随系统'),
                ],
                value: currentTheme,
                onChanged: (theme) {
                  _change('theme', theme);
                  setAppThemeMode(theme);
                },
              ),
            ),
          ),
          prism.ListRow(
            title: const Text('Prism 色彩风格'),
            subtitle: const Text('鲜明突出强调色 · 浸润微染背景 · 柔和低饱和 · 单色纯粹'),
            trailing: SizedBox(
              width: 300,
              child: prism.SegmentedControl<String>(
                segments: const [
                  ('vivid', '鲜明'),
                  ('tinted', '浸润'),
                  ('soft', '柔和'),
                  ('monochrome', '单色'),
                ],
                value: currentStyle,
                onChanged: (style) {
                  _change('themeStyle', style);
                  setAppThemeStyle(style);
                },
              ),
            ),
          ),
          prism.ListRow(
            title: const Text('界面语言'),
            subtitle: const Text('应用界面默认展示语言'),
            trailing: SizedBox(
              width: 210,
              child: prism.SegmentedControl<String>(
                segments: const [('zh-CN', '简体中文'), ('en-US', 'English')],
                value: currentLang,
                onChanged: (lang) => _change('language', lang),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        PrismSectionCard(
          title: '主题色板',
          glyph: AntGlyphs.tune,
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in appThemeColorOptions)
                _ColorSwatchPill(
                  label: option.label,
                  color: Color(option.hex),
                  selected: currentColorId == option.id,
                  onTap: () {
                    _change('themeColor', option.id);
                    setAppThemeColor(option.id);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupedCard([
          PrismSwitchTile(
            title: const Text('保存通知历史'),
            subtitle: const Text('在通知中心保留错误和运行状态提醒'),
            value: _bool('enableNotifications'),
            onChanged: (value) => _change('enableNotifications', value),
          ),
          PrismSwitchTile(
            title: const Text('自动保存'),
            subtitle: const Text('定期自动持久化配置改动'),
            value: _bool('enableAutoSave'),
            onChanged: (value) => _change('enableAutoSave', value),
          ),
          if (_bool('enableAutoSave'))
            _sliderSettingRow(
              title: '自动保存间隔',
              subtitle: '每次自动保存配置的时间间隔（5 – 300 秒）',
              fieldKey: 'autoSaveInterval',
              unit: '秒',
              divisions: 59,
            ),
          _sliderSettingRow(
            title: '最大上传大小',
            subtitle: '单次上传或导入文件允许的最大体积（1 – 1024 MB）',
            fieldKey: 'maxUploadSize',
            unit: 'MB',
          ),
        ]),
        const SizedBox(height: 16),
        PrismSectionCard(
          title: '应用标识信息',
          glyph: AntGlyphs.info,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _textField('应用名称', 'appName', _appNameController),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: _textField(
                  '应用说明',
                  'appDescription',
                  _appDescriptionController,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAutomationSection(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final automationSettings = _nested(_automation, 'settings');
    final automationStatus = _nested(_automation, 'status');
    final automationEnabled = automationSettings['enabled'] == true;
    final automationReady = automationStatus['ready'] == true;
    final automationInstalled = automationStatus['installed'] == true;
    final automationInstalling = automationStatus['installing'] == true;
    final bundledOnly = _nodeSource == 'bundled';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Runtime Status Summary Row
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            PrismMetricTile(
              label: '运行环境状态',
              value: automationReady
                  ? '已就绪'
                  : automationInstalling
                  ? '安装中'
                  : '未就绪',
              glyph: AntGlyphs.robot,
              tone: automationReady
                  ? PrismTone.success
                  : automationInstalling
                  ? PrismTone.warning
                  : PrismTone.danger,
            ),
            if ('${automationStatus['nodeVersion'] ?? ''}'.isNotEmpty)
              PrismMetricTile(
                label: 'Node 版本',
                value: '${automationStatus['nodeVersion']}',
                glyph: AntGlyphs.code,
                tone: PrismTone.info,
              ),
            if ('${automationStatus['playwrightVersion'] ?? ''}'.isNotEmpty)
              PrismMetricTile(
                label: 'Playwright',
                value: '${automationStatus['playwrightVersion']}',
                glyph: AntGlyphs.bolt,
                tone: PrismTone.primary,
              ),
          ],
        ),
        const SizedBox(height: 16),
        _groupedCard([
          PrismSwitchTile(
            title: const Text('启用自动化脚本支持'),
            subtitle: const Text('允许通过内置运行时执行自动化脚本任务'),
            value: automationEnabled,
            onChanged: _busy.isEmpty
                ? (value) => _saveAutomation(
                    value,
                    automationSettings['headlessDefault'] == true,
                  )
                : null,
          ),
          PrismSwitchTile(
            title: const Text('默认无头模式'),
            subtitle: const Text('脚本启动实例时默认隐藏浏览器窗口'),
            value: automationSettings['headlessDefault'] == true,
            onChanged: _busy.isEmpty
                ? (value) => _saveAutomation(automationEnabled, value)
                : null,
          ),
          PrismSwitchTile(
            title: const Text('允许构建 TypeScript 脚本'),
            subtitle: const Text('导入或运行 TS 脚本包时自动编译'),
            value: automationSettings['allowTypeScriptBuild'] == true,
            onChanged: _busy.isEmpty ? _toggleTypeScript : null,
          ),
          prism.ListRow(
            title: const Text('Node 来源'),
            subtitle: const Text('优先使用自动探测、指定系统 Node 或内置运行时'),
            trailing: SizedBox(
              width: 280,
              child: prism.SegmentedControl<String>(
                segments: const [
                  ('auto', '自动'),
                  ('system', '系统 Node'),
                  ('bundled', '内置运行时'),
                ],
                value: _nodeSource,
                onChanged: (value) {
                  if (_busy.isEmpty) setState(() => _nodeSource = value);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: PrismTextField(
                        controller: _systemNodePathController,
                        enabled: !bundledOnly && _busy.isEmpty,
                        decoration: PrismInputDecoration(
                          labelText: '系统 Node 路径（可选）',
                          hintText: bundledOnly
                              ? '内置运行时模式无需填写'
                              : '留空将自动从 PATH 探测',
                          isDense: true,
                          enabled: !bundledOnly && _busy.isEmpty,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    prism.OutlinedButton.icon(
                      onPressed: _busy.isEmpty && !bundledOnly
                          ? _probeNode
                          : null,
                      icon: const PrismGlyph(AntGlyphs.search, size: 15),
                      label: const Text('检测'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PrismTonalButton.icon(
                      onPressed: _busy.isEmpty && _automationRuntimeDirty
                          ? _saveRuntime
                          : null,
                      icon: const PrismGlyph(AntGlyphs.save, size: 16),
                      child: const Text('保存运行时配置'),
                    ),
                    prism.OutlinedButton.icon(
                      onPressed: _busy.isEmpty && !automationInstalling
                          ? _installRuntime
                          : null,
                      icon: const PrismGlyph(AntGlyphs.download, size: 16),
                      label: Text(
                        automationInstalling || _busy == 'install'
                            ? '安装中…'
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
                    if (_automationRuntimeDirty)
                      const PrismBadge(
                        label: '配置已修改，待保存',
                        tone: PrismTone.warning,
                        dot: true,
                      ),
                  ],
                ),
                if (_nodeProbe != null) ...[
                  const SizedBox(height: 12),
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
                if (_runtimeProgress != null) ...[
                  const SizedBox(height: 12),
                  _buildRuntimeProgressPanel(_runtimeProgress!),
                ],
                if (_runtimeCheck != null) ...[
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
                  PrismBanner(
                    tone: PrismTone.danger,
                    title: '运行时错误',
                    message: '${automationStatus['lastError']}',
                  ),
                ],
              ],
            ),
          ),
        ]),
        if (runtimeDetails.isNotEmpty) ...[
          const SizedBox(height: 16),
          PrismSectionCard(
            title: '运行时诊断信息',
            glyph: AntGlyphs.info,
            padding: EdgeInsets.zero,
            child: prism.SelectionArea(
              child: Column(
                children: [
                  for (var i = 0; i < runtimeDetails.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: prism.Divider(height: 1),
                      ),
                    prism.ListRow(
                      minHeight: 44,
                      minVerticalPadding: 6,
                      title: Text(
                        runtimeDetails[i].$1,
                        style: prism.AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Text(
                          runtimeDetails[i].$2,
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: prism.AppTextStyle.footnote.of(context),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLaunchApiSection(BuildContext context) {
    final launchReady = _launchServer['ready'] == true;
    final baseUrl = '${_launchServer['baseUrl'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            PrismMetricTile(
              label: '服务状态',
              value: launchReady ? '运行中' : '未启动',
              glyph: AntGlyphs.api,
              tone: launchReady ? PrismTone.success : PrismTone.neutral,
            ),
            if (baseUrl.isNotEmpty)
              PrismMetricTile(
                label: '接口地址',
                value: baseUrl,
                glyph: AntGlyphs.link,
                tone: PrismTone.primary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: baseUrl));
                  _message('已复制接口地址');
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        _groupedCard([
          prism.ListRow(
            title: const Text('监听端口'),
            subtitle: const Text('供外部脚本、自动化与 OpenClaw 调用（1 – 65535，默认 19876）'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                SizedBox(
                  width: 130,
                  child: PrismTextField(
                    controller: _launchPortController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    decoration: const PrismInputDecoration(isDense: true),
                  ),
                ),
                PrismTonalButton(
                  onPressed: _busy.isEmpty ? _saveLaunchServer : null,
                  child: Text(_busy == 'launch' ? '保存中…' : '应用端口'),
                ),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildPerformanceSection(BuildContext context) {
    final currentLogLevel = '${_settings['logLevel'] ?? 'info'}'.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupedCard([
          PrismSwitchTile(
            title: const Text('启用本地缓存'),
            subtitle: const Text('缓存高频读取的配置与运行时元数据以提升响应速度'),
            value: _bool('cacheEnabled'),
            onChanged: (value) => _change('cacheEnabled', value),
          ),
          prism.ListRow(
            title: const Text('日志级别'),
            subtitle: const Text('控制后端记录的最低日志严重程度'),
            trailing: SizedBox(
              width: 300,
              child: prism.SegmentedControl<String>(
                segments: const [
                  ('debug', 'DEBUG'),
                  ('info', 'INFO'),
                  ('warn', 'WARN'),
                  ('error', 'ERROR'),
                ],
                value:
                    const [
                      'debug',
                      'info',
                      'warn',
                      'error',
                    ].contains(currentLogLevel)
                    ? currentLogLevel
                    : 'info',
                onChanged: (value) => _change('logLevel', value),
              ),
            ),
          ),
          _sliderSettingRow(
            title: '会话超时',
            subtitle: '空闲会话保持时长（1 – 1440 分钟）',
            fieldKey: 'sessionTimeout',
            unit: '分钟',
          ),
          _sliderSettingRow(
            title: '最大内存上限',
            subtitle: '进程建议内存上限（128 – 32768 MB）',
            fieldKey: 'maxMemoryMB',
            unit: 'MB',
          ),
          _sliderSettingRow(
            title: '垃圾回收阈值',
            subtitle: 'Go 运行时 GOGC 触发百分比（10 – 1000%）',
            fieldKey: 'gcPercent',
            unit: '%',
          ),
        ]),
      ],
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
      textAlign: TextAlign.end,
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

class _CategoryRailTile extends StatelessWidget {
  const _CategoryRailTile({
    required this.section,
    required this.selected,
    required this.onTap,
    this.statusTone,
  });

  final _SettingsSection section;
  final bool selected;
  final VoidCallback onTap;
  final PrismTone? statusTone;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final dotColor = statusTone == null
        ? null
        : PrismToneColors.of(context, statusTone!).fg;
    return PrismHoverMotion(
      hoverScale: 1.015,
      pressScale: 0.985,
      child: prism.PressRegion(
        onTap: onTap,
        shape: prism.AppShape.lg,
        child: prism.Surface(
          color: selected ? colors.primaryContainer : const Color(0x00000000),
          shape: prism.AppShape.lg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                PrismGlyph(
                  section.glyph,
                  size: 18,
                  color: selected
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        section.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.subheadline
                            .of(context, emphasized: selected)
                            .copyWith(
                              color: selected
                                  ? colors.onPrimaryContainer
                                  : colors.onSurface,
                            ),
                      ),
                      Text(
                        section.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.caption2
                            .of(context)
                            .copyWith(
                              color: selected
                                  ? colors.onPrimaryContainer.withValues(
                                      alpha: 0.78,
                                    )
                                  : colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (dotColor != null) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 7,
                    height: 7,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: dotColor,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatchPill extends StatelessWidget {
  const _ColorSwatchPill({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return PrismHoverMotion(
      hoverScale: 1.04,
      pressScale: 0.96,
      child: prism.PressRegion(
        onTap: onTap,
        shape: prism.AppShape.full,
        child: prism.Surface(
          color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
          shape: prism.AppShape.full,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: color,
                      shape: const CircleBorder(),
                    ),
                    child: selected
                        ? const Center(
                            child: PrismGlyph(
                              AntGlyphs.check,
                              size: 13,
                              color: Color(0xFFFFFFFF),
                            ),
                          )
                        : null,
                  ),
                ),
                Text(
                  label,
                  style: prism.AppTextStyle.footnote
                      .of(context, emphasized: selected)
                      .copyWith(
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
