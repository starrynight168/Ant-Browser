import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

class BrowserProfileToolsPage extends StatefulWidget {
  const BrowserProfileToolsPage({
    super.key,
    required this.profileId,
    required this.onBack,
  });

  final String profileId;
  final VoidCallback onBack;

  @override
  State<BrowserProfileToolsPage> createState() =>
      _BrowserProfileToolsPageState();
}

class _BrowserProfileToolsPageState extends State<BrowserProfileToolsPage> {
  Map<String, dynamic>? _profile;
  Map<String, String> _groupNames = {};
  Map<String, String> _coreNames = {};
  List<Map<String, dynamic>> _snapshots = [];
  List<Map<String, dynamic>> _tabs = [];
  List<Map<String, dynamic>> _cookies = [];
  final _url = TextEditingController();
  final _cookieFilter = TextEditingController();
  bool _loading = true;
  bool _cookiesLoadedForRun = false;
  String _busy = '';
  String _cookieExport = '';
  int _selectedDetailTab = 0;
  final List<void Function()> _eventUnsubscribers = [];

  bool get _running => _profile?['running'] == true;
  bool get _debugReady => _running && _profile?['debugReady'] == true;

  @override
  void initState() {
    super.initState();
    _reload();
    _listenInstanceEvents();
  }

  /// 监听实例状态事件，自动刷新详情数据（旧版 BrowserDetailPage 行为）。
  void _listenInstanceEvents() {
    for (final event in const [
      'browser:instance:started',
      'browser:instance:stopped',
      'browser:instance:updated',
      'browser:instance:crashed',
    ]) {
      _eventUnsubscribers.add(
        AppBridge.onEvent(event, (payload) {
          final id = payload is Map ? '${payload['profileId'] ?? ''}' : '';
          if (id.isNotEmpty && id != widget.profileId) return;
          if (!mounted) return;
          _reload(silent: true);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final remove in _eventUnsubscribers) {
      remove();
    }
    _url.dispose();
    _cookieFilter.dispose();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    if (mounted && !silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AppBridge.call('BrowserProfileList'),
        AppBridge.call('ListGroups').catchError((_) => const []),
        AppBridge.call('BrowserCoreList').catchError((_) => const []),
      ]);
      final rows = (results[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final matched = rows.where(
        (row) => row['profileId']?.toString() == widget.profileId,
      );
      _profile = matched.isEmpty ? null : matched.first;
      _groupNames = {
        for (final row in (results[1] as List? ?? []).whereType<Map>())
          if ('${row['groupId'] ?? ''}'.trim().isNotEmpty)
            '${row['groupId']}'.trim(): '${row['groupName'] ?? '分组'}'.trim(),
      };
      _coreNames = {
        for (final row in (results[2] as List? ?? []).whereType<Map>())
          if ('${row['coreId'] ?? ''}'.trim().isNotEmpty)
            '${row['coreId']}'.trim():
                '${row['coreName'] ?? row['coreId'] ?? ''}'.trim(),
      };
      await _loadSnapshots();
      if (_debugReady) {
        await _loadTabs();
        if (!_cookiesLoadedForRun) {
          _cookiesLoadedForRun = true;
          await _loadCookies(silent: true);
        }
      } else {
        _tabs = [];
        if (!_running) {
          _cookies = [];
          _cookieExport = '';
          _cookiesLoadedForRun = false;
        }
      }
    } catch (error) {
      if (!silent) _message(error.toString());
    }
    if (mounted) {
      setState(() {
        if (!silent) _loading = false;
      });
    }
  }

  Future<void> _loadSnapshots() async {
    final value = await AppBridge.call('BrowserSnapshotList', [
      widget.profileId,
    ]);
    _snapshots = (value as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _loadTabs() async {
    if (!_debugReady) return;
    try {
      final value = await AppBridge.call('BrowserInstanceGetTabs', [
        widget.profileId,
      ]);
      _tabs = (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (mounted) setState(() {});
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _loadCookies({bool silent = false}) async {
    if (!_debugReady) return;
    if (!silent && mounted) setState(() => _busy = 'cookies');
    try {
      final value = await AppBridge.call('BrowserGetCookies', [
        widget.profileId,
      ]);
      _cookies = (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _cookieExport = '';
    } catch (error) {
      if (!silent) _message(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          if (!silent) _busy = '';
        });
      }
    }
  }

  Future<void> _warmProfileProxy() async {
    final profile = _profile;
    if (profile == null) return;
    final proxyId = '${profile['proxyId'] ?? ''}'.trim();
    final proxyConfig = '${profile['proxyConfig'] ?? ''}'.trim();
    if (proxyId.isEmpty && proxyConfig.isEmpty) return;
    try {
      await AppBridge.call('BrowserProxyWarmupBridgeWithConfig', [
        proxyId,
        proxyConfig,
      ]);
    } catch (_) {}
  }

  Future<void> _perform(String key, Future<dynamic> Function() action) async {
    setState(() => _busy = key);
    try {
      await action();
      await _reload();
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  String _formatDateTime(dynamic raw) {
    final text = '${raw ?? ''}'.trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _defaultSnapshotName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '快照_${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}:${two(now.minute)}';
  }

  String _formatSnapshotSize(dynamic rawSizeMB) {
    final mb = (rawSizeMB is num)
        ? rawSizeMB.toDouble()
        : double.tryParse('${rawSizeMB ?? ''}') ?? 0.0;
    if (mb < 1.0) {
      return '${(mb * 1024).round()} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _cookieExpiry(dynamic value) {
    final expires = double.tryParse(value?.toString() ?? '') ?? 0;
    if (expires <= 0) return '会话 Cookie';
    final local = DateTime.fromMillisecondsSinceEpoch(
      (expires * 1000).round(),
    ).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _resolveGroupName(Map<String, dynamic> profile) {
    final id = '${profile['groupId'] ?? ''}'.trim();
    if (id.isEmpty) return '未分组';
    return _groupNames[id] ?? id;
  }

  String _resolveCoreName(Map<String, dynamic> profile) {
    final id = '${profile['coreId'] ?? ''}'.trim();
    if (id.isEmpty) return '默认内核';
    return _coreNames[id] ?? id;
  }

  ({String label, PrismTone tone, bool dot}) _runtimeStatusInfo(
    Map<String, dynamic> profile,
  ) {
    if (_busy == 'instance') {
      return (label: '处理中…', tone: PrismTone.info, dot: true);
    }
    if (_running && _debugReady) {
      return (label: '运行中', tone: PrismTone.success, dot: true);
    }
    if (_running && !_debugReady) {
      return (label: '运行中（待就绪）', tone: PrismTone.warning, dot: true);
    }
    final lastError = '${profile['lastError'] ?? ''}'.trim();
    if (lastError.isNotEmpty) {
      return (label: '异常', tone: PrismTone.danger, dot: true);
    }
    return (label: '已停止', tone: PrismTone.neutral, dot: false);
  }

  void _message(String text) {
    if (mounted) {
      showPrismNotice(context, text);
    }
  }

  Future<void> _toggle() => _perform('instance', () async {
    if (!_running) {
      await _warmProfileProxy();
    }
    await AppBridge.call(
      _running ? 'BrowserInstanceStop' : 'BrowserInstanceStart',
      [widget.profileId],
    );
  });

  Future<void> _restart() => _perform('instance', () async {
    await _warmProfileProxy();
    await AppBridge.call('BrowserInstanceRestart', [widget.profileId]);
  });

  Future<void> _openUserDataDir() async {
    final path = (_profile?['userDataDir'] ?? '').toString().trim();
    if (path.isEmpty) {
      _message('该实例没有用户数据目录');
      return;
    }
    await _perform('folder', () => AppBridge.call('OpenUserDataDir', [path]));
  }

  Future<void> _openUrl() async {
    final value = _url.text.trim();
    if (value.isEmpty) return;
    await _perform(
      'url',
      () => AppBridge.call('BrowserInstanceOpenUrl', [widget.profileId, value]),
    );
  }

  Future<void> _copyLaunchCode(Map<String, dynamic> profile) async {
    final code = '${profile['launchCode'] ?? ''}'.trim();
    if (code.isEmpty) {
      _message('此实例没有启动码');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) _message('启动码已复制');
    } catch (error) {
      if (mounted) _message('复制启动码失败：$error');
    }
  }

  Future<void> _regenerateLaunchCode() async {
    final accepted = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('重新生成启动码？'),
        content: const Text('旧启动码将立即失效，使用旧码的接口或脚本需要更新。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() => _busy = 'launch-code');
    try {
      await AppBridge.call('BrowserProfileRegenerateCode', [widget.profileId]);
      await _reload(silent: true);
      if (mounted) _message('启动码已重新生成');
    } catch (error) {
      if (mounted) _message('重新生成启动码失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _createSnapshot() async {
    final name = TextEditingController(text: _defaultSnapshotName());
    final value = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('创建快照'),
        content: SizedBox(
          width: 420,
          child: PrismTextField(
            controller: name,
            autofocus: true,
            decoration: const PrismInputDecoration(
              labelText: '快照名称',
              hintText: '快照_YYYY-MM-DD_HH:mm',
            ),
          ),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, name.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    name.dispose();
    if (value == null || value.isEmpty) return;
    await _perform(
      'snapshot',
      () => AppBridge.call('BrowserSnapshotCreate', [widget.profileId, value]),
    );
  }

  Future<void> _restoreSnapshot(Map<String, dynamic> snapshot) async {
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('恢复快照？'),
        content: Text('将用“${snapshot['name'] ?? ''}”替换此实例的浏览器数据。请先关闭实例。'),
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
    if (yes != true) return;
    await _perform(
      'snapshot',
      () => AppBridge.call('BrowserSnapshotRestore', [
        widget.profileId,
        snapshot['snapshotId'],
      ]),
    );
  }

  Future<void> _deleteSnapshot(Map<String, dynamic> snapshot) async {
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除快照？'),
        destructive: true,
        content: Text('将删除“${snapshot['name'] ?? ''}”的本地备份文件。'),
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
    if (yes != true) return;
    await _perform(
      'snapshot',
      () => AppBridge.call('BrowserSnapshotDelete', [
        widget.profileId,
        snapshot['snapshotId'],
      ]),
    );
  }

  Future<void> _exportCookies() async {
    if (!_debugReady) return;
    setState(() => _busy = 'cookies');
    try {
      _cookieExport = (await AppBridge.call('BrowserExportCookies', [
        widget.profileId,
      ])).toString();
      if (mounted) setState(() {});
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _saveCookieExportToFile() async {
    if (_cookieExport.isEmpty) return;
    final safeName = '${_profile?['profileName'] ?? widget.profileId}'
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final baseDir = Directory.systemTemp.path;
    final defaultPath = '$baseDir${Platform.pathSeparator}cookies_$safeName.txt';
    final pathController = TextEditingController(text: defaultPath);
    final chosenPath = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('保存 Netscape Cookie 到文件'),
        content: SizedBox(
          width: 520,
          child: PrismTextField(
            controller: pathController,
            autofocus: true,
            decoration: const PrismInputDecoration(
              labelText: '保存路径',
              hintText: '输入目标 .txt 文件完整路径',
            ),
          ),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.FilledButton.icon(
            onPressed: () => Navigator.pop(context, pathController.text.trim()),
            icon: const PrismGlyph(AntGlyphs.save, size: 15),
            label: const Text('保存'),
          ),
        ],
      ),
    );
    pathController.dispose();
    if (chosenPath == null || chosenPath.isEmpty) return;
    try {
      final file = File(chosenPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(_cookieExport);
      if (mounted) {
        _message('Cookie 已保存到：$chosenPath');
      }
    } catch (error) {
      if (mounted) _message('保存文件失败：$error');
    }
  }

  Future<void> _importCookies() async {
    if (!_debugReady) return;
    final input = TextEditingController();
    final text = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('导入 Cookie'),
        content: SizedBox(
          width: 520,
          child: PrismTextField(
            controller: input,
            minLines: 8,
            maxLines: 16,
            decoration: const PrismInputDecoration(
              labelText: 'Cookie JSON 数组',
              hintText:
                  '[{"name":"session","value":"...","domain":"example.com","path":"/"}]',
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
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List || decoded.any((item) => item is! Map)) {
        throw const FormatException('请输入 Cookie JSON 数组');
      }
      await _perform(
        'cookies',
        () => AppBridge.call('BrowserSetCookies', [
          widget.profileId,
          decoded
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(),
        ]),
      );
      await _loadCookies(silent: true);
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _clearCookies() async {
    if (!_debugReady) return;
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('清除全部 Cookie？'),
        destructive: true,
        content: const Text('此操作会退出相关网站账号。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _perform(
      'cookies',
      () => AppBridge.call('BrowserClearCookies', [widget.profileId]),
    );
    if (mounted) {
      setState(() {
        _cookies = [];
        _cookieExport = '';
      });
    }
  }

  int _valueCount(dynamic value) {
    if (value is Map || value is List || value is String) return value.length;
    return 0;
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final colors = prism.Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: prism.AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: prism.SelectableText(
              value.isEmpty ? '-' : value,
              style: prism.AppTextStyle.footnote.of(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PrismProgressIndicator());
    final profile = _profile;
    if (profile == null) {
      return PrismEmptyState(
        glyph: AntGlyphs.browserOff,
        title: '实例不存在',
        subtitle: '该实例可能已被删除或移动',
        action: prism.FilledButton(
          onPressed: widget.onBack,
          child: const Text('返回列表'),
        ),
      );
    }

    final colors = prism.Theme.of(context).colorScheme;
    final statusInfo = _runtimeStatusInfo(profile);
    final lastError = '${profile['lastError'] ?? ''}'.trim();
    final runtimeWarning = '${profile['runtimeWarning'] ?? ''}'.trim();
    final pid = (profile['pid'] as num?)?.toInt() ?? 0;
    final debugPort = (profile['debugPort'] as num?)?.toInt() ?? 0;
    final tags = (profile['tags'] as List? ?? const [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              prism.IconButton(
                tooltip: '返回',
                onPressed: widget.onBack,
                icon: const PrismGlyph(AntGlyphs.arrowBack, size: 18),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        (profile['profileName'] ?? '实例详情').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.title2.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    PrismBadge(
                      label: statusInfo.label,
                      tone: statusInfo.tone,
                      dot: statusInfo.dot,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty ? _openUserDataDir : null,
                icon: const PrismGlyph(AntGlyphs.folder, size: 16),
                label: const Text('数据目录'),
              ),
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty ? _restart : null,
                icon: const PrismGlyph(AntGlyphs.restart, size: 16),
                label: const Text('重启'),
              ),
              PrismTonalButton.icon(
                onPressed: _busy.isEmpty ? _toggle : null,
                icon: PrismGlyph(
                  _running ? AntGlyphs.stop : AntGlyphs.play,
                  size: 16,
                ),
                child: Text(
                  _busy == 'instance'
                      ? '处理中…'
                      : _running
                      ? '关闭实例'
                      : '启动实例',
                ),
              ),
              prism.IconButton(
                tooltip: '刷新状态',
                onPressed: _busy.isEmpty ? () => _reload() : null,
                icon: const PrismGlyph(AntGlyphs.refresh, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 12),
          prism.SegmentedControl<int>(
            segments: const [(0, '概览与标签页'), (1, '数据快照'), (2, 'Cookie')],
            value: _selectedDetailTab,
            onChanged: (value) {
              setState(() => _selectedDetailTab = value);
              if (value == 2 && _debugReady && !_cookiesLoadedForRun) {
                _cookiesLoadedForRun = true;
                _loadCookies();
              }
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedDetailTab,
              children: [
                ListView(
                  padding: const EdgeInsets.only(top: 16),
                  children: [
                    if (lastError.isNotEmpty) ...[
                      PrismBanner(
                        tone: PrismTone.danger,
                        title: '最近错误',
                        message: lastError,
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (runtimeWarning.isNotEmpty) ...[
                      PrismBanner(
                        tone: PrismTone.warning,
                        title: '运行提示',
                        message: runtimeWarning,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        PrismMetricTile(
                          label: '运行状态',
                          value: statusInfo.label,
                          glyph: AntGlyphs.browser,
                          tone: statusInfo.tone,
                        ),
                        PrismMetricTile(
                          label: '进程 PID',
                          value: pid > 0 ? '$pid' : '-',
                          glyph: AntGlyphs.cpu,
                          tone: pid > 0 ? PrismTone.info : PrismTone.neutral,
                        ),
                        PrismMetricTile(
                          label: '调试端口',
                          value: debugPort > 0 ? '$debugPort' : '-',
                          subtitle: _running
                              ? (_debugReady ? 'CDP 已就绪' : '等待 CDP 就绪')
                              : '未启动',
                          glyph: AntGlyphs.api,
                          tone: _debugReady
                              ? PrismTone.success
                              : _running
                              ? PrismTone.warning
                              : PrismTone.neutral,
                        ),
                        PrismMetricTile(
                          label: '最近启动',
                          value: _formatDateTime(profile['lastStartAt']),
                          subtitle:
                              '最近停止：${_formatDateTime(profile['lastStopAt'])}',
                          glyph: AntGlyphs.schedule,
                          tone: PrismTone.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    PrismSectionCard(
                      title: '实例配置与启动码',
                      glyph: AntGlyphs.settings,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _infoRow(
                            context,
                            '实例编号',
                            '${profile['profileId'] ?? ''}',
                          ),
                          _infoRow(
                            context,
                            '浏览器内核',
                            _resolveCoreName(profile),
                          ),
                          _infoRow(
                            context,
                            '所属分组',
                            _resolveGroupName(profile),
                          ),
                          _infoRow(
                            context,
                            '代理配置',
                            '${profile['proxyConfig'] ?? ''}'.trim().isEmpty
                                ? '直连'
                                : '${profile['proxyConfig']}',
                          ),
                          _infoRow(
                            context,
                            '参数概览',
                            '指纹参数 ${_valueCount(profile['fingerprintArgs'])} 项 · '
                                '启动参数 ${_valueCount(profile['launchArgs'])} 项',
                          ),
                          _infoRow(
                            context,
                            '用户数据目录',
                            '${profile['userDataDir'] ?? ''}',
                          ),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final tag in tags)
                                  PrismBadge(
                                    label: tag,
                                    tone: PrismTone.info,
                                    glyph: AntGlyphs.tag,
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          const prism.Divider(height: 1),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: prism.SelectableText(
                                  '启动码：${profile['launchCode'] ?? '未分配'}',
                                  style: prism.AppTextStyle.subheadline.of(
                                    context,
                                    emphasized: true,
                                  ),
                                ),
                              ),
                              prism.IconButton(
                                tooltip: '复制启动码',
                                onPressed: () => _copyLaunchCode(profile),
                                icon: const PrismGlyph(
                                  AntGlyphs.copy,
                                  size: 16,
                                ),
                              ),
                              prism.IconButton(
                                tooltip: '重新生成启动码',
                                onPressed: _busy.isEmpty
                                    ? _regenerateLaunchCode
                                    : null,
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
                    const SizedBox(height: 14),
                    PrismSectionCard(
                      title: '打开网址与标签页',
                      glyph: AntGlyphs.globe,
                      actions: [
                        prism.IconButton(
                          tooltip: '刷新标签页',
                          onPressed: _debugReady ? _loadTabs : null,
                          icon: const PrismGlyph(AntGlyphs.refresh, size: 16),
                        ),
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: PrismTextField(
                                  controller: _url,
                                  enabled: _debugReady,
                                  onSubmitted: (_) {
                                    if (_debugReady && _busy.isEmpty) {
                                      _openUrl();
                                    }
                                  },
                                  decoration: const PrismInputDecoration(
                                    hintText: 'https://example.com',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              prism.FilledButton.icon(
                                onPressed: _debugReady && _busy.isEmpty
                                    ? _openUrl
                                    : null,
                                icon: const PrismGlyph(
                                  AntGlyphs.openInNew,
                                  size: 15,
                                ),
                                label: const Text('打开'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!_running)
                            const PrismEmptyState(
                              glyph: AntGlyphs.browser,
                              title: '实例未启动',
                              subtitle: '启动实例后可查看和管理当前标签页',
                            )
                          else if (!_debugReady)
                            const PrismBanner(
                              tone: PrismTone.warning,
                              title: '等待调试端口就绪',
                              message:
                                  '实例进程已启动，正在等待 CDP 调试端口就绪，就绪后可加载标签页与打开网址。',
                            )
                          else if (_tabs.isEmpty)
                            const PrismEmptyState(
                              glyph: AntGlyphs.globe,
                              title: '暂无可显示的标签页',
                            )
                          else
                            for (final tab in _tabs)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: prism.Surface(
                                  color: colors.surfaceContainerLow,
                                  shape: prism.AppShape.lg,
                                  child: PrismListTile(
                                    leading: const PrismGlyph(
                                      AntGlyphs.globe,
                                      size: 17,
                                    ),
                                    title: Text(
                                      (tab['title'] ?? '新标签页').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      (tab['url'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: PrismBanner(
                              tone: _running
                                  ? PrismTone.warning
                                  : PrismTone.info,
                              message: _running
                                  ? '实例正在运行，请先关闭实例后再创建或恢复快照。'
                                  : '快照用于备份或还原此实例的本地浏览器数据目录。',
                            ),
                          ),
                          const SizedBox(width: 12),
                          prism.FilledButton.icon(
                            onPressed: !_running && _busy.isEmpty
                                ? _createSnapshot
                                : null,
                            icon: const PrismGlyph(AntGlyphs.add, size: 16),
                            label: const Text('创建快照'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _snapshots.isEmpty
                          ? const PrismEmptyState(
                              glyph: AntGlyphs.archive,
                              title: '暂无数据快照',
                              subtitle: '在实例停止状态下点击“创建快照”保存当前数据',
                            )
                          : ListView(
                              children: [
                                for (final snapshot in _snapshots)
                                  PrismCard(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: PrismListTile(
                                      leading: const PrismGlyph(
                                        AntGlyphs.archive,
                                        size: 18,
                                      ),
                                      title: Text(
                                        (snapshot['name'] ?? '未命名快照')
                                            .toString(),
                                        style: prism.AppTextStyle.subheadline
                                            .of(context, emphasized: true),
                                      ),
                                      subtitle: Text(
                                        '${_formatDateTime(snapshot['createdAt'])} · '
                                        '${_formatSnapshotSize(snapshot['sizeMB'])}',
                                      ),
                                      trailing: Wrap(
                                        spacing: 4,
                                        children: [
                                          prism.IconButton(
                                            tooltip: '恢复快照',
                                            onPressed:
                                                !_running && _busy.isEmpty
                                                ? () =>
                                                      _restoreSnapshot(snapshot)
                                                : null,
                                            icon: const PrismGlyph(
                                              AntGlyphs.restore,
                                              size: 17,
                                            ),
                                          ),
                                          prism.IconButton(
                                            tooltip: '删除快照',
                                            onPressed: _busy.isEmpty
                                                ? () =>
                                                      _deleteSnapshot(snapshot)
                                                : null,
                                            icon: PrismGlyph(
                                              AntGlyphs.delete,
                                              size: 17,
                                              color: colors.error,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 14),
                    if (_running && !_debugReady) ...[
                      const PrismBanner(
                        tone: PrismTone.warning,
                        title: '等待调试端口就绪',
                        message:
                            '实例已启动但调试端口尚未就绪，就绪后将自动支持 Cookie 读取与导入导出。',
                      ),
                      const SizedBox(height: 10),
                    ],
                    PrismSearchBar(
                      controller: _cookieFilter,
                      hintText: '按域名过滤 Cookie...',
                      onChanged: (_) => setState(() {}),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          prism.OutlinedButton.icon(
                            onPressed: _debugReady && _busy.isEmpty
                                ? _loadCookies
                                : null,
                            icon: const PrismGlyph(
                              AntGlyphs.refresh,
                              size: 15,
                            ),
                            label: const Text('读取'),
                          ),
                          prism.OutlinedButton.icon(
                            onPressed: _debugReady && _busy.isEmpty
                                ? _exportCookies
                                : null,
                            icon: const PrismGlyph(
                              AntGlyphs.download,
                              size: 15,
                            ),
                            label: const Text('导出 Netscape'),
                          ),
                          prism.OutlinedButton.icon(
                            onPressed: _debugReady && _busy.isEmpty
                                ? _importCookies
                                : null,
                            icon: const PrismGlyph(
                              AntGlyphs.upload,
                              size: 15,
                            ),
                            label: const Text('导入 JSON'),
                          ),
                          prism.TextButton.icon(
                            onPressed: _debugReady && _busy.isEmpty
                                ? _clearCookies
                                : null,
                            icon: PrismGlyph(
                              AntGlyphs.delete,
                              size: 15,
                              color: _debugReady ? colors.error : null,
                            ),
                            label: const Text('清空'),
                          ),
                        ],
                      ),
                    ),
                    if (_cookieExport.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '导出的 Netscape Cookie',
                              style: prism.AppTextStyle.footnote.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                          ),
                          prism.OutlinedButton.icon(
                            onPressed: _saveCookieExportToFile,
                            icon: const PrismGlyph(AntGlyphs.save, size: 14),
                            label: const Text('保存到文件'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      PrismCodeSurface(
                        code: _cookieExport,
                        language: 'netscape',
                        maxHeight: 150,
                        showCopy: true,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Expanded(
                      child: !_running
                          ? const PrismEmptyState(
                              glyph: AntGlyphs.shield,
                              title: '实例未启动',
                              subtitle: '启动实例且调试端口就绪后可管理 Cookie',
                            )
                          : !_debugReady
                          ? const PrismEmptyState(
                              glyph: AntGlyphs.pending,
                              title: '等待调试端口就绪',
                              subtitle: '就绪后将自动加载当前实例的 Cookie',
                            )
                          : _cookies.isEmpty
                          ? PrismEmptyState(
                              glyph: AntGlyphs.shield,
                              title: '暂无 Cookie',
                              subtitle: '点击“读取”刷新或“导入 JSON”写入 Cookie',
                              action: prism.OutlinedButton.icon(
                                onPressed: _busy.isEmpty ? _loadCookies : null,
                                icon: const PrismGlyph(
                                  AntGlyphs.refresh,
                                  size: 15,
                                ),
                                label: const Text('重新读取'),
                              ),
                            )
                          : Builder(
                              builder: (context) {
                                final query = _cookieFilter.text
                                    .trim()
                                    .toLowerCase();
                                final cookies = _cookies.where((cookie) {
                                  return query.isEmpty ||
                                      (cookie['domain'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .contains(query);
                                }).toList();
                                if (cookies.isEmpty) {
                                  return const PrismEmptyState(
                                    glyph: AntGlyphs.search,
                                    title: '没有匹配的 Cookie',
                                    subtitle: '尝试修改域名过滤关键词',
                                  );
                                }
                                return ListView(
                                  children: [
                                    for (final cookie in cookies)
                                      PrismCard(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      (cookie['name'] ?? '')
                                                          .toString(),
                                                      style: prism
                                                          .AppTextStyle
                                                          .subheadline
                                                          .of(
                                                            context,
                                                            emphasized: true,
                                                          ),
                                                    ),
                                                  ),
                                                  if (cookie['httpOnly'] ==
                                                      true)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        left: 6,
                                                      ),
                                                      child: PrismBadge(
                                                        label: 'HttpOnly',
                                                        tone: PrismTone.info,
                                                      ),
                                                    ),
                                                  if (cookie['secure'] == true)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        left: 6,
                                                      ),
                                                      child: PrismBadge(
                                                        label: 'Secure',
                                                        tone: PrismTone.success,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${cookie['domain'] ?? ''} · ${cookie['path'] ?? '/'} · ${_cookieExpiry(cookie['expires'])}',
                                                style: prism
                                                    .AppTextStyle
                                                    .caption1
                                                    .of(context)
                                                    .copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                              const SizedBox(height: 6),
                                              prism.SelectableText(
                                                (cookie['value'] ?? '')
                                                    .toString(),
                                                maxLines: 2,
                                                style: const TextStyle(
                                                  fontFamily: 'Consolas',
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
