import 'dart:convert';

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';

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
  List<Map<String, dynamic>> _snapshots = [];
  List<Map<String, dynamic>> _tabs = [];
  List<Map<String, dynamic>> _cookies = [];
  final _url = TextEditingController();
  final _cookieFilter = TextEditingController();
  final _cookieExportController = TextEditingController();
  bool _loading = true;
  String _busy = '';
  String _cookieExport = '';
  int _selectedDetailTab = 0;

  bool get _running => _profile?['running'] == true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _url.dispose();
    _cookieFilter.dispose();
    _cookieExportController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profiles = await AppBridge.call('BrowserProfileList');
      final rows = (profiles as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final matched = rows.where(
        (row) => row['profileId']?.toString() == widget.profileId,
      );
      _profile = matched.isEmpty ? null : matched.first;
      await _loadSnapshots();
      if (_running) await _loadTabs();
    } catch (error) {
      _message(error.toString());
    }
    if (mounted) setState(() => _loading = false);
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
    final value = await AppBridge.call('BrowserInstanceGetTabs', [
      widget.profileId,
    ]);
    _tabs = (value as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (mounted) setState(() {});
  }

  Future<void> _loadCookies() async {
    setState(() => _busy = 'cookies');
    try {
      final value = await AppBridge.call('BrowserGetCookies', [
        widget.profileId,
      ]);
      _cookies = (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _cookieExport = '';
      _cookieExportController.clear();
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
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

  String _cookieExpiry(dynamic value) {
    final expires = double.tryParse(value?.toString() ?? '') ?? 0;
    if (expires <= 0) return '会话 Cookie';
    return DateTime.fromMillisecondsSinceEpoch((expires * 1000).round())
        .toLocal()
        .toString();
  }

  void _message(String text) {
    if (mounted) {
      showPrismNotice(context, (text).toString());
    }
  }

  Future<void> _toggle() => _perform(
    'instance',
    () => AppBridge.call(
      _running ? 'BrowserInstanceStop' : 'BrowserInstanceStart',
      [widget.profileId],
    ),
  );

  Future<void> _restart() => _perform(
    'instance',
    () => AppBridge.call('BrowserInstanceRestart', [widget.profileId]),
  );

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

  Future<void> _createSnapshot() async {
    final name = TextEditingController();
    final value = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('创建快照'),
        content: PrismTextField(
          controller: name,
          autofocus: true,
          decoration: const PrismInputDecoration(labelText: '快照名称'),
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
    setState(() => _busy = 'cookies');
    try {
      _cookieExport = (await AppBridge.call('BrowserExportCookies', [
        widget.profileId,
      ])).toString();
      _cookieExportController.text = _cookieExport;
      if (mounted) setState(() {});
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _importCookies() async {
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
              hintText: '[{"name":"session","value":"...","domain":"example.com","path":"/"}]',
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
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _clearCookies() async {
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('清除全部 Cookie？'),
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
    if (mounted) setState(() => _cookies = []);
  }

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.all(20),
    child: Center(child: Text(text)),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PrismProgressIndicator());
    final profile = _profile;
    if (profile == null)
      return Center(
        child: prism.TextButton(
          onPressed: widget.onBack,
          child: const Text('实例不存在，返回列表'),
        ),
      );
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              prism.IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  (profile['profileName'] ?? '实例详情').toString(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              prism.IconButton(
                tooltip: '打开用户数据目录',
                onPressed: _busy.isEmpty ? _openUserDataDir : null,
                icon: const Icon(Icons.folder_open_outlined),
              ),
              prism.OutlinedButton.icon(
                onPressed: _busy.isEmpty ? _restart : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('重启'),
              ),
              const SizedBox(width: 8),
              PrismTonalButton.icon(
                onPressed: _busy.isEmpty ? _toggle : null,
                icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                child: Text(
                  _busy == 'instance'
                      ? '处理中…'
                      : _running
                      ? '关闭实例'
                      : '启动实例',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          prism.SegmentedControl<int>(
            segments: const [(0, '概览与标签页'), (1, '数据快照'), (2, 'Cookie')],
            value: _selectedDetailTab,
            onChanged: (value) => setState(() => _selectedDetailTab = value),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedDetailTab,
              children: [
                ListView(
                  padding: const EdgeInsets.only(top: 16),
                  children: [
                    PrismCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: prism.SelectableText(
                          '实例编号：${profile['profileId'] ?? ''}\n启动码：${profile['launchCode'] ?? ''}\n浏览器内核：${profile['coreId'] ?? ''}\n代理：${profile['proxyConfig'] ?? '直连'}\n分组：${profile['groupId'] ?? '未分组'}\n用户数据目录：${profile['userDataDir'] ?? ''}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '打开网址',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        prism.IconButton(
                          onPressed: _running ? _loadTabs : null,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: PrismTextField(
                            controller: _url,
                            enabled: _running,
                            decoration: const PrismInputDecoration(
                              hintText: 'https://example.com',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        prism.FilledButton(
                          onPressed: _running && _busy.isEmpty
                              ? _openUrl
                              : null,
                          child: const Text('打开'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_running) _empty('启动实例后可查看当前标签页'),
                    for (final tab in _tabs)
                      PrismCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: PrismListTile(
                          leading: const Icon(Icons.language),
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
                    if (_running && _tabs.isEmpty) _empty('当前没有可显示的标签页'),
                  ],
                ),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Row(
                        children: [
                          const Expanded(child: Text('快照只能在实例关闭时创建或恢复。')),
                          prism.FilledButton.icon(
                            onPressed: !_running && _busy.isEmpty
                                ? _createSnapshot
                                : null,
                            icon: const Icon(Icons.add),
                            label: const Text('创建快照'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _snapshots.isEmpty
                          ? _empty('暂无快照')
                          : ListView(
                              children: [
                                for (final snapshot in _snapshots)
                                  PrismCard(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: PrismListTile(
                                      title: Text(
                                        (snapshot['name'] ?? '未命名快照')
                                            .toString(),
                                      ),
                                      subtitle: Text(
                                        '${snapshot['createdAt'] ?? ''} · ${((snapshot['sizeMB'] as num?) ?? 0).toStringAsFixed(1)} MB',
                                      ),
                                      trailing: Wrap(
                                        children: [
                                          prism.IconButton(
                                            tooltip: '恢复',
                                            onPressed:
                                                !_running && _busy.isEmpty
                                                ? () =>
                                                      _restoreSnapshot(snapshot)
                                                : null,
                                            icon: const Icon(Icons.restore),
                                          ),
                                          prism.IconButton(
                                            tooltip: '删除',
                                            onPressed: _busy.isEmpty
                                                ? () =>
                                                      _deleteSnapshot(snapshot)
                                                : null,
                                            icon: const Icon(
                                              Icons.delete_outline,
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
                  children: [
                    PrismTextField(
                      controller: _cookieFilter,
                      onChanged: (_) => setState(() {}),
                      decoration: const PrismInputDecoration(
                        labelText: '按域名过滤 Cookie',
                        isDense: true,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          prism.OutlinedButton.icon(
                            onPressed: _running && _busy.isEmpty
                                ? _loadCookies
                                : null,
                            icon: const Icon(Icons.refresh),
                            label: const Text('读取'),
                          ),
                          prism.OutlinedButton.icon(
                            onPressed: _running && _busy.isEmpty
                                ? _exportCookies
                                : null,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('导出 Netscape'),
                          ),
                          prism.OutlinedButton.icon(
                            onPressed: _running && _busy.isEmpty
                                ? _importCookies
                                : null,
                            icon: const Icon(Icons.upload_outlined),
                            label: const Text('导入 JSON'),
                          ),
                          prism.TextButton.icon(
                            onPressed: _running && _busy.isEmpty
                                ? _clearCookies
                                : null,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('清空'),
                          ),
                        ],
                      ),
                    ),
                    if (_cookieExport.isNotEmpty)
                      SizedBox(
                        height: 150,
                        child: PrismTextField(
                          controller: _cookieExportController,
                          readOnly: true,
                          maxLines: null,
                          decoration: const PrismInputDecoration(
                            labelText: '导出的 Cookie',
                          ),
                        ),
                      ),
                    Expanded(
                      child: _cookies.isEmpty
                          ? _empty(
                              _running ? '点击“读取”加载 Cookie' : '启动实例后可管理 Cookie',
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
                                  return _empty('没有匹配的 Cookie');
                                }
                                return ListView(
                                  children: [
                                    for (final cookie in cookies)
                                      PrismCard(
                                        margin: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                (cookie['name'] ?? '')
                                                    .toString(),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${cookie['domain'] ?? ''} · ${cookie['path'] ?? '/'} · ${_cookieExpiry(cookie['expires'])}',
                                              ),
                                              const SizedBox(height: 4),
                                              prism.SelectableText(
                                                (cookie['value'] ?? '')
                                                    .toString(),
                                                maxLines: 2,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'HttpOnly ${cookie['httpOnly'] == true ? '是' : '否'} · Secure ${cookie['secure'] == true ? '是' : '否'}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: prism.Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
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
