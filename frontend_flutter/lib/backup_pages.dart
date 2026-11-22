import 'dart:convert';

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.onOpenS3,
    required this.onOpenOpenList,
  });
  final VoidCallback onOpenS3;
  final VoidCallback onOpenOpenList;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

mixin _BackupProfileImportFlow<T extends StatefulWidget> on State<T> {
  Future<List<Map<String, dynamic>>?> _confirmProfileImport(
    Map<String, dynamic> preview,
  ) async {
    final profiles = (preview['profiles'] as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final actions = profiles.map((profile) {
      return <String, dynamic>{
        'sourceProfileId': profile['sourceProfileId'],
        'sourceIndex': profile['sourceIndex'] ?? 0,
        'mode': profile['suggestedAction'] ?? 'new',
        'profileName':
            profile['suggestedProfileName'] ??
            profile['sourceProfileName'] ??
            '',
      };
    }).toList();
    return showPrismDialog<List<Map<String, dynamic>>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: Text('导入 ${preview['profileCount'] ?? profiles.length} 个实例'),
          content: SizedBox(
            width: 560,
            height: 420,
            child: ListView.separated(
              itemCount: profiles.length,
              separatorBuilder: (_, __) => const prism.Divider(height: 1),
              itemBuilder: (context, index) {
                final profile = profiles[index];
                final action = actions[index];
                final canOverwrite = profile['canOverwrite'] == true;
                final choices = <String>[
                  'new',
                  if (canOverwrite) 'overwrite',
                  'rename',
                ];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (profile['sourceProfileName'] ?? '未命名实例').toString(),
                      ),
                      if ((profile['targetProfileName'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Text('匹配到本机实例：${profile['targetProfileName']}'),
                      PrismDropdownField<String>(
                        value: choices.contains(action['mode'])
                            ? action['mode'] as String
                            : 'new',
                        items: [
                          const PrismDropdownItem(
                            value: 'new',
                            child: Text('新建实例'),
                          ),
                          if (canOverwrite)
                            const PrismDropdownItem(
                              value: 'overwrite',
                              child: Text('覆盖匹配实例'),
                            ),
                          const PrismDropdownItem(
                            value: 'rename',
                            child: Text('重命名导入'),
                          ),
                        ],
                        decoration: const PrismInputDecoration(
                          labelText: '导入方式',
                        ),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialog(() {
                            action['mode'] = value;
                            if (value == 'rename') {
                              action['profileName'] =
                                  profile['suggestedProfileName'] ??
                                  '${profile['sourceProfileName'] ?? '实例'}-副本';
                            }
                          });
                        },
                      ),
                      if (action['mode'] == 'rename')
                        PrismTextFormField(
                          key: ValueKey('backup-import-name-$index'),
                          initialValue: (action['profileName'] ?? '')
                              .toString(),
                          decoration: const PrismInputDecoration(
                            labelText: '导入后的名称',
                          ),
                          onChanged: (value) => action['profileName'] = value,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed:
                  actions.any(
                    (action) =>
                        action['mode'] == 'rename' &&
                        (action['profileName'] ?? '').toString().trim().isEmpty,
                  )
                  ? null
                  : () => Navigator.pop(context, actions),
              child: const Text('继续导入'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askImportPassword() async {
    final password = TextEditingController();
    final result = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('恢复登录态'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入导出时设置的迁移密码；留空可跳过登录态恢复。'),
            const SizedBox(height: 12),
            PrismTextField(
              controller: password,
              obscureText: true,
              decoration: const PrismInputDecoration(labelText: '迁移密码'),
            ),
          ],
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, password.text),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    password.dispose();
    return result;
  }

  Future<Map<String, dynamic>> _completeProfileImport(
    Map<String, dynamic> result,
  ) async {
    if (result['cancelled'] == true ||
        result['requiresProfileImportConfirmation'] != true) {
      return result;
    }
    final preview = Map<String, dynamic>.from(
      (result['profileImportPreview'] as Map?) ?? result,
    );
    final actions = await _confirmProfileImport(preview);
    if (actions == null) {
      return {'cancelled': true, 'message': '已取消导入'};
    }
    var password = '';
    if (preview['portableSessionAvailable'] == true) {
      final value = await _askImportPassword();
      if (value == null) {
        return {'cancelled': true, 'message': '已取消导入'};
      }
      password = value;
    }
    final imported = await AppBridge.call(
      'BrowserProfilePackageImportWithOptions',
      [
        preview['zipPath'] ?? result['zipPath'],
        {
          'conflictMode': 'new',
          'confirmConflict': true,
          'actions': actions,
          'portableSessionPassword': password,
        },
      ],
    );
    return imported is Map
        ? Map<String, dynamic>.from(imported)
        : <String, dynamic>{'message': imported?.toString() ?? '导入完成'};
  }
}

class _BackupPageState extends State<BackupPage>
    with _BackupProfileImportFlow<BackupPage> {
  String _directory = '';
  List<Map<String, dynamic>> _backups = [];
  bool _loading = true;
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await AppBridge.call('BackupGetLocalSettings');
      _directory = (settings as Map?)?['localDirectory']?.toString() ?? '';
      final result = await AppBridge.call('BackupListLocalBackups', [
        _directory,
      ]);
      _backups = (result as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (error) {
      if (mounted) _message(error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  void _message(String message) {
    showPrismNotice(context, (message).toString());
  }

  Future<void> _run(String key, Future<dynamic> Function() action) async {
    setState(() => _busy = key);
    try {
      final result = await action();
      if (result is Map && result['message'] != null)
        _message(result['message'].toString());
      await _load();
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _chooseDirectory() async {
    await _run('directory', () async {
      final selected = await AppBridge.call('BackupSelectLocalDirectory');
      final selectedMap = selected as Map?;
      if (selectedMap?['cancelled'] == true) return null;
      _directory = selectedMap?['localDirectory']?.toString() ?? '';
      if (_directory.isNotEmpty)
        await AppBridge.call('BackupSaveLocalDirectory', [_directory]);
      return null;
    });
  }

  Future<void> _restore(Map<String, dynamic> backup) async {
    final accepted = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('恢复备份？'),
        content: Text('将从「${backup['name'] ?? ''}」恢复数据。建议先关闭浏览器实例。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续恢复'),
          ),
        ],
      ),
    );
    if (accepted == true)
      await _run('restore', () async {
        final value = await AppBridge.call('BackupRestoreLocalPackage', [
          backup['path'],
        ]);
        if (value is Map) {
          return _completeProfileImport(Map<String, dynamic>.from(value));
        }
        return value;
      });
  }

  Future<List<String>?> _selectProfileIds() async {
    final result = await AppBridge.call('BrowserProfileList');
    final profiles = (result as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((profile) => (profile['profileId'] ?? '').toString().isNotEmpty)
        .toList();
    final selected = <String>{};
    return showPrismDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('选择要备份的实例'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: profiles.isEmpty
                ? const Center(child: Text('没有可备份的实例'))
                : ListView.builder(
                    itemCount: profiles.length,
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      final id = profile['profileId'].toString();
                      final running = profile['running'] == true;
                      return PrismCheckboxTile(
                        value: selected.contains(id),
                        title: Text((profile['profileName'] ?? id).toString()),
                        subtitle: running ? const Text('运行中，请先关闭') : null,
                        onChanged: running
                            ? null
                            : (checked) => setDialog(() {
                                if (checked == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              }),
                      );
                    },
                  ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.toList()),
              child: Text('备份所选（${selected.length}）'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askExportPassword() async {
    final password = TextEditingController();
    var error = '';
    final result = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('迁移登录态'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('可以设置密码，将实例 Cookie 一并迁移到另一台电脑。'),
              const SizedBox(height: 12),
              PrismTextField(
                controller: password,
                obscureText: true,
                decoration: PrismInputDecoration(
                  labelText: '迁移密码（至少 8 个字符）',
                  errorText: error.isEmpty ? null : error,
                ),
              ),
            ],
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('仅导出配置'),
            ),
            prism.FilledButton(
              onPressed: () {
                if (password.text.runes.length < 8) {
                  setDialog(() => error = '密码至少需要 8 个字符');
                  return;
                }
                Navigator.pop(context, password.text);
              },
              child: const Text('导出配置和登录态'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    return result;
  }

  Future<Set<String>?> _selectDestinations() async {
    var openListConfigured = false;
    var s3Configured = false;
    try {
      final value = await AppBridge.call('BackupOpenListGetSettings');
      final settings = Map<String, dynamic>.from(value as Map);
      openListConfigured =
          (settings['baseURL'] ?? '').toString().trim().isNotEmpty &&
          settings['authConfigured'] == true;
    } catch (_) {}
    try {
      final value = await AppBridge.call('BackupS3GetSettings');
      final settings = Map<String, dynamic>.from(value as Map);
      s3Configured =
          (settings['endpoint'] ?? '').toString().trim().isNotEmpty &&
          (settings['bucket'] ?? '').toString().trim().isNotEmpty &&
          settings['credentialsConfigured'] == true;
    } catch (_) {}

    final selected = <String>{'local'};
    final destinations = await showPrismDialog<Set<String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('选择备份位置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismCheckboxTile(
                value: selected.contains('local'),
                title: const Text('本地 ZIP'),
                subtitle: const Text('保存到电脑，可选择多个位置'),
                onChanged: (checked) => setDialog(() {
                  checked == true
                      ? selected.add('local')
                      : selected.remove('local');
                }),
              ),
              PrismCheckboxTile(
                value: selected.contains('openlist'),
                title: const Text('OpenList'),
                subtitle: Text(openListConfigured ? '已配置' : '未配置，选择后会打开设置页'),
                onChanged: (checked) => setDialog(() {
                  checked == true
                      ? selected.add('openlist')
                      : selected.remove('openlist');
                }),
              ),
              PrismCheckboxTile(
                value: selected.contains('s3'),
                title: const Text('S3'),
                subtitle: Text(s3Configured ? '已配置' : '未配置，选择后会打开设置页'),
                onChanged: (checked) => setDialog(() {
                  checked == true ? selected.add('s3') : selected.remove('s3');
                }),
              ),
            ],
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected),
              child: const Text('继续'),
            ),
          ],
        ),
      ),
    );
    if (destinations == null) return null;
    if (destinations.contains('openlist') && !openListConfigured) {
      _message('请先配置 OpenList，再开始备份');
      widget.onOpenOpenList();
      return null;
    }
    if (destinations.contains('s3') && !s3Configured) {
      _message('请先配置 S3，再开始备份');
      widget.onOpenS3();
      return null;
    }
    return destinations;
  }

  Future<void> _createBackup() async {
    final scope = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('选择备份范围'),
        content: const Text('全量备份保存应用配置；实例备份保存选中的浏览器实例数据。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('全量备份'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择实例'),
          ),
        ],
      ),
    );
    if (scope == null) return;
    final destinations = await _selectDestinations();
    if (destinations == null) return;
    List<String> profileIds = [];
    var portableSessionPassword = '';
    if (scope) {
      final selected = await _selectProfileIds();
      if (selected == null || selected.isEmpty) return;
      profileIds = selected;
      final password = await _askExportPassword();
      if (password == null) return;
      portableSessionPassword = password;
    }
    await _run(
      'backup',
      () => AppBridge.call('BackupCreatePackage', [
        {
          'local': destinations.contains('local').toString(),
          'openList': destinations.contains('openlist').toString(),
          's3': destinations.contains('s3').toString(),
          if (profileIds.isNotEmpty) 'profileIds': jsonEncode(profileIds),
          if (portableSessionPassword.isNotEmpty)
            'portableSessionPassword': portableSessionPassword,
        },
      ]),
    );
  }

  Future<void> _importBackup() async {
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('导入备份？'),
        content: const Text('导入会更改当前应用数据，请先确认选择了正确的备份文件。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run('import', () async {
      final value = await AppBridge.call('BackupImportPackage');
      if (value is! Map) return value;
      return _completeProfileImport(Map<String, dynamic>.from(value));
    });
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
                '备份与恢复',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            prism.OutlinedButton.icon(
              onPressed: widget.onOpenOpenList,
              icon: const Icon(Icons.cloud_queue_outlined),
              label: const Text('OpenList'),
            ),
            const SizedBox(width: 8),
            prism.OutlinedButton.icon(
              onPressed: widget.onOpenS3,
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('S3 设置'),
            ),
            const SizedBox(width: 8),
            prism.IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 14),
        PrismCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本地备份目录',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: prism.SelectableText(
                        _directory.isEmpty ? '尚未选择目录' : _directory,
                      ),
                    ),
                    prism.OutlinedButton(
                      onPressed: _busy.isEmpty ? _chooseDirectory : null,
                      child: const Text('选择目录'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    prism.FilledButton.icon(
                      onPressed: _busy.isEmpty ? _createBackup : null,
                      icon: const Icon(Icons.archive_outlined),
                      label: Text(_busy == 'backup' ? '备份中…' : '立即备份'),
                    ),
                    prism.OutlinedButton.icon(
                      onPressed: _busy.isEmpty ? _importBackup : null,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('导入备份'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('本地备份记录', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: PrismProgressIndicator())
              : _backups.isEmpty
              ? const Center(child: Text('没有找到本地备份'))
              : ListView.separated(
                  itemCount: _backups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final backup = _backups[index];
                    return PrismCard(
                      child: PrismListTile(
                        title: Text((backup['name'] ?? '').toString()),
                        subtitle: Text(
                          '${backup['modifiedAt'] ?? ''} · ${backup['path'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          children: [
                            prism.IconButton(
                              tooltip: '打开文件位置',
                              onPressed: () => _run(
                                'open',
                                () => AppBridge.call('OpenBackupPath', [
                                  backup['path'],
                                ]),
                              ),
                              icon: const Icon(Icons.folder_open_outlined),
                            ),
                            prism.IconButton(
                              tooltip: '恢复',
                              onPressed: _busy.isEmpty
                                  ? () => _restore(backup)
                                  : null,
                              icon: const Icon(Icons.restore),
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

class S3ConfigPage extends StatefulWidget {
  const S3ConfigPage({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<S3ConfigPage> createState() => _S3ConfigPageState();
}

class OpenListConfigPage extends StatefulWidget {
  const OpenListConfigPage({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<OpenListConfigPage> createState() => _OpenListConfigPageState();
}

class _OpenListConfigPageState extends State<OpenListConfigPage>
    with _BackupProfileImportFlow<OpenListConfigPage> {
  final _url = TextEditingController();
  final _path = TextEditingController(text: 'ant-chrome/backups');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _token = TextEditingController();
  final _rate = TextEditingController(text: '0');
  String _mode = 'token';
  bool _loading = true;
  String _busy = '';
  bool _tokenConfigured = false;
  bool _tokenVisible = false;
  bool _revealingToken = false;
  List<Map<String, dynamic>> _files = [];
  Map<String, dynamic> _schedule = {};
  bool _scheduleEnabled = false;
  String _scheduleTime = '03:00';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _path.dispose();
    _username.dispose();
    _password.dispose();
    _token.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final value = Map<String, dynamic>.from(
        await AppBridge.call('BackupOpenListGetSettings') as Map,
      );
      _url.text = (value['baseURL'] ?? '').toString();
      _path.text = (value['remotePath'] ?? 'ant-chrome/backups').toString();
      _username.text = (value['username'] ?? '').toString();
      _mode = (value['authMode'] ?? 'token').toString();
      _tokenConfigured = value['tokenConfigured'] == true;
      _rate.text = (value['uploadRateLimitMBps'] ?? 0).toString();
      final schedule = await AppBridge.call('BackupScheduledGetSettings');
      _schedule = Map<String, dynamic>.from(schedule as Map);
      _scheduleEnabled = _schedule['enabled'] == true;
      _scheduleTime = (_schedule['dailyTime'] ?? '03:00').toString();
      if (_url.text.isNotEmpty) await _loadFiles();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, String> get _payload => {
    'baseURL': _url.text.trim(),
    'remotePath': _path.text.trim(),
    'authMode': _mode,
    'username': _username.text.trim(),
    'password': _password.text,
    'token': _token.text.trim(),
    'uploadRateLimitMBps': _rate.text.trim(),
  };

  Future<void> _toggleTokenVisibility() async {
    if (_tokenVisible) {
      setState(() => _tokenVisible = false);
      return;
    }
    if (_token.text.isEmpty) {
      setState(() => _revealingToken = true);
      try {
        _token.text = (await AppBridge.call('BackupOpenListRevealToken') ?? '')
            .toString();
      } catch (error) {
        if (mounted) showPrismNotice(context, error.toString());
        return;
      } finally {
        if (mounted) setState(() => _revealingToken = false);
      }
    }
    if (mounted) setState(() => _tokenVisible = true);
  }

  Future<void> _loadFiles() async {
    final value = await AppBridge.call('BackupOpenListList', [_payload]);
    _files = (value as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (mounted) setState(() {});
  }

  Future<void> _action(String action) async {
    setState(() => _busy = action);
    try {
      if (action == 'test') {
        await AppBridge.call('BackupOpenListTest', [_payload]);
        if (mounted) showPrismNotice(context, ('连接成功').toString());
      } else if (action == 'save') {
        await AppBridge.call('BackupOpenListSaveSettings', [_payload]);
        if (mounted) showPrismNotice(context, ('设置已保存').toString());
      } else if (action == 'upload') {
        final result = await AppBridge.call('BackupOpenListUpload', [_payload]);
        await _loadFiles();
        if (mounted)
          showPrismNotice(
            context,
            ((result as Map?)?['message']?.toString() ?? '备份上传完成').toString(),
          );
      } else {
        await _loadFiles();
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _saveSchedule() async {
    setState(() => _busy = 'schedule');
    try {
      final result = await AppBridge.call('BackupScheduledSaveSettings', [
        {'enabled': _scheduleEnabled.toString(), 'dailyTime': _scheduleTime},
      ]);
      _schedule = Map<String, dynamic>.from(result as Map);
      if (mounted) {
        showPrismNotice(context, ('定时备份设置已保存').toString());
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _restore(String fileName) async {
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('从 OpenList 恢复？'),
        content: Text('将合并恢复「$fileName」中的数据；已有数据会保留。'),
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
    setState(() => _busy = 'restore');
    try {
      final result = await AppBridge.call('BackupOpenListRestore', [
        _payload,
        fileName,
      ]);
      final completed = result is Map
          ? await _completeProfileImport(Map<String, dynamic>.from(result))
          : <String, dynamic>{'message': result?.toString() ?? '恢复完成'};
      if (mounted)
        showPrismNotice(context, (completed['message'] ?? '恢复完成').toString());
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _download(String fileName) async {
    setState(() => _busy = 'download');
    try {
      final result = await AppBridge.call('BackupOpenListDownload', [
        _payload,
        fileName,
      ]);
      if (mounted)
        showPrismNotice(
          context,
          ((result as Map?)?['message']?.toString() ?? '下载完成').toString(),
        );
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
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
                    'OpenList 备份设置',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                prism.OutlinedButton(
                  onPressed: _busy.isEmpty ? () => _action('test') : null,
                  child: const Text('测试连接'),
                ),
                const SizedBox(width: 8),
                prism.FilledButton(
                  onPressed: _busy.isEmpty ? () => _action('save') : null,
                  child: const Text('保存'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PrismTextField(
              controller: _url,
              decoration: const PrismInputDecoration(labelText: 'OpenList 地址'),
            ),
            PrismTextField(
              controller: _path,
              decoration: const PrismInputDecoration(labelText: '远程目录'),
            ),
            PrismDropdownField<String>(
              initialValue: _mode,
              decoration: const PrismInputDecoration(labelText: '认证方式'),
              items: const [
                PrismDropdownItem(value: 'token', child: Text('Token')),
                PrismDropdownItem(value: 'basic', child: Text('用户名和密码')),
              ],
              onChanged: (value) => setState(() => _mode = value ?? 'token'),
            ),
            if (_mode == 'basic') ...[
              PrismTextField(
                controller: _username,
                decoration: const PrismInputDecoration(labelText: '用户名'),
              ),
              PrismTextField(
                controller: _password,
                obscureText: true,
                decoration: const PrismInputDecoration(
                  labelText: '密码（留空保留原密码）',
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: PrismTextField(
                      controller: _token,
                      obscureText: !_tokenVisible,
                      decoration: PrismInputDecoration(
                        labelText: 'Token（留空保留原 Token）',
                        hintText: _tokenConfigured ? '已保存，点击眼睛查看' : null,
                      ),
                    ),
                  ),
                  prism.IconButton(
                    onPressed: _busy.isEmpty && !_revealingToken
                        ? _toggleTokenVisibility
                        : null,
                    icon: _revealingToken
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: PrismProgressIndicator(size: 18),
                          )
                        : Icon(
                            _tokenVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                  ),
                ],
              ),
            PrismTextField(
              controller: _rate,
              keyboardType: TextInputType.number,
              decoration: const PrismInputDecoration(
                labelText: '上传限速 MB/s（0 表示不限速）',
              ),
            ),
            const SizedBox(height: 12),
            PrismCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('每天自动备份到 OpenList'),
                      subtitle: const Text('实例仍在运行时会跳过当次任务。'),
                      value: _scheduleEnabled,
                      onChanged: _busy.isEmpty
                          ? (value) => setState(() => _scheduleEnabled = value)
                          : null,
                    ),
                    Row(
                      children: [
                        const Expanded(child: Text('每日执行时间')),
                        prism.OutlinedButton.icon(
                          onPressed: _busy.isEmpty
                              ? () async {
                                  final controller = TextEditingController(
                                    text: _scheduleTime,
                                  );
                                  try {
                                    final picked = await showPrismDialog<String>(
                                      context: context,
                                      builder: (dialogContext) => PrismDialog(
                                        title: '每日执行时间',
                                        hasFields: true,
                                        content: PrismTextField(
                                          controller: controller,
                                          keyboardType: TextInputType.datetime,
                                          decoration:
                                              const PrismInputDecoration(
                                                hintText: '24 小时制，例如 03:00',
                                              ),
                                        ),
                                        actions: [
                                          prism.TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dialogContext),
                                            child: const Text('取消'),
                                          ),
                                          prism.FilledButton(
                                            onPressed: () {
                                              final value = controller.text
                                                  .trim();
                                              if (RegExp(
                                                r'^([01]?\d|2[0-3]):[0-5]\d$',
                                              ).hasMatch(value)) {
                                                Navigator.pop(
                                                  dialogContext,
                                                  value.length == 4
                                                      ? '0$value'
                                                      : value,
                                                );
                                              } else {
                                                showPrismNotice(
                                                  dialogContext,
                                                  '请输入有效的 24 小时时间，例如 03:00',
                                                );
                                              }
                                            },
                                            child: const Text('确定'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (picked != null) {
                                      setState(() => _scheduleTime = picked);
                                    }
                                  } finally {
                                    controller.dispose();
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.schedule),
                          label: Text(_scheduleTime),
                        ),
                        const SizedBox(width: 8),
                        prism.FilledButton(
                          onPressed: _busy.isEmpty ? _saveSchedule : null,
                          child: Text(_busy == 'schedule' ? '保存中…' : '保存定时设置'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '最近状态：${_schedule['status'] ?? 'never'}${(_schedule['lastError'] ?? '').toString().isEmpty ? '' : ' · ${_schedule['lastError']}'}',
                      style: TextStyle(
                        color: prism.Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                    for (final time
                        in (_schedule['recentBackupTimes'] as List? ?? []).take(
                          3,
                        ))
                      Text(
                        '最近备份：$time',
                        style: TextStyle(
                          color: prism.Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const prism.Divider(height: 28),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '远程备份文件',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                prism.IconButton(
                  onPressed: _busy.isEmpty ? () => _action('list') : null,
                  icon: const Icon(Icons.refresh),
                ),
                prism.FilledButton.icon(
                  onPressed: _busy.isEmpty ? () => _action('upload') : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(_busy == 'upload' ? '上传中…' : '创建并上传备份'),
                ),
              ],
            ),
            if (_files.isEmpty)
              Text(
                '没有找到远程备份',
                style: TextStyle(
                  color: prism.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            for (final file in _files)
              PrismCard(
                child: PrismListTile(
                  title: Text((file['name'] ?? '').toString()),
                  subtitle: Text((file['modifiedAt'] ?? '').toString()),
                  trailing: Wrap(
                    children: [
                      prism.IconButton(
                        tooltip: '下载到本地',
                        onPressed: _busy.isEmpty
                            ? () => _download((file['name'] ?? '').toString())
                            : null,
                        icon: const Icon(Icons.download_outlined),
                      ),
                      prism.TextButton(
                        onPressed: _busy.isEmpty
                            ? () => _restore((file['name'] ?? '').toString())
                            : null,
                        child: const Text('恢复'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
}

class _S3ConfigPageState extends State<S3ConfigPage>
    with _BackupProfileImportFlow<S3ConfigPage> {
  final _endpoint = TextEditingController();
  final _region = TextEditingController(text: 'us-east-1');
  final _bucket = TextEditingController();
  final _prefix = TextEditingController();
  final _accessKey = TextEditingController();
  final _secret = TextEditingController();
  final _token = TextEditingController();
  final Map<String, bool> _credentialConfigured = {};
  final Map<String, bool> _visibleCredentials = {};
  bool _pathStyle = false;
  bool _loading = true;
  String _busy = '';
  String _revealingCredential = '';
  List<Map<String, dynamic>> _files = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _region.dispose();
    _bucket.dispose();
    _prefix.dispose();
    _accessKey.dispose();
    _secret.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final value = Map<String, dynamic>.from(
        await AppBridge.call('BackupS3GetSettings') as Map,
      );
      _endpoint.text = (value['endpoint'] ?? '').toString();
      _region.text = (value['region'] ?? 'us-east-1').toString();
      _bucket.text = (value['bucket'] ?? '').toString();
      _prefix.text = (value['prefix'] ?? '').toString();
      _pathStyle = value['forcePathStyle'] == true;
      _credentialConfigured
        ..['accessKeyID'] = value['accessKeyIDConfigured'] == true
        ..['secretAccessKey'] = value['secretAccessKeyConfigured'] == true
        ..['sessionToken'] = value['sessionTokenConfigured'] == true;
      if (_bucket.text.isNotEmpty) await _loadFiles();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, String> get _payload => {
    'endpoint': _endpoint.text.trim(),
    'region': _region.text.trim(),
    'bucket': _bucket.text.trim(),
    'prefix': _prefix.text.trim(),
    'forcePathStyle': '$_pathStyle',
    'accessKeyID': _accessKey.text.trim(),
    'secretAccessKey': _secret.text.trim(),
    'sessionToken': _token.text.trim(),
  };

  Future<void> _toggleCredentialVisibility(
    String field,
    TextEditingController controller,
  ) async {
    if (_visibleCredentials[field] == true) {
      setState(() => _visibleCredentials[field] = false);
      return;
    }
    setState(() => _revealingCredential = field);
    try {
      if (controller.text.isEmpty) {
        controller.text =
            (await AppBridge.call('BackupS3RevealCredential', [field]) ?? '')
                .toString();
      }
      if (mounted) setState(() => _visibleCredentials[field] = true);
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _revealingCredential = '');
    }
  }

  Widget _credentialVisibilityButton(
    String field,
    TextEditingController controller,
  ) => prism.IconButton(
    onPressed: _busy.isEmpty && _revealingCredential.isEmpty
        ? () => _toggleCredentialVisibility(field, controller)
        : null,
    icon: _revealingCredential == field
        ? const SizedBox(
            width: 18,
            height: 18,
            child: PrismProgressIndicator(size: 18),
          )
        : Icon(
            _visibleCredentials[field] == true
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
  );

  Future<void> _action(String method) async {
    setState(() => _busy = method);
    try {
      if (method == 'BackupS3Test') {
        await AppBridge.call(method, [_payload]);
        if (mounted) showPrismNotice(context, ('连接成功').toString());
      } else {
        await AppBridge.call('BackupS3SaveSettings', [_payload]);
        await _loadFiles();
        if (mounted) showPrismNotice(context, ('设置已保存').toString());
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _loadFiles() async {
    final value = await AppBridge.call('BackupS3List', [_payload]);
    _files = (value as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (mounted) setState(() {});
  }

  Future<void> _refreshS3() async {
    try {
      await _loadFiles();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    }
  }

  Future<void> _upload() async {
    setState(() => _busy = 'upload');
    try {
      final result = await AppBridge.call('BackupS3Upload', [_payload]);
      await _loadFiles();
      if (mounted)
        showPrismNotice(
          context,
          ((result as Map?)?['message']?.toString() ?? '上传完成').toString(),
        );
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _restoreS3(String name) async {
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('从 S3 恢复？'),
        content: Text('将合并恢复「$name」中的数据；已有数据会保留。'),
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
    setState(() => _busy = 'restore');
    try {
      final result = await AppBridge.call('BackupS3Restore', [_payload, name]);
      final completed = result is Map
          ? await _completeProfileImport(Map<String, dynamic>.from(result))
          : <String, dynamic>{'message': result?.toString() ?? '恢复完成'};
      if (mounted)
        showPrismNotice(context, (completed['message'] ?? '恢复完成').toString());
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _downloadS3(String name) async {
    setState(() => _busy = 'download');
    try {
      final result = await AppBridge.call('BackupS3Download', [_payload, name]);
      if (mounted)
        showPrismNotice(
          context,
          ((result as Map?)?['message']?.toString() ?? '下载完成').toString(),
        );
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
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
                    'S3 备份设置',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                prism.OutlinedButton(
                  onPressed: _busy.isEmpty
                      ? () => _action('BackupS3Test')
                      : null,
                  child: Text(_busy == 'BackupS3Test' ? '测试中…' : '测试连接'),
                ),
                const SizedBox(width: 8),
                prism.FilledButton(
                  onPressed: _busy.isEmpty ? () => _action('save') : null,
                  child: const Text('保存'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            PrismTextField(
              controller: _endpoint,
              decoration: const PrismInputDecoration(labelText: 'Endpoint'),
            ),
            PrismTextField(
              controller: _region,
              decoration: const PrismInputDecoration(labelText: 'Region'),
            ),
            PrismTextField(
              controller: _bucket,
              decoration: const PrismInputDecoration(labelText: 'Bucket'),
            ),
            PrismTextField(
              controller: _prefix,
              decoration: const PrismInputDecoration(labelText: '备份目录前缀'),
            ),
            Row(
              children: [
                Expanded(
                  child: PrismTextField(
                    controller: _accessKey,
                    obscureText: _visibleCredentials['accessKeyID'] != true,
                    decoration: PrismInputDecoration(
                      labelText: 'Access Key ID',
                      hintText: _credentialConfigured['accessKeyID'] == true
                          ? '已保存，点击眼睛查看'
                          : null,
                    ),
                  ),
                ),
                _credentialVisibilityButton('accessKeyID', _accessKey),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: PrismTextField(
                    controller: _secret,
                    obscureText: _visibleCredentials['secretAccessKey'] != true,
                    decoration: PrismInputDecoration(
                      labelText: 'Secret Access Key',
                      hintText: _credentialConfigured['secretAccessKey'] == true
                          ? '已保存，点击眼睛查看'
                          : null,
                    ),
                  ),
                ),
                _credentialVisibilityButton('secretAccessKey', _secret),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: PrismTextField(
                    controller: _token,
                    obscureText: _visibleCredentials['sessionToken'] != true,
                    decoration: PrismInputDecoration(
                      labelText: 'Session Token（可选）',
                      hintText: _credentialConfigured['sessionToken'] == true
                          ? '已保存，点击眼睛查看'
                          : null,
                    ),
                  ),
                ),
                _credentialVisibilityButton('sessionToken', _token),
              ],
            ),
            PrismSwitchTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('强制使用路径风格地址'),
              value: _pathStyle,
              onChanged: (value) => setState(() => _pathStyle = value),
            ),
            const prism.Divider(height: 28),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'S3 备份文件',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                prism.IconButton(
                  onPressed: _busy.isEmpty ? _refreshS3 : null,
                  icon: const Icon(Icons.refresh),
                ),
                prism.FilledButton.icon(
                  onPressed: _busy.isEmpty ? _upload : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(_busy == 'upload' ? '上传中…' : '创建并上传备份'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_files.isEmpty)
              Text(
                '没有找到 S3 备份文件',
                style: TextStyle(
                  color: prism.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            for (final file in _files)
              PrismCard(
                child: PrismListTile(
                  title: Text((file['name'] ?? '').toString()),
                  subtitle: Text((file['modifiedAt'] ?? '').toString()),
                  trailing: Wrap(
                    children: [
                      prism.IconButton(
                        tooltip: '下载到本地',
                        onPressed: _busy.isEmpty
                            ? () => _downloadS3((file['name'] ?? '').toString())
                            : null,
                        icon: const Icon(Icons.download_outlined),
                      ),
                      prism.TextButton(
                        onPressed: _busy.isEmpty
                            ? () => _restoreS3((file['name'] ?? '').toString())
                            : null,
                        child: const Text('恢复'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
}
