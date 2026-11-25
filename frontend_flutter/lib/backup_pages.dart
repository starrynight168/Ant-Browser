import 'dart:convert';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

String _formatFileSize(dynamic rawBytes) {
  final bytes = (rawBytes is num)
      ? rawBytes.toDouble()
      : double.tryParse('$rawBytes') ?? 0;
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final digits = unitIndex == 0 ? 0 : (value >= 100 ? 0 : (value >= 10 ? 1 : 2));
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String _formatTransferRate(dynamic rawBps) {
  final bps = (rawBps is num)
      ? rawBps.toDouble()
      : double.tryParse('$rawBps') ?? 0;
  if (bps <= 0) return '';
  return '${_formatFileSize(bps)}/s';
}

String _formatTimestamp(dynamic raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final local = parsed.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _formatBackupResultSummary(Map<String, dynamic> result) {
  final parts = <String>[];
  final baseMessage = (result['message'] ?? '').toString().trim();
  if (baseMessage.isNotEmpty) {
    parts.add(baseMessage);
  }

  final created = (result['createdCount'] as num?)?.toInt() ?? 0;
  final overwritten = (result['overwrittenCount'] as num?)?.toInt() ?? 0;
  final renamed = (result['renamedCount'] as num?)?.toInt() ?? 0;
  if (created > 0 || overwritten > 0 || renamed > 0) {
    parts.add('实例导入统计：新建 $created · 覆盖 $overwritten · 重命名 $renamed');
  }

  final failedComponents = (result['failedComponents'] as List? ?? [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
  if (failedComponents.isNotEmpty) {
    final items = failedComponents.take(3).map((item) {
      final name = (item['componentName'] ?? item['componentId'] ?? '未知组件')
          .toString();
      final err = (item['error'] ?? '').toString();
      return err.isEmpty ? name : '$name（$err）';
    }).join('；');
    final suffix = failedComponents.length > 3
        ? ' 等 ${failedComponents.length} 项'
        : '';
    parts.add('部分组件失败：$items$suffix');
  }

  final warnings = (result['warnings'] as List? ?? [])
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
  if (warnings.isNotEmpty) {
    final preview = warnings.take(2).join('；');
    final suffix = warnings.length > 2 ? ' 等 ${warnings.length} 条警告' : '';
    parts.add('提示：$preview$suffix');
  }

  return parts.isEmpty ? '操作完成' : parts.join('\n');
}

(String, PrismTone) _scheduleStatusInfo(String status) => switch (status) {
  'running' => ('运行中', PrismTone.info),
  'success' => ('成功', PrismTone.success),
  'skipped' => ('已跳过', PrismTone.warning),
  'failed' => ('失败', PrismTone.danger),
  _ => ('从未执行', PrismTone.neutral),
};

(String, PrismTone) _backupPackageBadge(
  Map<String, dynamic> backup, {
  required bool isLocal,
}) {
  if (backup['metadataOrphan'] == true) {
    return ('备份文件缺失', PrismTone.danger);
  }
  if (isLocal && backup.containsKey('metadataAvailable') &&
      backup['metadataAvailable'] == false) {
    return ('信息不可用', PrismTone.warning);
  }
  final packageType = (backup['packageType'] ?? '').toString().trim();
  final profileCount = (backup['profileCount'] as num?)?.toInt() ?? 0;
  return switch (packageType) {
    'full' => ('全量', PrismTone.primary),
    'profile' => (profileCount > 1 ? '多实例' : '单实例', PrismTone.info),
    _ => ('信息不可用', PrismTone.neutral),
  };
}

class _TestResultState {
  const _TestResultState({required this.ok, required this.message});

  final bool ok;
  final String message;
}

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
    final conflictCount = (preview['conflictCount'] as num?)?.toInt() ?? 0;
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
        builder: (context, setDialog) {
          final colors = prism.Theme.of(context).colorScheme;
          final hasOverwrite = actions.any((a) => a['mode'] == 'overwrite');
          return PrismDialog(
            title: Text('导入 ${preview['profileCount'] ?? profiles.length} 个实例'),
            content: SizedBox(
              width: 620,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      PrismBadge(
                        label: '共 ${preview['profileCount'] ?? profiles.length} 个实例',
                        tone: PrismTone.info,
                        glyph: AntGlyphs.browser,
                      ),
                      if (conflictCount > 0)
                        PrismBadge(
                          label: '$conflictCount 个冲突需确认',
                          tone: PrismTone.warning,
                          glyph: AntGlyphs.warning,
                        )
                      else
                        const PrismBadge(
                          label: '无冲突',
                          tone: PrismTone.success,
                          glyph: AntGlyphs.checkCircle,
                        ),
                    ],
                  ),
                  if (hasOverwrite) ...[
                    const SizedBox(height: 10),
                    const PrismBanner(
                      tone: PrismTone.warning,
                      title: '覆盖提示',
                      message: '选择「覆盖匹配实例」时，原实例数据会先移入回收站，再由备份包数据替换。',
                    ),
                  ],
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: profiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final profile = profiles[index];
                        final action = actions[index];
                        final canOverwrite = profile['canOverwrite'] == true;
                        final matchType = (profile['matchType'] ?? '')
                            .toString()
                            .trim();
                        final sourceNameCollision =
                            profile['sourceNameCollision'] == true;
                        final sourceTargetCollision =
                            profile['sourceTargetCollision'] == true;
                        final ambiguous = profile['ambiguous'] == true;
                        final targetRunning = profile['targetRunning'] == true;
                        final targetName =
                            (profile['targetProfileName'] ?? '').toString();
                        final sourceName =
                            (profile['sourceProfileName'] ?? '未命名实例')
                                .toString();
                        final choices = <String>[
                          'new',
                          if (canOverwrite) 'overwrite',
                          'rename',
                        ];
                        final currentMode = choices.contains(action['mode'])
                            ? action['mode'] as String
                            : 'new';
                        final resultPreview = switch (currentMode) {
                          'overwrite' =>
                            '最终结果：覆盖本机实例「${targetName.isEmpty ? sourceName : targetName}」',
                          'rename' =>
                            '最终结果：以新名称「${(action['profileName'] ?? '').toString().trim()}」导入',
                          _ =>
                            '最终结果：新建实例「${(profile['suggestedProfileName'] ?? sourceName).toString()}」',
                        };
                        final conflictReasons = <String>[
                          if (sourceNameCollision) '备份包内存在重名实例',
                          if (sourceTargetCollision) '多个导入实例匹配到同一本机实例',
                          if (ambiguous) '本机存在多个同名实例（匹配不唯一）',
                          if (targetRunning) '本机目标实例正在运行，无法覆盖',
                        ];

                        return prism.Surface(
                          color: colors.surfaceContainerLow,
                          shape: prism.AppShape.lg,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      sourceName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: prism.AppTextStyle.subheadline.of(
                                        context,
                                        emphasized: true,
                                      ),
                                    ),
                                    if (matchType == 'id')
                                      const PrismBadge(
                                        label: 'ID 匹配',
                                        tone: PrismTone.info,
                                      )
                                    else if (matchType == 'name')
                                      const PrismBadge(
                                        label: '名称匹配',
                                        tone: PrismTone.warning,
                                      ),
                                    if (targetRunning)
                                      const PrismBadge(
                                        label: '运行中',
                                        tone: PrismTone.danger,
                                      ),
                                  ],
                                ),
                                if (targetName.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '匹配到本机实例：$targetName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: prism.AppTextStyle.caption1
                                        .of(context)
                                        .copyWith(color: colors.onSurfaceVariant),
                                  ),
                                ],
                                if (conflictReasons.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      for (final reason in conflictReasons)
                                        PrismBadge(
                                          label: reason,
                                          tone: PrismTone.warning,
                                          glyph: AntGlyphs.warning,
                                        ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                PrismDropdownField<String>(
                                  value: currentMode,
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
                                            '$sourceName-副本';
                                      }
                                    });
                                  },
                                ),
                                if (currentMode == 'rename') ...[
                                  const SizedBox(height: 8),
                                  PrismTextFormField(
                                    key: ValueKey('backup-import-name-$index'),
                                    initialValue: (action['profileName'] ?? '')
                                        .toString(),
                                    decoration: const PrismInputDecoration(
                                      labelText: '导入后的名称',
                                    ),
                                    onChanged: (value) => setDialog(
                                      () => action['profileName'] = value,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  resultPreview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: prism.AppTextStyle.caption1
                                      .of(context, emphasized: true)
                                      .copyWith(
                                        color: currentMode == 'overwrite'
                                            ? PrismToneColors.of(
                                                context,
                                                PrismTone.warning,
                                              ).fg
                                            : colors.primary,
                                      ),
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
                          (action['profileName'] ?? '')
                              .toString()
                              .trim()
                              .isEmpty,
                    )
                    ? null
                    : () => Navigator.pop(context, actions),
                child: const Text('继续导入'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _importWithPasswordDialog(
    Future<Map<String, dynamic>> Function(String password) performImport,
  ) async {
    final password = TextEditingController();
    var obscure = true;
    var submitting = false;
    var error = '';

    final result = await showPrismDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          Future<void> submit({required bool skipPassword}) async {
            final value = skipPassword ? '' : password.text;
            if (!skipPassword && value.isNotEmpty && value.runes.length < 8) {
              setDialog(() => error = '迁移密码至少需要 8 个字符，或留空跳过登录态恢复');
              return;
            }
            setDialog(() {
              submitting = true;
              error = '';
            });
            try {
              final imported = await performImport(value);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, imported);
              }
            } catch (err) {
              final text = err.toString();
              if (dialogContext.mounted) {
                setDialog(() {
                  submitting = false;
                  error = text;
                });
              }
            }
          }

          return PrismDialog(
            title: const Text('恢复登录态'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '此备份包包含加密的跨设备登录态。输入导出时设置的迁移密码即可恢复 Cookie；留空或点击「跳过登录态」仅恢复配置。',
                    style: prism.AppTextStyle.footnote.of(dialogContext),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: PrismTextField(
                          controller: password,
                          obscureText: obscure,
                          enabled: !submitting,
                          onSubmitted: (_) => submit(skipPassword: false),
                          decoration: PrismInputDecoration(
                            labelText: '迁移密码（至少 8 个字符，可留空）',
                            errorText: error.isEmpty ? null : error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(top: 21),
                        child: prism.IconButton(
                          tooltip: obscure ? '显示密码' : '隐藏密码',
                          onPressed: submitting
                              ? null
                              : () => setDialog(() => obscure = !obscure),
                          icon: PrismGlyph(
                            obscure ? AntGlyphs.eye : AntGlyphs.eyeOff,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    PrismBanner(
                      tone: PrismTone.danger,
                      message: error,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              prism.OutlinedButton(
                onPressed: submitting
                    ? null
                    : () => submit(skipPassword: true),
                child: const Text('跳过登录态'),
              ),
              prism.FilledButton(
                onPressed: submitting
                    ? null
                    : () => submit(skipPassword: false),
                child: Text(submitting ? '恢复中…' : '确认并导入'),
              ),
            ],
          );
        },
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

    Future<Map<String, dynamic>> invokeImport(String password) async {
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

    if (preview['portableSessionAvailable'] == true) {
      final imported = await _importWithPasswordDialog(invokeImport);
      if (imported == null) {
        return {'cancelled': true, 'message': '已取消导入'};
      }
      return imported;
    }
    return invokeImport('');
  }
}

class _BackupPageState extends State<BackupPage>
    with _BackupProfileImportFlow<BackupPage> {
  int _historyTab = 0; // 0: local, 1: openlist, 2: s3
  String _directory = '';
  List<Map<String, dynamic>> _localBackups = [];
  List<Map<String, dynamic>> _openListBackups = [];
  List<Map<String, dynamic>> _s3Backups = [];
  bool _openListConfigured = false;
  bool _s3Configured = false;
  bool _openListLoaded = false;
  bool _s3Loaded = false;
  Map<String, String> _openListPayload = {};
  Map<String, String> _s3Payload = {};
  Map<String, dynamic> _scheduleSettings = {};
  bool _loading = true;
  bool _loadingRemote = false;
  String _busy = '';

  Map<String, dynamic>? _activeProgress;
  String _progressKind = '';
  final List<String> _progressLogs = [];
  late final void Function() _removeExportProgressListener;
  late final void Function() _removeImportProgressListener;

  @override
  void initState() {
    super.initState();
    _removeExportProgressListener = AppBridge.onEvent(
      'backup:export:progress',
      (payload) => _onProgressEvent('export', payload),
    );
    _removeImportProgressListener = AppBridge.onEvent(
      'backup:import:progress',
      (payload) => _onProgressEvent('import', payload),
    );
    _load();
  }

  @override
  void dispose() {
    _removeExportProgressListener();
    _removeImportProgressListener();
    super.dispose();
  }

  void _onProgressEvent(String kind, dynamic payload) {
    if (!mounted || payload is! Map) return;
    final event = Map<String, dynamic>.from(payload);
    final ts = (event['timestamp'] ?? '').toString().trim();
    final msg = (event['message'] ?? '').toString().trim();
    final comp = (event['componentName'] ?? '').toString().trim();
    final idx = (event['entryIndex'] as num?)?.toInt() ?? 0;
    final total = (event['entryTotal'] as num?)?.toInt() ?? 0;
    final rate = _formatTransferRate(event['bytesPerSecond']);
    final parts = <String>[
      if (ts.isNotEmpty) '[$ts]',
      if (comp.isNotEmpty) comp,
      if (msg.isNotEmpty) msg,
      if (idx > 0 && total > 0) '($idx/$total)',
      if (rate.isNotEmpty) rate,
    ];
    setState(() {
      _progressKind = kind;
      _activeProgress = event;
      if (parts.isNotEmpty) {
        final line = parts.join(' ');
        if (_progressLogs.isEmpty || _progressLogs.last != line) {
          _progressLogs.add(line);
          if (_progressLogs.length > 200) {
            _progressLogs.removeAt(0);
          }
        }
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await AppBridge.call('BackupGetLocalSettings');
      _directory = (settings as Map?)?['localDirectory']?.toString() ?? '';
      final result = await AppBridge.call('BackupListLocalBackups', [
        _directory,
      ]);
      _localBackups = (result as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      await _loadRemoteMetadata();
    } catch (error) {
      if (mounted) _message(error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRemoteMetadata() async {
    try {
      final ol = await AppBridge.call('BackupOpenListGetSettings');
      if (ol is Map) {
        final map = Map<String, dynamic>.from(ol);
        _openListConfigured =
            (map['baseURL'] ?? '').toString().trim().isNotEmpty &&
            map['authConfigured'] == true;
        _openListPayload = {
          'baseURL': (map['baseURL'] ?? '').toString(),
          'remotePath': (map['remotePath'] ?? 'ant-chrome/backups').toString(),
          'authMode': (map['authMode'] ?? 'token').toString(),
          'username': (map['username'] ?? '').toString(),
          'password': '',
          'token': '',
          'uploadRateLimitMBps': (map['uploadRateLimitMBps'] ?? 0).toString(),
        };
      }
    } catch (_) {
      _openListConfigured = false;
    }

    try {
      final s3 = await AppBridge.call('BackupS3GetSettings');
      if (s3 is Map) {
        final map = Map<String, dynamic>.from(s3);
        _s3Configured =
            (map['endpoint'] ?? '').toString().trim().isNotEmpty &&
            (map['bucket'] ?? '').toString().trim().isNotEmpty &&
            map['credentialsConfigured'] == true;
        _s3Payload = {
          'endpoint': (map['endpoint'] ?? '').toString(),
          'region': (map['region'] ?? 'us-east-1').toString(),
          'bucket': (map['bucket'] ?? '').toString(),
          'prefix': (map['prefix'] ?? '').toString(),
          'forcePathStyle': '${map['forcePathStyle'] == true}',
          'accessKeyID': '',
          'secretAccessKey': '',
          'sessionToken': '',
        };
      }
    } catch (_) {
      _s3Configured = false;
    }

    try {
      final sched = await AppBridge.call('BackupScheduledGetSettings');
      if (sched is Map) {
        _scheduleSettings = Map<String, dynamic>.from(sched);
      }
    } catch (_) {}

    if (!_openListConfigured) {
      _openListLoaded = false;
      _openListBackups = [];
    }
    if (!_s3Configured) {
      _s3Loaded = false;
      _s3Backups = [];
    }

    if (_historyTab == 1 && _openListConfigured) {
      await _loadOpenListBackups();
    } else if (_historyTab == 2 && _s3Configured) {
      await _loadS3Backups();
    }
  }

  Future<void> _loadOpenListBackups() async {
    if (!_openListConfigured) return;
    if (mounted) setState(() => _loadingRemote = true);
    try {
      final value = await AppBridge.call('BackupOpenListList', [
        _openListPayload,
      ]);
      _openListBackups = (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _openListLoaded = true;
    } catch (error) {
      if (mounted) _message('读取 OpenList 备份失败：$error');
    } finally {
      if (mounted) setState(() => _loadingRemote = false);
    }
  }

  Future<void> _loadS3Backups() async {
    if (!_s3Configured) return;
    if (mounted) setState(() => _loadingRemote = true);
    try {
      final value = await AppBridge.call('BackupS3List', [_s3Payload]);
      _s3Backups = (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _s3Loaded = true;
    } catch (error) {
      if (mounted) _message('读取 S3 备份失败：$error');
    } finally {
      if (mounted) setState(() => _loadingRemote = false);
    }
  }

  void _message(String message) {
    if (mounted) showPrismNotice(context, message);
  }

  Future<void> _run(
    String key,
    Future<dynamic> Function() action, {
    bool resetProgress = false,
  }) async {
    setState(() {
      _busy = key;
      if (resetProgress) {
        _activeProgress = null;
        _progressLogs.clear();
      }
    });
    try {
      final result = await action();
      if (result is Map) {
        final summary = _formatBackupResultSummary(
          Map<String, dynamic>.from(result),
        );
        if (result['cancelled'] != true) {
          _message(summary);
        }
      }
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
      if (_directory.isNotEmpty) {
        await AppBridge.call('BackupSaveLocalDirectory', [_directory]);
      }
      return null;
    });
  }

  Future<void> _openScheduledBackupModal() async {
    Map<String, dynamic> schedule = {};
    try {
      final raw = await AppBridge.call('BackupScheduledGetSettings');
      if (raw is Map) {
        schedule = Map<String, dynamic>.from(raw);
        if (mounted) {
          setState(() => _scheduleSettings = Map<String, dynamic>.from(schedule));
        }
      }
    } catch (error) {
      _message('读取定时备份设置失败：$error');
      return;
    }
    if (!mounted) return;

    var enabled = schedule['enabled'] == true;
    var dailyTime = (schedule['dailyTime'] ?? '03:00').toString();
    var saving = false;
    final timeController = TextEditingController(text: dailyTime);
    var timeError = '';

    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          final authConfigured = schedule['authConfigured'] == true;
          final status = (schedule['status'] ?? 'never').toString();
          final (statusLabel, statusTone) = _scheduleStatusInfo(status);
          final lastSuccessAt = _formatTimestamp(schedule['lastSuccessAt']);
          final lastError = (schedule['lastError'] ?? '').toString().trim();
          final lastRemoteName =
              (schedule['lastRemoteName'] ?? '').toString().trim();
          final recentTimes = (schedule['recentBackupTimes'] as List? ?? [])
              .map(_formatTimestamp)
              .where((item) => item.isNotEmpty)
              .toList();
          final colors = prism.Theme.of(dialogContext).colorScheme;

          return PrismDialog(
            title: const Text('定时备份'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!authConfigured) ...[
                      PrismBanner(
                        tone: PrismTone.warning,
                        title: '尚未配置 OpenList',
                        message: '定时备份会自动上传到 OpenList，请先完成连接与认证配置。',
                        trailing: prism.OutlinedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            widget.onOpenOpenList();
                          },
                          child: const Text('去配置'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用每日自动备份到 OpenList'),
                      subtitle: const Text('如果触发时仍有浏览器实例运行，将自动跳过本次任务。'),
                      value: enabled,
                      onChanged: saving
                          ? null
                          : (value) => setDialog(() => enabled = value),
                    ),
                    const SizedBox(height: 8),
                    PrismTextField(
                      controller: timeController,
                      enabled: !saving,
                      keyboardType: TextInputType.datetime,
                      decoration: PrismInputDecoration(
                        labelText: '每日执行时间（24 小时制 HH:mm）',
                        hintText: '例如 03:00',
                        errorText: timeError.isEmpty ? null : timeError,
                      ),
                      onChanged: (_) {
                        if (timeError.isNotEmpty) {
                          setDialog(() => timeError = '');
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    prism.Surface(
                      color: colors.surfaceContainerLow,
                      shape: prism.AppShape.lg,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '执行状态',
                                  style: prism.AppTextStyle.footnote.of(
                                    dialogContext,
                                    emphasized: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PrismBadge(
                                  label: statusLabel,
                                  tone: statusTone,
                                  dot: true,
                                ),
                              ],
                            ),
                            if (lastSuccessAt.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '上次成功：$lastSuccessAt',
                                style: prism.AppTextStyle.caption1
                                    .of(dialogContext)
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                            if (lastRemoteName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '最近上传：$lastRemoteName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: prism.AppTextStyle.caption1
                                    .of(dialogContext)
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                            if (lastError.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              PrismBanner(
                                tone: PrismTone.danger,
                                message: lastError,
                              ),
                            ],
                            if (recentTimes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                '最近备份时间',
                                style: prism.AppTextStyle.caption1
                                    .of(dialogContext, emphasized: true)
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              for (final time in recentTimes.take(5))
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '• $time',
                                    style: prism.AppTextStyle.caption1
                                        .of(dialogContext)
                                        .copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
              prism.FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final trimmed = timeController.text.trim();
                        if (!RegExp(
                          r'^([01]?\d|2[0-3]):[0-5]\d$',
                        ).hasMatch(trimmed)) {
                          setDialog(
                            () => timeError = '请输入有效的 24 小时时间，例如 03:00',
                          );
                          return;
                        }
                        dailyTime =
                            trimmed.length == 4 ? '0$trimmed' : trimmed;
                        setDialog(() => saving = true);
                        try {
                          final updated = await AppBridge.call(
                            'BackupScheduledSaveSettings',
                            [
                              {
                                'enabled': enabled.toString(),
                                'dailyTime': dailyTime,
                              },
                            ],
                          );
                          if (updated is Map) {
                            schedule = Map<String, dynamic>.from(updated);
                            if (mounted) {
                              setState(() {
                                _scheduleSettings = Map<String, dynamic>.from(
                                  schedule,
                                );
                              });
                            }
                          }
                          if (dialogContext.mounted) {
                            showPrismNotice(dialogContext, '定时备份设置已保存');
                            Navigator.pop(dialogContext);
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialog(() => saving = false);
                            showPrismNotice(dialogContext, '$error');
                          }
                        }
                      },
                child: Text(saving ? '保存中…' : '保存设置'),
              ),
            ],
          );
        },
      ),
    );
    timeController.dispose();
  }

  Future<void> _restoreLocal(Map<String, dynamic> backup) async {
    final accepted = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('合并恢复本地备份？'),
        content: Text('将从「${backup['name'] ?? ''}」合并恢复数据。建议先关闭浏览器实例。'),
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
    if (accepted == true) {
      await _run('restore', () async {
        final value = await AppBridge.call('BackupRestoreLocalPackage', [
          backup['path'],
        ]);
        if (value is Map) {
          return _completeProfileImport(Map<String, dynamic>.from(value));
        }
        return value;
      }, resetProgress: true);
    }
  }

  Future<void> _restoreRemote(String channel, String fileName) async {
    final label = channel == 'openlist' ? 'OpenList' : 'S3';
    final accepted = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text('从 $label 合并恢复？'),
        content: Text('将从 $label 合并恢复「$fileName」中的数据；已有数据会保留。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('合并恢复'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _run('restore', () async {
      final result = await AppBridge.call(
        channel == 'openlist' ? 'BackupOpenListRestore' : 'BackupS3Restore',
        [channel == 'openlist' ? _openListPayload : _s3Payload, fileName],
      );
      if (result is Map) {
        return _completeProfileImport(Map<String, dynamic>.from(result));
      }
      return result;
    }, resetProgress: true);
  }

  Future<void> _downloadRemote(String channel, String fileName) async {
    await _run('download', () async {
      return AppBridge.call(
        channel == 'openlist' ? 'BackupOpenListDownload' : 'BackupS3Download',
        [channel == 'openlist' ? _openListPayload : _s3Payload, fileName],
      );
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
    final search = TextEditingController();
    var sortOrder = 'createdAtDesc';
    final resultIds = await showPrismDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          final selectable = profiles
              .where((profile) => profile['running'] != true)
              .toList();
          final allSelected =
              selectable.isNotEmpty &&
              selectable.every(
                (profile) => selected.contains('${profile['profileId']}'),
              );
          final query = search.text.trim().toLowerCase();
          final visible =
              profiles.where((profile) {
                final name = '${profile['profileName'] ?? ''}'.toLowerCase();
                final id = '${profile['profileId'] ?? ''}'.toLowerCase();
                return query.isEmpty ||
                    name.contains(query) ||
                    id.contains(query);
              }).toList()..sort((left, right) {
                final leftName =
                    '${left['profileName'] ?? left['profileId'] ?? ''}'
                        .toLowerCase();
                final rightName =
                    '${right['profileName'] ?? right['profileId'] ?? ''}'
                        .toLowerCase();
                if (sortOrder == 'profileNameAsc') {
                  return leftName.compareTo(rightName);
                }
                if (sortOrder == 'profileNameDesc') {
                  return rightName.compareTo(leftName);
                }
                final leftCreated = DateTime.tryParse(
                  '${left['createdAt'] ?? ''}',
                );
                final rightCreated = DateTime.tryParse(
                  '${right['createdAt'] ?? ''}',
                );
                final comparison = leftCreated == null || rightCreated == null
                    ? leftName.compareTo(rightName)
                    : leftCreated.compareTo(rightCreated);
                return sortOrder == 'createdAtAsc' ? comparison : -comparison;
              });

          return PrismDialog(
            title: const Text('选择要备份的实例'),
            content: SizedBox(
              width: 620,
              height: 460,
              child: profiles.isEmpty
                  ? const PrismEmptyState(
                      title: '没有可备份的实例',
                      glyph: AntGlyphs.browser,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PrismCheckboxTile(
                          value: allSelected,
                          title: const Text('全选未运行实例'),
                          subtitle: Text('已选 ${selected.length} 个'),
                          onChanged: selectable.isEmpty
                              ? null
                              : (checked) => setDialog(() {
                                  if (checked == true) {
                                    selected
                                      ..clear()
                                      ..addAll(
                                        selectable.map(
                                          (profile) =>
                                              '${profile['profileId']}',
                                        ),
                                      );
                                  } else {
                                    selected.clear();
                                  }
                                }),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: PrismSearchBar(
                                controller: search,
                                hintText: '搜索名称或实例 ID',
                                onChanged: (_) => setDialog(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 190,
                              child: PrismDropdownField<String>(
                                value: sortOrder,
                                decoration: const PrismInputDecoration(
                                  hintText: '排序方式',
                                  isDense: true,
                                ),
                                items: const [
                                  PrismDropdownItem(
                                    value: 'createdAtDesc',
                                    child: Text('创建时间：新到旧'),
                                  ),
                                  PrismDropdownItem(
                                    value: 'createdAtAsc',
                                    child: Text('创建时间：旧到新'),
                                  ),
                                  PrismDropdownItem(
                                    value: 'profileNameAsc',
                                    child: Text('名称：A 到 Z'),
                                  ),
                                  PrismDropdownItem(
                                    value: 'profileNameDesc',
                                    child: Text('名称：Z 到 A'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialog(() => sortOrder = value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: visible.isEmpty
                              ? const PrismEmptyState(
                                  title: '没有匹配的实例',
                                  glyph: AntGlyphs.search,
                                )
                              : ListView.builder(
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final profile = visible[index];
                                    final id = '${profile['profileId'] ?? ''}';
                                    final running = profile['running'] == true;
                                    return PrismCheckboxTile(
                                      value: selected.contains(id),
                                      title: Text(
                                        '${profile['profileName'] ?? id}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: running
                                          ? const Text('运行中，不能备份')
                                          : null,
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
                      ],
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
          );
        },
      ),
    );
    search.dispose();
    return resultIds;
  }

  Future<String?> _askExportPassword() async {
    final password = TextEditingController();
    final confirmPassword = TextEditingController();
    var obscure = true;
    var error = '';
    final result = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('迁移登录态'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '可以设置迁移密码，将实例 Cookie 加密后一并迁移到另一台电脑。',
                  style: prism.AppTextStyle.footnote.of(context),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: PrismTextField(
                        controller: password,
                        obscureText: obscure,
                        onChanged: (_) {
                          if (error.isNotEmpty) setDialog(() => error = '');
                        },
                        decoration: const PrismInputDecoration(
                          labelText: '迁移密码（至少 8 个字符）',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    prism.IconButton(
                      tooltip: obscure ? '显示密码' : '隐藏密码',
                      onPressed: () => setDialog(() => obscure = !obscure),
                      icon: PrismGlyph(
                        obscure ? AntGlyphs.eye : AntGlyphs.eyeOff,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PrismTextField(
                  controller: confirmPassword,
                  obscureText: obscure,
                  onChanged: (_) {
                    if (error.isNotEmpty) setDialog(() => error = '');
                  },
                  decoration: PrismInputDecoration(
                    labelText: '确认迁移密码',
                    errorText: error.isEmpty ? null : error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.OutlinedButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('仅导出配置'),
            ),
            prism.FilledButton(
              onPressed: () {
                if (password.text.runes.length < 8) {
                  setDialog(() => error = '密码至少需要 8 个字符');
                  return;
                }
                if (password.text != confirmPassword.text) {
                  setDialog(() => error = '两次输入的密码不一致');
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
    confirmPassword.dispose();
    return result;
  }

  Future<Set<String>?> _selectDestinations() async {
    await _loadRemoteMetadata();

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
                subtitle: Text(_openListConfigured ? '已配置' : '未配置，选择后会打开设置页'),
                onChanged: (checked) => setDialog(() {
                  checked == true
                      ? selected.add('openlist')
                      : selected.remove('openlist');
                }),
              ),
              PrismCheckboxTile(
                value: selected.contains('s3'),
                title: const Text('S3'),
                subtitle: Text(_s3Configured ? '已配置' : '未配置，选择后会打开设置页'),
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
    if (destinations.contains('openlist') && !_openListConfigured) {
      _message('请先配置 OpenList，再开始备份');
      widget.onOpenOpenList();
      return null;
    }
    if (destinations.contains('s3') && !_s3Configured) {
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
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.OutlinedButton(
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
      resetProgress: true,
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
    }, resetProgress: true);
  }

  Widget _buildProgressSection() {
    final event = _activeProgress!;
    final colors = prism.Theme.of(context).colorScheme;
    final progressNum = (event['progress'] as num?)?.toDouble();
    final progressValue =
        progressNum == null ? null : (progressNum / 100).clamp(0.0, 1.0);
    final componentName = (event['componentName'] ?? '').toString().trim();
    final message = (event['message'] ?? '').toString().trim();
    final entryIndex = (event['entryIndex'] as num?)?.toInt() ?? 0;
    final entryTotal = (event['entryTotal'] as num?)?.toInt() ?? 0;
    final rate = _formatTransferRate(event['bytesPerSecond']);
    final transferred = (event['bytesTransferred'] as num?)?.toInt() ?? 0;
    final totalBytes = (event['totalBytes'] as num?)?.toInt() ?? 0;
    final kindLabel = _progressKind == 'import' ? '正在恢复备份' : '正在导出备份';
    final title = componentName.isEmpty
        ? kindLabel
        : '$kindLabel · $componentName';
    final subtitleParts = <String>[
      if (message.isNotEmpty) message,
      if (entryIndex > 0 && entryTotal > 0) '条目 $entryIndex / $entryTotal',
      if (transferred > 0 && totalBytes > 0)
        '${_formatFileSize(transferred)} / ${_formatFileSize(totalBytes)}',
      if (rate.isNotEmpty) '速度 $rate',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrismProgressPanel(
          title: title,
          subtitle: subtitleParts.join(' · '),
          progress: progressValue,
          trailing: _busy.isEmpty
              ? prism.IconButton(
                  tooltip: '关闭进度面板',
                  onPressed: () => setState(() {
                    _activeProgress = null;
                    _progressLogs.clear();
                  }),
                  icon: const PrismGlyph(AntGlyphs.close, size: 15),
                )
              : null,
        ),
        if (_progressLogs.isNotEmpty) ...[
          const SizedBox(height: 8),
          prism.Surface(
            color: colors.surfaceContainerLow,
            shape: prism.AppShape.lg,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shrinkWrap: true,
                itemCount: _progressLogs.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Text(
                    _progressLogs[index],
                    style: TextStyle(
                      fontFamily: prismMonoFontFamily,
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBackupHistoryItem(
    Map<String, dynamic> backup, {
    required String channel,
  }) {
    final isLocal = channel == 'local';
    final colors = prism.Theme.of(context).colorScheme;
    final name = (backup['name'] ?? '').toString();
    final path = (backup['path'] ?? '').toString();
    final sizeText = _formatFileSize(backup['size']);
    final modifiedAt = _formatTimestamp(backup['modifiedAt']);
    final (badgeLabel, badgeTone) = _backupPackageBadge(
      backup,
      isLocal: isLocal,
    );
    final profileNames = (backup['profileNames'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final profileCount = (backup['profileCount'] as num?)?.toInt() ?? 0;
    final metadataOrphan = backup['metadataOrphan'] == true;
    final metadataUnavailable =
        isLocal &&
        backup.containsKey('metadataAvailable') &&
        backup['metadataAvailable'] == false;
    final metadataError = (backup['metadataError'] ?? '').toString().trim();
    final restoreBlocked = metadataOrphan || metadataUnavailable;

    return PrismCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: prism.AppTextStyle.subheadline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        PrismBadge(label: badgeLabel, tone: badgeTone),
                        if ((backup['size'] as num?) != null)
                          PrismBadge(label: sizeText, tone: PrismTone.neutral),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      modifiedAt.isEmpty ? '时间未知' : '修改时间：$modifiedAt',
                      style: prism.AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                    if (profileCount > 0 || profileNames.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        profileNames.isNotEmpty
                            ? '包含 ${profileCount > 0 ? profileCount : profileNames.length} 个实例：${profileNames.take(5).join('、')}${profileNames.length > 5 ? ' 等' : ''}'
                            : '包含 $profileCount 个实例',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.caption1
                            .of(context)
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                    if (isLocal && path.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      prism.PressRegion(
                        onTap: () => _run(
                          'open',
                          () => AppBridge.call('OpenBackupPath', [path]),
                        ),
                        shape: prism.AppShape.sm,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PrismGlyph(
                                AntGlyphs.folder,
                                size: 13,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: prism.AppTextStyle.caption1
                                      .of(context)
                                      .copyWith(color: colors.primary),
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
              const SizedBox(width: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isLocal)
                    prism.IconButton(
                      tooltip: '打开文件位置',
                      onPressed: path.isEmpty
                          ? null
                          : () => _run(
                              'open',
                              () => AppBridge.call('OpenBackupPath', [path]),
                            ),
                      icon: const PrismGlyph(AntGlyphs.folder, size: 18),
                    )
                  else
                    prism.OutlinedButton.icon(
                      onPressed: _busy.isEmpty
                          ? () => _downloadRemote(channel, name)
                          : null,
                      icon: const PrismGlyph(AntGlyphs.download, size: 15),
                      label: const Text('下载到本地'),
                    ),
                  prism.FilledButton.icon(
                    onPressed: (_busy.isEmpty && !restoreBlocked)
                        ? () => isLocal
                              ? _restoreLocal(backup)
                              : _restoreRemote(channel, name)
                        : null,
                    icon: const PrismGlyph(AntGlyphs.restore, size: 15),
                    label: const Text('合并恢复'),
                  ),
                ],
              ),
            ],
          ),
          if (restoreBlocked) ...[
            const SizedBox(height: 8),
            PrismBanner(
              tone: metadataOrphan ? PrismTone.danger : PrismTone.warning,
              message: metadataOrphan
                  ? '仅找到元数据文件，对应的备份包已缺失，无法恢复。'
                  : (metadataError.isNotEmpty
                        ? '备份元数据不可用（$metadataError），已阻止恢复。'
                        : '备份包信息不可用或已损坏，已阻止恢复。'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryBody() {
    if (_loading || _loadingRemote) {
      return const Center(child: PrismProgressIndicator());
    }
    if (_historyTab == 0) {
      if (_localBackups.isEmpty) {
        return const PrismEmptyState(
          title: '没有找到本地备份',
          subtitle: '点击上方「立即备份」即可创建本地备份包。',
          glyph: AntGlyphs.archive,
        );
      }
      return ListView.separated(
        padding: kPrismListPadding,
        itemCount: _localBackups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _buildBackupHistoryItem(
          _localBackups[index],
          channel: 'local',
        ),
      );
    }
    if (_historyTab == 1) {
      if (!_openListConfigured) {
        return PrismEmptyState(
          title: '尚未配置 OpenList',
          subtitle: '配置 OpenList 连接后，可在此查看、下载或合并恢复云端备份。',
          glyph: AntGlyphs.cloudOff,
          action: PrismHoverMotion(
            child: prism.FilledButton(
              onPressed: widget.onOpenOpenList,
              child: const Text('前往配置 OpenList'),
            ),
          ),
        );
      }
      if (_openListBackups.isEmpty) {
        return const PrismEmptyState(
          title: '没有找到 OpenList 备份',
          subtitle: '创建备份时勾选 OpenList，或前往 OpenList 设置页上传备份。',
          glyph: AntGlyphs.cloud,
        );
      }
      return ListView.separated(
        padding: kPrismListPadding,
        itemCount: _openListBackups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _buildBackupHistoryItem(
          _openListBackups[index],
          channel: 'openlist',
        ),
      );
    }
    if (!_s3Configured) {
      return PrismEmptyState(
        title: '尚未配置 S3 存储',
        subtitle: '配置 S3 兼容存储后，可在此查看、下载或合并恢复远端备份。',
        glyph: AntGlyphs.cloudOff,
        action: PrismHoverMotion(
          child: prism.FilledButton(
            onPressed: widget.onOpenS3,
            child: const Text('前往配置 S3'),
          ),
        ),
      );
    }
    if (_s3Backups.isEmpty) {
      return const PrismEmptyState(
        title: '没有找到 S3 备份',
        subtitle: '创建备份时勾选 S3，或前往 S3 设置页上传备份。',
        glyph: AntGlyphs.cloud,
      );
    }
    return ListView.separated(
      padding: kPrismListPadding,
      itemCount: _s3Backups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildBackupHistoryItem(
        _s3Backups[index],
        channel: 's3',
      ),
    );
  }

  void _selectHistoryTab(int value) {
    setState(() => _historyTab = value);
    if (value == 1 && _openListConfigured) {
      _loadOpenListBackups();
    } else if (value == 2 && _s3Configured) {
      _loadS3Backups();
    }
  }

  Widget _buildOverviewStrip(BuildContext context) {
    var localTotalBytes = 0.0;
    for (final backup in _localBackups) {
      final size = backup['size'];
      if (size is num) {
        localTotalBytes += size.toDouble();
      } else {
        localTotalBytes += double.tryParse('$size') ?? 0;
      }
    }
    final scheduledEnabled = _scheduleSettings['enabled'] == true;
    final scheduledTime = (_scheduleSettings['dailyTime'] ?? '03:00')
        .toString();
    final scheduledStatus = (_scheduleSettings['status'] ?? 'never').toString();
    final (scheduledStatusLabel, _) = _scheduleStatusInfo(scheduledStatus);

    final tiles = [
      PrismMetricTile(
        label: '本地备份',
        value: '${_localBackups.length}',
        subtitle: _localBackups.isEmpty
            ? (_directory.isEmpty ? '尚未选择目录' : '当前目录暂无备份')
            : '共 ${_formatFileSize(localTotalBytes)} · 点击查看',
        glyph: AntGlyphs.archive,
        tone: PrismTone.primary,
        onPressed: () => _selectHistoryTab(0),
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: 'OpenList',
        value: _openListConfigured
            ? (_openListLoaded ? '${_openListBackups.length}' : '已配置')
            : '未配置',
        subtitle: _openListConfigured
            ? (_openListLoaded ? '云端备份包 · 点击查看' : '点击加载云端备份')
            : '点击前往配置连接',
        glyph: _openListConfigured ? AntGlyphs.cloud : AntGlyphs.cloudOff,
        tone: _openListConfigured ? PrismTone.info : PrismTone.neutral,
        onPressed: _openListConfigured
            ? () => _selectHistoryTab(1)
            : widget.onOpenOpenList,
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: 'S3 存储',
        value: _s3Configured
            ? (_s3Loaded ? '${_s3Backups.length}' : '已配置')
            : '未配置',
        subtitle: _s3Configured
            ? (_s3Loaded ? '远端备份包 · 点击查看' : '点击加载远端备份')
            : '点击前往配置存储',
        glyph: _s3Configured ? AntGlyphs.cloudUpload : AntGlyphs.cloudOff,
        tone: _s3Configured ? PrismTone.info : PrismTone.neutral,
        onPressed: _s3Configured ? () => _selectHistoryTab(2) : widget.onOpenS3,
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '定时备份',
        value: scheduledEnabled ? '每日 $scheduledTime' : '未启用',
        subtitle: scheduledEnabled
            ? '上次状态：$scheduledStatusLabel · 点击设置'
            : '自动上传到 OpenList · 点击设置',
        glyph: AntGlyphs.schedule,
        tone: scheduledEnabled
            ? (scheduledStatus == 'failed'
                  ? PrismTone.danger
                  : PrismTone.success)
            : PrismTone.neutral,
        onPressed: _openScheduledBackupModal,
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
    final colors = prism.Theme.of(context).colorScheme;
    final directoryInfo = Row(
      children: [
        PrismGlyph(AntGlyphs.folder, size: 17, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '本地备份目录',
                style: prism.AppTextStyle.caption1.of(
                  context,
                  emphasized: true,
                ),
              ),
              const SizedBox(height: 1),
              prism.SelectableText(
                _directory.isEmpty ? '尚未选择目录' : _directory,
                maxLines: 1,
                style: prism.AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        prism.OutlinedButton(
          onPressed: _busy.isEmpty ? _chooseDirectory : null,
          child: const Text('选择目录'),
        ),
      ],
    );

    final actionWidgets = <Widget>[
      prism.TonalButtonGroup(
        size: prism.TonalButtonSize.section,
        children: [
          prism.IconButton(
            tooltip: 'OpenList 配置',
            onPressed: widget.onOpenOpenList,
            icon: const PrismGlyph(AntGlyphs.cloud, size: 17),
          ),
          prism.IconButton(
            tooltip: 'S3 配置',
            onPressed: widget.onOpenS3,
            icon: const PrismGlyph(AntGlyphs.cloudUpload, size: 17),
          ),
          prism.IconButton(
            tooltip: '定时备份',
            onPressed: _openScheduledBackupModal,
            icon: const PrismGlyph(AntGlyphs.schedule, size: 17),
          ),
          prism.IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const PrismGlyph(AntGlyphs.refresh, size: 17),
          ),
        ],
      ),
      prism.OutlinedButton.icon(
        onPressed: _busy.isEmpty ? _importBackup : null,
        icon: const PrismGlyph(AntGlyphs.restore, size: 15),
        label: const Text('导入备份'),
      ),
      PrismHoverMotion(
        enabled: _busy.isEmpty,
        child: prism.FilledButton.icon(
          onPressed: _busy.isEmpty ? _createBackup : null,
          icon: const PrismGlyph(AntGlyphs.archive, size: 15),
          label: Text(_busy == 'backup' ? '备份中…' : '立即备份'),
        ),
      ),
    ];

    return PrismHoverCard(
      staggerIndex: 4,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 880) {
            return Row(
              children: [
                Expanded(child: directoryInfo),
                const SizedBox(width: 14),
                Wrap(
                  spacing: 8,
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
              directoryInfo,
              const SizedBox(height: 10),
              const prism.Divider(height: 1),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
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

  Widget _buildHistorySection(BuildContext context) {
    final currentCount = switch (_historyTab) {
      0 => _localBackups.length,
      1 => _openListBackups.length,
      _ => _s3Backups.length,
    };
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
            info: const prism.Info(label: '备份历史', glyph: AntGlyphs.history),
            actions: [
              PrismBadge(
                label: '$currentCount 个',
                tone: currentCount == 0
                    ? PrismTone.neutral
                    : PrismTone.primary,
              ),
              SizedBox(
                width: 280,
                child: prism.SegmentedControl<int>(
                  segments: const [(0, '本地'), (1, 'OpenList'), (2, 'S3')],
                  value: _historyTab,
                  onChanged: _selectHistoryTab,
                ),
              ),
            ],
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
          ),
          const prism.Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: prism.PageTransitionSwitcher(
                duration: PrismMotionSpec.current.pageDuration,
                transitionBuilder: PrismSlideThroughTransition.builder,
                child: KeyedSubtree(
                  key: ValueKey(_historyTab),
                  child: _buildHistoryBody(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewStrip(context),
          const SizedBox(height: 12),
          _buildToolbar(context),
          if (_activeProgress != null) ...[
            const SizedBox(height: 12),
            _buildProgressSection(),
          ],
          const SizedBox(height: 12),
          Expanded(child: _buildHistorySection(context)),
        ],
      ),
    );
  }
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
  bool _passwordConfigured = false;
  bool _tokenVisible = false;
  bool _passwordVisible = false;
  bool _revealingToken = false;
  _TestResultState? _testResult;
  List<Map<String, dynamic>> _files = [];

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
      _passwordConfigured =
          value['passwordConfigured'] == true ||
          (_mode == 'basic' && value['authConfigured'] == true);
      _rate.text = (value['uploadRateLimitMBps'] ?? 0).toString();
      if (_url.text.isNotEmpty) await _loadFiles();
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
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

  String? _validateForm() {
    final baseUrl = _url.text.trim();
    if (baseUrl.isEmpty) return '请填写 OpenList 服务地址';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'OpenList 地址格式无效，需以 http:// 或 https:// 开头';
    }
    if (_mode == 'basic') {
      if (_username.text.trim().isEmpty) return 'Basic 认证需要填写用户名';
      if (_password.text.isEmpty && !_passwordConfigured) {
        return 'Basic 认证需要填写密码';
      }
    } else {
      if (_token.text.trim().isEmpty && !_tokenConfigured) {
        return 'Token 认证需要填写 Token';
      }
    }
    final rateText = _rate.text.trim();
    if (rateText.isNotEmpty) {
      final parsed = double.tryParse(rateText);
      if (parsed == null || parsed < 0) return '上传限速必须为非负数字';
    }
    return null;
  }

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
    if (action != 'list') {
      final validationError = _validateForm();
      if (validationError != null) {
        setState(
          () => _testResult = _TestResultState(
            ok: false,
            message: validationError,
          ),
        );
        showPrismNotice(context, validationError);
        return;
      }
    }
    setState(() => _busy = action);
    try {
      if (action == 'test') {
        final res = await AppBridge.call('BackupOpenListTest', [_payload]);
        final msg =
            (res is Map ? res['message']?.toString() : null) ?? 'OpenList 连接成功';
        if (mounted) {
          setState(
            () => _testResult = _TestResultState(ok: true, message: msg),
          );
          showPrismNotice(context, msg);
        }
      } else if (action == 'save') {
        await AppBridge.call('BackupOpenListSaveSettings', [_payload]);
        if (_mode == 'token' && _token.text.trim().isNotEmpty) {
          _tokenConfigured = true;
        }
        if (_mode == 'basic' && _password.text.isNotEmpty) {
          _passwordConfigured = true;
        }
        if (mounted) {
          setState(
            () => _testResult = const _TestResultState(
              ok: true,
              message: 'OpenList 设置已保存',
            ),
          );
          showPrismNotice(context, '设置已保存');
        }
      } else if (action == 'upload') {
        final result = await AppBridge.call('BackupOpenListUpload', [_payload]);
        await _loadFiles();
        if (mounted) {
          final summary = result is Map
              ? _formatBackupResultSummary(Map<String, dynamic>.from(result))
              : '备份上传完成';
          showPrismNotice(context, summary);
        }
      } else {
        await _loadFiles();
      }
    } catch (error) {
      if (mounted) {
        if (action == 'test') {
          setState(
            () => _testResult = _TestResultState(
              ok: false,
              message: '连接测试失败：$error',
            ),
          );
        }
        showPrismNotice(context, error.toString());
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
      if (mounted && completed['cancelled'] != true) {
        showPrismNotice(context, _formatBackupResultSummary(completed));
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
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
      if (mounted) {
        showPrismNotice(
          context,
          ((result as Map?)?['message']?.toString() ?? '下载完成'),
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PrismProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: prism.IconButton(
                onPressed: widget.onBack,
                tooltip: '返回',
                icon: const PrismGlyph(AntGlyphs.arrowBack, size: 18),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: PrismPageContextBar(
                glyph: AntGlyphs.cloud,
                title: 'OpenList 备份设置',
                subtitle: '配置 OpenList 远程备份通道的连接、上传与恢复。',
                actions: [
                  prism.OutlinedButton(
                    onPressed: _busy.isEmpty ? () => _action('test') : null,
                    child: Text(_busy == 'test' ? '测试中…' : '测试连接'),
                  ),
                  PrismHoverMotion(
                    enabled: _busy.isEmpty,
                    child: prism.FilledButton(
                      onPressed: _busy.isEmpty ? () => _action('save') : null,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          PrismBanner(
            tone: _testResult!.ok ? PrismTone.success : PrismTone.danger,
            message: _testResult!.message,
          ),
        ],
        const SizedBox(height: 16),
        PrismSectionCard(
          title: '连接与认证',
          glyph: AntGlyphs.cloud,
          staggerIndex: 0,
          staggerDelay: const Duration(milliseconds: 45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismTextField(
                controller: _url,
                decoration: const PrismInputDecoration(
                  labelText: 'OpenList 地址',
                  hintText: 'https://alist.example.com',
                ),
              ),
              const SizedBox(height: 10),
              PrismTextField(
                controller: _path,
                decoration: const PrismInputDecoration(labelText: '远程目录'),
              ),
              const SizedBox(height: 10),
              PrismDropdownField<String>(
                initialValue: _mode,
                decoration: const PrismInputDecoration(labelText: '认证方式'),
                items: const [
                  PrismDropdownItem(value: 'token', child: Text('Token')),
                  PrismDropdownItem(value: 'basic', child: Text('用户名和密码')),
                ],
                onChanged: (value) => setState(() => _mode = value ?? 'token'),
              ),
              const SizedBox(height: 10),
              if (_mode == 'basic') ...[
                PrismTextField(
                  controller: _username,
                  decoration: const PrismInputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: PrismTextField(
                        controller: _password,
                        obscureText: !_passwordVisible,
                        decoration: PrismInputDecoration(
                          labelText: '密码（留空保留原密码）',
                          hintText: _passwordConfigured ? '已保存，留空将保留原密码' : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    prism.IconButton(
                      tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      icon: PrismGlyph(
                        _passwordVisible ? AntGlyphs.eyeOff : AntGlyphs.eye,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                    const SizedBox(width: 6),
                    prism.IconButton(
                      tooltip: _tokenVisible ? '隐藏 Token' : '显示 Token',
                      onPressed: _busy.isEmpty && !_revealingToken
                          ? _toggleTokenVisibility
                          : null,
                      icon: _revealingToken
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: PrismProgressIndicator(size: 18),
                            )
                          : PrismGlyph(
                              _tokenVisible ? AntGlyphs.eyeOff : AntGlyphs.eye,
                              size: 18,
                            ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              PrismTextField(
                controller: _rate,
                keyboardType: TextInputType.number,
                decoration: const PrismInputDecoration(
                  labelText: '上传限速 MB/s（0 表示不限速）',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                '远程备份文件',
                style: prism.AppTextStyle.headline.of(context),
              ),
            ),
            prism.IconButton(
              tooltip: '刷新列表',
              onPressed: _busy.isEmpty ? () => _action('list') : null,
              icon: const PrismGlyph(AntGlyphs.refresh, size: 18),
            ),
            const SizedBox(width: 6),
            PrismHoverMotion(
              enabled: _busy.isEmpty,
              child: prism.FilledButton.icon(
                onPressed: _busy.isEmpty ? () => _action('upload') : null,
                icon: const PrismGlyph(AntGlyphs.cloudUpload, size: 16),
                label: Text(_busy == 'upload' ? '上传中…' : '创建并上传备份'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_files.isEmpty)
          const PrismEmptyState(
            title: '没有找到远程备份',
            glyph: AntGlyphs.cloud,
          ),
        for (final file in _files)
          PrismCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: PrismListTile(
              title: Text(
                (file['name'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${_formatFileSize(file['size'])} · ${_formatTimestamp(file['modifiedAt'])}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  prism.IconButton(
                    tooltip: '下载到本地',
                    onPressed: _busy.isEmpty
                        ? () => _download((file['name'] ?? '').toString())
                        : null,
                    icon: const PrismGlyph(AntGlyphs.download, size: 18),
                  ),
                  prism.TextButton(
                    onPressed: _busy.isEmpty
                        ? () => _restore((file['name'] ?? '').toString())
                        : null,
                    child: const Text('合并恢复'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
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
  _TestResultState? _testResult;
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
      if (mounted) showPrismNotice(context, error.toString());
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

  String? _validateForm() {
    final endpoint = _endpoint.text.trim();
    if (endpoint.isEmpty) return '请填写 S3 Endpoint';
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'Endpoint 格式无效，需以 http:// 或 https:// 开头';
    }
    if (_region.text.trim().isEmpty) return '请填写 Region';
    if (_bucket.text.trim().isEmpty) return '请填写 Bucket 名称';
    if (_accessKey.text.trim().isEmpty &&
        _credentialConfigured['accessKeyID'] != true) {
      return '请填写 Access Key ID';
    }
    if (_secret.text.trim().isEmpty &&
        _credentialConfigured['secretAccessKey'] != true) {
      return '请填写 Secret Access Key';
    }
    return null;
  }

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
    tooltip: _visibleCredentials[field] == true ? '隐藏凭据' : '显示凭据',
    onPressed: _busy.isEmpty && _revealingCredential.isEmpty
        ? () => _toggleCredentialVisibility(field, controller)
        : null,
    icon: _revealingCredential == field
        ? const SizedBox(
            width: 18,
            height: 18,
            child: PrismProgressIndicator(size: 18),
          )
        : PrismGlyph(
            _visibleCredentials[field] == true
                ? AntGlyphs.eyeOff
                : AntGlyphs.eye,
            size: 18,
          ),
  );

  Future<void> _action(String method) async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(
        () => _testResult = _TestResultState(
          ok: false,
          message: validationError,
        ),
      );
      showPrismNotice(context, validationError);
      return;
    }
    setState(() => _busy = method);
    try {
      if (method == 'BackupS3Test') {
        final res = await AppBridge.call(method, [_payload]);
        final msg =
            (res is Map ? res['message']?.toString() : null) ?? 'S3 连接测试成功';
        if (mounted) {
          setState(
            () => _testResult = _TestResultState(ok: true, message: msg),
          );
          showPrismNotice(context, msg);
        }
      } else {
        await AppBridge.call('BackupS3SaveSettings', [_payload]);
        if (_accessKey.text.trim().isNotEmpty) {
          _credentialConfigured['accessKeyID'] = true;
        }
        if (_secret.text.trim().isNotEmpty) {
          _credentialConfigured['secretAccessKey'] = true;
        }
        if (_token.text.trim().isNotEmpty) {
          _credentialConfigured['sessionToken'] = true;
        }
        await _loadFiles();
        if (mounted) {
          setState(
            () => _testResult = const _TestResultState(
              ok: true,
              message: 'S3 设置已保存',
            ),
          );
          showPrismNotice(context, '设置已保存');
        }
      }
    } catch (error) {
      if (mounted) {
        if (method == 'BackupS3Test') {
          setState(
            () => _testResult = _TestResultState(
              ok: false,
              message: '连接测试失败：$error',
            ),
          );
        }
        showPrismNotice(context, error.toString());
      }
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
      if (mounted) showPrismNotice(context, error.toString());
    }
  }

  Future<void> _upload() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(
        () => _testResult = _TestResultState(
          ok: false,
          message: validationError,
        ),
      );
      showPrismNotice(context, validationError);
      return;
    }
    setState(() => _busy = 'upload');
    try {
      final result = await AppBridge.call('BackupS3Upload', [_payload]);
      await _loadFiles();
      if (mounted) {
        final summary = result is Map
            ? _formatBackupResultSummary(Map<String, dynamic>.from(result))
            : '上传完成';
        showPrismNotice(context, summary);
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
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
      if (mounted && completed['cancelled'] != true) {
        showPrismNotice(context, _formatBackupResultSummary(completed));
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _downloadS3(String name) async {
    setState(() => _busy = 'download');
    try {
      final result = await AppBridge.call('BackupS3Download', [_payload, name]);
      if (mounted) {
        showPrismNotice(
          context,
          ((result as Map?)?['message']?.toString() ?? '下载完成'),
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PrismProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: prism.IconButton(
                onPressed: widget.onBack,
                tooltip: '返回',
                icon: const PrismGlyph(AntGlyphs.arrowBack, size: 18),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: PrismPageContextBar(
                glyph: AntGlyphs.cloudUpload,
                title: 'S3 备份设置',
                subtitle: '配置 S3 兼容对象存储备份通道的连接、上传与恢复。',
                actions: [
                  prism.OutlinedButton(
                    onPressed: _busy.isEmpty
                        ? () => _action('BackupS3Test')
                        : null,
                    child: Text(_busy == 'BackupS3Test' ? '测试中…' : '测试连接'),
                  ),
                  PrismHoverMotion(
                    enabled: _busy.isEmpty,
                    child: prism.FilledButton(
                      onPressed: _busy.isEmpty ? () => _action('save') : null,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          PrismBanner(
            tone: _testResult!.ok ? PrismTone.success : PrismTone.danger,
            message: _testResult!.message,
          ),
        ],
        const SizedBox(height: 16),
        PrismSectionCard(
          title: '存储桶与凭据',
          glyph: AntGlyphs.cloudUpload,
          staggerIndex: 0,
          staggerDelay: const Duration(milliseconds: 45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismTextField(
                controller: _endpoint,
                decoration: const PrismInputDecoration(
                  labelText: 'Endpoint',
                  hintText: 'https://s3.amazonaws.com',
                ),
              ),
              const SizedBox(height: 10),
              PrismTextField(
                controller: _region,
                decoration: const PrismInputDecoration(labelText: 'Region'),
              ),
              const SizedBox(height: 10),
              PrismTextField(
                controller: _bucket,
                decoration: const PrismInputDecoration(labelText: 'Bucket'),
              ),
              const SizedBox(height: 10),
              PrismTextField(
                controller: _prefix,
                decoration: const PrismInputDecoration(labelText: '备份目录前缀'),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
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
                  const SizedBox(width: 6),
                  _credentialVisibilityButton('accessKeyID', _accessKey),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: PrismTextField(
                      controller: _secret,
                      obscureText:
                          _visibleCredentials['secretAccessKey'] != true,
                      decoration: PrismInputDecoration(
                        labelText: 'Secret Access Key',
                        hintText:
                            _credentialConfigured['secretAccessKey'] == true
                            ? '已保存，点击眼睛查看'
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _credentialVisibilityButton('secretAccessKey', _secret),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
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
                  const SizedBox(width: 6),
                  _credentialVisibilityButton('sessionToken', _token),
                ],
              ),
              const SizedBox(height: 8),
              PrismSwitchTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('强制使用路径风格地址'),
                value: _pathStyle,
                onChanged: (value) => setState(() => _pathStyle = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'S3 备份文件',
                style: prism.AppTextStyle.headline.of(context),
              ),
            ),
            prism.IconButton(
              tooltip: '刷新列表',
              onPressed: _busy.isEmpty ? _refreshS3 : null,
              icon: const PrismGlyph(AntGlyphs.refresh, size: 18),
            ),
            const SizedBox(width: 6),
            PrismHoverMotion(
              enabled: _busy.isEmpty,
              child: prism.FilledButton.icon(
                onPressed: _busy.isEmpty ? _upload : null,
                icon: const PrismGlyph(AntGlyphs.cloudUpload, size: 16),
                label: Text(_busy == 'upload' ? '上传中…' : '创建并上传备份'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_files.isEmpty)
          const PrismEmptyState(
            title: '没有找到 S3 备份文件',
            glyph: AntGlyphs.cloud,
          ),
        for (final file in _files)
          PrismCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: PrismListTile(
              title: Text(
                (file['name'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${_formatFileSize(file['size'])} · ${_formatTimestamp(file['modifiedAt'])}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  prism.IconButton(
                    tooltip: '下载到本地',
                    onPressed: _busy.isEmpty
                        ? () => _downloadS3((file['name'] ?? '').toString())
                        : null,
                    icon: const PrismGlyph(AntGlyphs.download, size: 18),
                  ),
                  prism.TextButton(
                    onPressed: _busy.isEmpty
                        ? () => _restoreS3((file['name'] ?? '').toString())
                        : null,
                    child: const Text('合并恢复'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
