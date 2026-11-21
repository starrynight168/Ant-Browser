import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'prism_components.dart';
import 'wails_bridge.dart';

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
  final _cookieExportController = TextEditingController();
  bool _loading = true;
  String _busy = '';
  String _cookieExport = '';

  bool get _running => _profile?['running'] == true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _url.dispose();
    _cookieExportController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profiles = await WailsBridge.call('BrowserProfileList');
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
    final value = await WailsBridge.call('BrowserSnapshotList', [
      widget.profileId,
    ]);
    _snapshots = (value as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _loadTabs() async {
    final value = await WailsBridge.call('BrowserInstanceGetTabs', [
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
      final value = await WailsBridge.call('BrowserGetCookies', [
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

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _toggle() => _perform(
    'instance',
    () => WailsBridge.call(
      _running ? 'BrowserInstanceStop' : 'BrowserInstanceStart',
      [widget.profileId],
    ),
  );

  Future<void> _restart() => _perform(
    'instance',
    () => WailsBridge.call('BrowserInstanceRestart', [widget.profileId]),
  );

  Future<void> _openUserDataDir() async {
    final path = (_profile?['userDataDir'] ?? '').toString().trim();
    if (path.isEmpty) {
      _message('该实例没有用户数据目录');
      return;
    }
    await _perform('folder', () => WailsBridge.call('OpenUserDataDir', [path]));
  }

  Future<void> _openUrl() async {
    final value = _url.text.trim();
    if (value.isEmpty) return;
    await _perform(
      'url',
      () =>
          WailsBridge.call('BrowserInstanceOpenUrl', [widget.profileId, value]),
    );
  }

  Future<void> _createSnapshot() async {
    final name = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('创建快照'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '快照名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
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
      () =>
          WailsBridge.call('BrowserSnapshotCreate', [widget.profileId, value]),
    );
  }

  Future<void> _restoreSnapshot(Map<String, dynamic> snapshot) async {
    final yes = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('恢复快照？'),
        content: Text('将用“${snapshot['name'] ?? ''}”替换此实例的浏览器数据。请先关闭实例。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _perform(
      'snapshot',
      () => WailsBridge.call('BrowserSnapshotRestore', [
        widget.profileId,
        snapshot['snapshotId'],
      ]),
    );
  }

  Future<void> _deleteSnapshot(Map<String, dynamic> snapshot) async {
    final yes = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('删除快照？'),
        content: Text('将删除“${snapshot['name'] ?? ''}”的本地备份文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _perform(
      'snapshot',
      () => WailsBridge.call('BrowserSnapshotDelete', [
        widget.profileId,
        snapshot['snapshotId'],
      ]),
    );
  }

  Future<void> _exportCookies() async {
    setState(() => _busy = 'cookies');
    try {
      _cookieExport = (await WailsBridge.call('BrowserExportCookies', [
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
    final text = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('导入 Cookie'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: input,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Cookie JSON 数组',
              hintText: '[{"name":"session","value":"...","domain":"example.com","path":"/"}]',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
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
        () => WailsBridge.call('BrowserSetCookies', [
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
    final yes = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('清除全部 Cookie？'),
        content: const Text('此操作会退出相关网站账号。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _perform(
      'cookies',
      () => WailsBridge.call('BrowserClearCookies', [widget.profileId]),
    );
    if (mounted) setState(() => _cookies = []);
  }

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.all(20),
    child: Center(child: Text(text)),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final profile = _profile;
    if (profile == null)
      return Center(
        child: TextButton(
          onPressed: widget.onBack,
          child: const Text('实例不存在，返回列表'),
        ),
      );
    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
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
                IconButton(
                  tooltip: '打开用户数据目录',
                  onPressed: _busy.isEmpty ? _openUserDataDir : null,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
                OutlinedButton.icon(
                  onPressed: _busy.isEmpty ? _restart : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重启'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy.isEmpty ? _toggle : null,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                  label: Text(
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
            const TabBar(
              tabs: [
                Tab(text: '概览与标签页'),
                Tab(text: '数据快照'),
                Tab(text: 'Cookie'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.only(top: 16),
                    children: [
                      PrismCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
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
                          IconButton(
                            onPressed: _running ? _loadTabs : null,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _url,
                              enabled: _running,
                              decoration: const InputDecoration(
                                hintText: 'https://example.com',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
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
                            FilledButton.icon(
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
                                            IconButton(
                                              tooltip: '恢复',
                                              onPressed:
                                                  !_running && _busy.isEmpty
                                                  ? () => _restoreSnapshot(
                                                      snapshot,
                                                    )
                                                  : null,
                                              icon: const Icon(Icons.restore),
                                            ),
                                            IconButton(
                                              tooltip: '删除',
                                              onPressed: _busy.isEmpty
                                                  ? () => _deleteSnapshot(
                                                      snapshot,
                                                    )
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
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _running && _busy.isEmpty
                                  ? _loadCookies
                                  : null,
                              icon: const Icon(Icons.refresh),
                              label: const Text('读取'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _running && _busy.isEmpty
                                  ? _exportCookies
                                  : null,
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('导出 Netscape'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _running && _busy.isEmpty
                                  ? _importCookies
                                  : null,
                              icon: const Icon(Icons.upload_outlined),
                              label: const Text('导入 JSON'),
                            ),
                            TextButton.icon(
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
                          child: TextField(
                            controller: _cookieExportController,
                            readOnly: true,
                            maxLines: null,
                            decoration: const InputDecoration(
                              labelText: '导出的 Cookie',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      Expanded(
                        child: _cookies.isEmpty
                            ? _empty(
                                _running
                                    ? '点击“读取”加载 Cookie'
                                    : '启动实例后可管理 Cookie',
                              )
                            : ListView(
                                children: [
                                  for (final cookie in _cookies)
                                    PrismCard(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      child: PrismListTile(
                                        title: Text(
                                          (cookie['name'] ?? '').toString(),
                                        ),
                                        subtitle: Text(
                                          '${cookie['domain'] ?? ''} · ${cookie['path'] ?? '/'}',
                                        ),
                                        trailing: Text(
                                          cookie['secure'] == true
                                              ? 'Secure'
                                              : '',
                                        ),
                                      ),
                                    ),
                                ],
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
    );
  }
}
