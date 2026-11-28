import 'dart:async';

import 'package:prism_ui/icons/icons.dart' as prism_icons;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

const _remoteAuthorUrl = '';
const _remoteAuthorTimeoutMs = 1000;
const _projectUrl = 'https://github.com/starrynight168/Ant-Browser';
const _upstreamUrl = 'https://github.com/black-ant/Ant-Browser';
const _upstreamAuthorUrl = 'https://github.com/black-ant';
const _defaultAuthor = <String, dynamic>{
  'name': 'Ant Browser',
  'initial': 'A',
  'title': '多账号指纹浏览器桌面端',
  'bio': '支持多实例独立环境隔离、代理池调度与脚本自动化，专注轻量、流畅的桌面使用体验。',
  'location': '',
  'joinDate': '',
  'email': '',
  'website': '',
  'github': _projectUrl,
  'skills': ['Flutter', 'Dart', 'Go', 'Prism UI'],
  'channels': [
    {
      'name': '上游项目',
      'detail': 'black-ant/Ant-Browser',
      'href': _upstreamUrl,
      'icon': 'github',
    },
    {
      'name': '原作者',
      'detail': 'black-ant',
      'href': _upstreamAuthorUrl,
      'icon': 'github',
    },
    {
      'name': '版本发布',
      'detail': 'GitHub Releases',
      'href': 'https://github.com/starrynight168/Ant-Browser/releases',
      'icon': 'globe',
    },
  ],
};
const _projectProfile = <String, dynamic>{
  'name': 'Ant Browser',
  'techStack': ['Flutter', 'Dart', 'Go', 'Prism UI'],
  'description': '基于开源项目 black-ant/Ant-Browser 构建，感谢原作者与社区贡献者。遵循 PolyForm Noncommercial 1.0.0 协议，仅供非商业用途使用。',
  'actions': [
    {
      'label': '更新日志',
      'href': 'https://github.com/starrynight168/Ant-Browser/releases',
      'icon': 'globe',
    },
    {
      'label': '开源协议',
      'href': 'https://github.com/black-ant/Ant-Browser/blob/master/LICENSE',
      'icon': 'license',
    },
  ],
};

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.onUpdateStatusChanged});

  final ValueChanged<bool>? onUpdateStatusChanged;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '读取中';
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  late Map<String, dynamic> _author;
  final Map<String, dynamic> _project = Map<String, dynamic>.from(
    _projectProfile,
  );
  Map<String, dynamic>? _updateResult;
  Map<String, dynamic>? _updateProgress;
  Map<String, dynamic>? _downloadedUpdate;
  Map<String, dynamic>? _pendingUpdate;
  late final void Function() _removeProgressListener;
  late final void Function() _removePendingListener;

  @override
  void initState() {
    super.initState();
    _author = Map<String, dynamic>.from(_defaultAuthor);
    _loadVersion();
    _loadAuthor();
    _loadLocalUpdateState();
    _removeProgressListener = AppBridge.onEvent('app:update:progress', (
      payload,
    ) {
      if (!mounted || payload is! Map) return;
      final progress = Map<String, dynamic>.from(payload);
      final phase = '${progress['phase'] ?? ''}';
      setState(() {
        _updateProgress = progress;
        if (phase == 'done' || phase == 'error') {
          _downloading = false;
        }
      });
      if (phase == 'done') {
        _refreshDownloadedUpdate();
      }
    });
    _removePendingListener = AppBridge.onEvent('app:update:pending', (payload) {
      if (!mounted || payload is! Map) return;
      setState(() => _pendingUpdate = Map<String, dynamic>.from(payload));
    });
  }

  @override
  void dispose() {
    _removeProgressListener();
    _removePendingListener();
    super.dispose();
  }

  Future<void> _loadLocalUpdateState() async {
    await Future.wait([_refreshDownloadedUpdate(), _refreshPendingUpdate()]);
  }

  Future<void> _refreshDownloadedUpdate() async {
    try {
      final res = await AppBridge.call('GetDownloadedAppUpdate');
      if (mounted) {
        setState(
          () => _downloadedUpdate = res is Map
              ? Map<String, dynamic>.from(res)
              : null,
        );
      }
    } catch (_) {}
  }

  Future<void> _refreshPendingUpdate() async {
    try {
      final res = await AppBridge.call('GetPendingAppUpdate');
      if (mounted) {
        setState(
          () => _pendingUpdate = res is Map
              ? Map<String, dynamic>.from(res)
              : null,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadAuthor() async {
    if (_remoteAuthorUrl.trim().isEmpty) {
      return;
    }
    try {
      final payload = await AppBridge.call('FetchRemoteAuthorProfile', [
        _remoteAuthorUrl,
        _remoteAuthorTimeoutMs,
      ]);
      if (mounted) setState(() => _author = _normalizeAuthor(payload));
    } catch (_) {
      if (mounted) {
        setState(() {
          _author = Map<String, dynamic>.from(_defaultAuthor);
        });
      }
    }
  }

  Map<String, dynamic> _normalizeAuthor(dynamic payload) {
    final source = payload is Map && payload['author'] is Map
        ? Map<String, dynamic>.from(payload['author'] as Map)
        : payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    String value(String key, [String? fallback]) {
      final text = (source[key] ?? '').toString().trim();
      return text.isEmpty
          ? fallback ?? (_defaultAuthor[key] ?? '').toString()
          : text;
    }

    final name = value('name');
    final skills = source['skills'] is List
        ? (source['skills'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : <String>[];
    final channels = source['channels'] is List
        ? (source['channels'] as List)
              .whereType<Map>()
              .map((channel) {
                final result = Map<String, dynamic>.from(channel);
                final href = (result['href'] ?? result['url'] ?? '')
                    .toString()
                    .trim();
                result['href'] = href;
                result['name'] = (result['name'] ?? '').toString().trim();
                result['description'] = (result['description'] ?? '')
                    .toString()
                    .trim();
                result['detail'] = (result['detail'] ?? result['value'] ?? '')
                    .toString()
                    .trim();
                return result;
              })
              .where((channel) => (channel['name'] ?? '').toString().isNotEmpty)
              .toList()
        : <Map<String, dynamic>>[];
    final fallbackChannels = (_defaultAuthor['channels'] as List)
        .whereType<Map>()
        .map((channel) => Map<String, dynamic>.from(channel))
        .toList();
    return {
      'name': name,
      'initial': value('initial', name.isEmpty ? '志' : name[0]),
      'title': value('title'),
      'bio': value('bio'),
      'location': value('location'),
      'joinDate': value('joinDate'),
      'email': value('email'),
      'website': value('website'),
      'github': value('github'),
      'skills': skills.isEmpty
          ? List<String>.from(_defaultAuthor['skills'] as List)
          : skills,
      'channels': channels.isEmpty ? fallbackChannels : channels,
    };
  }

  Future<void> _loadVersion() async {
    try {
      final config = await AppBridge.call('GetAppConfig');
      if (mounted) {
        setState(
          () =>
              _version = config is Map ? '${config['version'] ?? '未知'}' : '未知',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _version = '未知');
    }
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await AppBridge.call('CheckAppUpdate');
      if (mounted) {
        final map = result is Map ? Map<String, dynamic>.from(result) : null;
        setState(() => _updateResult = map);
        widget.onUpdateStatusChanged?.call(
          map?['ok'] == true && map?['updateAvailable'] == true,
        );
      }
      await _loadLocalUpdateState();
    } catch (error) {
      if (mounted) {
        setState(() => _updateResult = {'error': error.toString()});
        widget.onUpdateStatusChanged?.call(false);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _normalizeUpdateVersion(String v) =>
      v.trim().replaceFirst(RegExp(r'^[vV]'), '');

  Future<void> _openDownloadWithProxyDialog() async {
    if (_downloading) return;
    var proxyOptions = <Map<String, dynamic>>[];
    try {
      final list = await AppBridge.call('BrowserProxyList');
      if (list is List) {
        proxyOptions = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where(
              (e) =>
                  (e['proxyId'] ?? '').toString().trim().isNotEmpty &&
                  e['proxyId'] != '__direct__',
            )
            .toList();
      }
    } catch (_) {}
    if (!mounted) return;
    var proxyMode = 'direct';
    var selectedProxyId = proxyOptions.isNotEmpty
        ? (proxyOptions.first['proxyId'] ?? '').toString()
        : '';
    final customProxyController = TextEditingController();
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => PrismDialog(
          title: const Text('下载更新 · 选择代理'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrismDropdownField<String>(
                  initialValue: proxyMode,
                  decoration: const PrismInputDecoration(labelText: '下载方式'),
                  items: const [
                    PrismDropdownItem(value: 'direct', child: Text('直连下载')),
                    PrismDropdownItem(value: 'pool', child: Text('使用代理池节点')),
                    PrismDropdownItem(value: 'custom', child: Text('自定义代理地址')),
                  ],
                  onChanged: (value) =>
                      setDialog(() => proxyMode = value ?? 'direct'),
                ),
                if (proxyMode == 'pool') ...[
                  const SizedBox(height: 14),
                  if (proxyOptions.isEmpty)
                    const PrismBanner(
                      tone: PrismTone.warning,
                      message: '代理池中暂无可用节点，请切换直连或自定义代理地址',
                    )
                  else
                    PrismDropdownField<String>(
                      initialValue: selectedProxyId,
                      decoration: const PrismInputDecoration(labelText: '代理节点'),
                      items: [
                        for (final item in proxyOptions)
                          PrismDropdownItem(
                            value: (item['proxyId'] ?? '').toString(),
                            child: Text(
                              (item['proxyName'] ?? item['proxyId'] ?? '')
                                  .toString(),
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialog(() => selectedProxyId = value ?? ''),
                    ),
                ],
                if (proxyMode == 'custom') ...[
                  const SizedBox(height: 14),
                  PrismTextField(
                    controller: customProxyController,
                    decoration: const PrismInputDecoration(
                      labelText: '代理地址（http:// 或 socks5://）',
                      hintText: 'socks5://127.0.0.1:7890',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () {
                if (proxyMode == 'pool' && selectedProxyId.isEmpty) {
                  showPrismNotice(dialogContext, '请先选择代理节点');
                  return;
                }
                if (proxyMode == 'custom' &&
                    customProxyController.text.trim().isEmpty) {
                  showPrismNotice(dialogContext, '请填写代理地址');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('开始下载'),
            ),
          ],
        ),
      ),
    );
    final customProxy = customProxyController.text.trim();
    customProxyController.dispose();
    if (confirmed != true || !mounted) return;

    var proxyConfig = '';
    var proxyId = '';
    if (proxyMode == 'pool') {
      final selected = proxyOptions
          .where((e) => (e['proxyId'] ?? '').toString() == selectedProxyId)
          .firstOrNull;
      proxyConfig = (selected?['proxyConfig'] ?? '').toString().trim();
      proxyId = (selected?['proxyId'] ?? selectedProxyId).toString();
    } else if (proxyMode == 'custom') {
      proxyConfig = customProxy;
    }

    setState(() {
      _downloading = true;
      _updateProgress = {
        'phase': 'resolving',
        'progress': 0,
        'message': proxyConfig.isNotEmpty || proxyId.isNotEmpty
            ? '准备下载（使用指定代理）'
            : '准备下载（直连）',
      };
    });
    try {
      await AppBridge.call('DownloadAppUpdateWithProxySelection', [
        '',
        '',
        proxyConfig,
        proxyId,
      ]);
    } catch (error) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _updateProgress = {
            'phase': 'error',
            'progress': 0,
            'message': error.toString(),
          };
        });
        showPrismNotice(context, '启动下载失败：$error');
      }
    }
  }

  Future<void> _clearPendingUpdate() async {
    try {
      await AppBridge.call('ClearPendingAppUpdate');
      if (!mounted) return;
      setState(() => _pendingUpdate = null);
      showPrismNotice(context, '已忽略待安装更新');
    } catch (error) {
      if (mounted) showPrismNotice(context, '忽略失败：$error');
    }
  }

  Future<void> _clearDownloadedUpdate() async {
    try {
      await AppBridge.call('ClearDownloadedAppUpdate');
      if (!mounted) return;
      setState(() => _downloadedUpdate = null);
      widget.onUpdateStatusChanged?.call(false);
      showPrismNotice(context, '已忽略已下载的更新');
    } catch (error) {
      if (mounted) showPrismNotice(context, '忽略失败：$error');
    }
  }

  Future<void> _confirmAndApplyUpdate({bool fromPending = false}) async {
    if (_installing) return;
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => PrismDialog(
        title: const Text('退出并安装更新'),
        content: const Text('应用将立即退出，随后自动打开已下载的安装包。系统可能弹出权限确认，请按提示完成安装。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('退出并安装'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _installing = true);
    try {
      if (fromPending) {
        await AppBridge.call('ApplyPendingAppUpdate');
      } else {
        final targetVersion =
            '${_downloadedUpdate?['version'] ?? _updateResult?['latestVersion'] ?? ''}';
        await AppBridge.call('ApplyAppUpdate', [targetVersion, '']);
      }
      if (!mounted) return;
      showPrismNotice(context, '即将退出并启动安装程序…');
      await Future<void>.delayed(const Duration(milliseconds: 650));
      await AppBridge.call('QuitAppOnly');
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, '准备安装失败：$error');
        await _loadLocalUpdateState();
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channels = (_author['channels'] as List? ?? [])
        .whereType<Map>()
        .map((channel) => Map<String, dynamic>.from(channel))
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _authorCard(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 560
                  ? 1
                  : constraints.maxWidth < 850
                  ? 2
                  : 3;
              final cardWidth = columns == 1
                  ? constraints.maxWidth
                  : ((constraints.maxWidth - 16 * (columns - 1)) / columns)
                        .floorToDouble();
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (var i = 0; i < channels.length; i++)
                    SizedBox(
                      width: cardWidth,
                      child: _channelCard(channels[i], staggerIndex: 1 + i),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _projectCard(staggerIndex: 1 + channels.length),
        ],
      ),
    );
  }

  Widget _authorCard() {
    final colors = prism.Theme.of(context).colorScheme;
    final name = (_author['name'] ?? '').toString();
    final github = (_author['github'] ?? '').toString().trim();
    final website = (_author['website'] ?? '').toString().trim();
    final email = (_author['email'] ?? '').toString().trim();
    return PrismSectionCard(
      padding: const EdgeInsets.all(22),
      staggerIndex: 0,
      staggerDelay: const Duration(milliseconds: 45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 64,
                child: prism.Surface(
                  color: colors.primary,
                  shape: prism.AppShape.circle,
                  child: Center(
                    child: Text(
                      (_author['initial'] ?? (name.isEmpty ? 'A' : name[0]))
                          .toString(),
                      style: prism.AppTextStyle.title1
                          .of(context, emphasized: true)
                          .copyWith(color: colors.onPrimary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.title2.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (_author['title'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.subheadline
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            (_author['bio'] ?? '').toString(),
            style: prism.AppTextStyle.body
                .of(context)
                .copyWith(height: 1.7, color: colors.onSurfaceVariant),
          ),
          if ((_author['location'] ?? '').toString().trim().isNotEmpty ||
              (_author['joinDate'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                if ((_author['location'] ?? '').toString().trim().isNotEmpty)
                  _MetaLabel(
                    glyph: AntGlyphs.location,
                    text: _author['location'].toString(),
                  ),
                if ((_author['joinDate'] ?? '').toString().trim().isNotEmpty)
                  _MetaLabel(
                    glyph: AntGlyphs.calendar,
                    text: '加入于 ${_author['joinDate']}',
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              if (github.isNotEmpty)
                prism.OutlinedButton.icon(
                  onPressed: () => AppBridge.openExternal(github),
                  icon: const PrismGlyph(AntGlyphs.code, size: 17),
                  label: const Text('项目主页'),
                ),
              if (website.isNotEmpty)
                prism.OutlinedButton.icon(
                  onPressed: () => AppBridge.openExternal(website),
                  icon: const PrismGlyph(AntGlyphs.globe, size: 17),
                  label: Text(_stripProtocol(website)),
                ),
              if (email.isNotEmpty)
                prism.OutlinedButton.icon(
                  onPressed: () => AppBridge.openExternal('mailto:$email'),
                  icon: const PrismGlyph(AntGlyphs.mail, size: 17),
                  label: const Text('联系作者'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _channelCard(
    Map<String, dynamic> channel, {
    required int staggerIndex,
  }) {
    final colors = prism.Theme.of(context).colorScheme;
    final primaryTone = PrismToneColors.of(context, PrismTone.primary);
    final href = (channel['href'] ?? '').toString().trim();
    final title = (channel['name'] ?? '').toString();
    final detail = (channel['detail'] ?? '').toString();
    return PrismHoverCard(
      staggerIndex: staggerIndex,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      onPressed: href.isEmpty ? null : () => AppBridge.openExternal(href),
      inert: href.isEmpty,
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            prism.Surface(
              color: primaryTone.bg,
              shape: prism.AppShape.md,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: PrismGlyph(
                  _profileGlyph((channel['icon'] ?? '').toString(), title),
                  size: 20,
                  color: primaryTone.fg,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: prism.AppTextStyle.headline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (href.isNotEmpty) ...[
              const SizedBox(width: 8),
              PrismGlyph(
                AntGlyphs.openInNew,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  prism_icons.Glyph _profileGlyph(String icon, String label) {
    final key = '$icon $label'.toLowerCase();
    if (key.contains('github') || key.contains('code') || key.contains('源码')) {
      return AntGlyphs.code;
    }
    if (key.contains('book') || key.contains('juejin') || key.contains('文章')) {
      return AntGlyphs.book;
    }
    if (key.contains('message') ||
        key.contains('wechat') ||
        key.contains('公众号')) {
      return AntGlyphs.chat;
    }
    if (key.contains('globe') || key.contains('web') || key.contains('博客')) {
      return AntGlyphs.globe;
    }
    return AntGlyphs.link;
  }

  String _stripProtocol(String url) => url
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceFirst(RegExp(r'/$'), '');

  Widget _projectCard({required int staggerIndex}) {
    final colors = prism.Theme.of(context).colorScheme;
    final result = _updateResult;
    final releaseUrl = '${result?['releaseUrl'] ?? ''}'.trim();
    final canOpenDownload =
        result != null &&
        result['ok'] == true &&
        result['updateAvailable'] == true &&
        releaseUrl.isNotEmpty;
    final hasError = result?['error']?.toString().isNotEmpty == true;
    final updateAvailable = result?['updateAvailable'] == true;
    final latestVersion = '${result?['latestVersion'] ?? ''}'.trim();
    final notesUrl = '${result?['notesUrl'] ?? ''}'.trim();
    final downloadedVersion = '${_downloadedUpdate?['version'] ?? ''}'.trim();
    final downloadedMatchesLatest =
        downloadedVersion.isNotEmpty &&
        latestVersion.isNotEmpty &&
        _normalizeUpdateVersion(downloadedVersion) ==
            _normalizeUpdateVersion(latestVersion);
    final updateDone = '${_updateProgress?['phase'] ?? ''}' == 'done';
    final updateText = result == null
        ? ''
        : updateAvailable
        ? '发现新版本 v$latestVersion'
        : hasError
        ? result['error'].toString()
        : '当前已是最新版本';

    return PrismSectionCard(
      title: '致谢与更新',
      glyph: AntGlyphs.browser,
      padding: const EdgeInsets.all(22),
      staggerIndex: staggerIndex,
      staggerDelay: const Duration(milliseconds: 45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (_project['description'] ?? '').toString(),
            style: prism.AppTextStyle.body
                .of(context)
                .copyWith(color: colors.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final item in (_project['techStack'] as List? ?? []))
                _SkillChip(label: item.toString()),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final action
                  in (_project['actions'] as List? ?? []).whereType<Map>())
                prism.OutlinedButton.icon(
                  onPressed: (action['href'] ?? '').toString().trim().isEmpty
                      ? null
                      : () => AppBridge.openExternal(action['href'].toString()),
                  icon: PrismGlyph(
                    _profileGlyph(
                      (action['icon'] ?? '').toString(),
                      (action['label'] ?? '').toString(),
                    ),
                    size: 17,
                  ),
                  label: Text((action['label'] ?? '').toString()),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const prism.Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              PrismGlyph(
                AntGlyphs.info,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前版本：$_version',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: prism.AppTextStyle.subheadline.of(
                    context,
                    emphasized: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (updateAvailable) ...[
                if (updateDone || downloadedMatchesLatest)
                  prism.FilledButton.icon(
                    onPressed: _installing
                        ? null
                        : () => _confirmAndApplyUpdate(),
                    icon: const PrismGlyph(AntGlyphs.download, size: 15),
                    label: Text(_installing ? '准备安装…' : '退出并安装'),
                  )
                else
                  prism.FilledButton.icon(
                    onPressed: _downloading
                        ? null
                        : _openDownloadWithProxyDialog,
                    icon: const PrismGlyph(AntGlyphs.download, size: 15),
                    label: Text(_downloading ? '下载中…' : '下载更新'),
                  ),
                const SizedBox(width: 10),
              ],
              PrismTonalButton(
                onPressed: _checking ? null : _checkUpdate,
                child: _checking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: PrismProgressIndicator(size: 16),
                      )
                    : const Text('检查更新'),
              ),
            ],
          ),
          if (_pendingUpdate != null) ...[
            const SizedBox(height: 16),
            PrismBanner(
              tone: _pendingUpdate!['missing'] == true
                  ? PrismTone.danger
                  : PrismTone.warning,
              title: _pendingUpdate!['missing'] == true
                  ? '待安装更新包已丢失'
                  : '有已下载待安装的更新 v${_pendingUpdate!['version'] ?? ''}',
              message: _pendingUpdate!['missing'] == true
                  ? '请点击“检查更新”重新下载最新安装包。'
                  : '上次已下载更新包，可点击右侧按钮立即退出并安装。',
              trailing: _pendingUpdate!['missing'] == true
                  ? prism.OutlinedButton(
                      onPressed: _clearPendingUpdate,
                      child: const Text('忽略'),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        prism.OutlinedButton(
                          onPressed: _installing ? null : _clearPendingUpdate,
                          child: const Text('忽略'),
                        ),
                        prism.FilledButton(
                          onPressed: _installing
                              ? null
                              : () => _confirmAndApplyUpdate(fromPending: true),
                          child: const Text('退出并安装'),
                        ),
                      ],
                    ),
            ),
          ] else if (_downloadedUpdate != null) ...[
            const SizedBox(height: 16),
            PrismBanner(
              tone: PrismTone.info,
              title: '已下载新版本 v${_downloadedUpdate!['version'] ?? ''}',
              message: '安装包已就绪，可点击右侧按钮立即退出并安装。',
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  prism.OutlinedButton(
                    onPressed: _installing ? null : _clearDownloadedUpdate,
                    child: const Text('忽略'),
                  ),
                  prism.FilledButton(
                    onPressed: _installing
                        ? null
                        : () => _confirmAndApplyUpdate(),
                    child: const Text('退出并安装'),
                  ),
                ],
              ),
            ),
          ],
          if (_updateProgress != null &&
              (_downloading ||
                  '${_updateProgress?['phase'] ?? ''}' == 'done' ||
                  '${_updateProgress?['phase'] ?? ''}' == 'error')) ...[
            const SizedBox(height: 16),
            PrismProgressPanel(
              title: '${_updateProgress?['phase'] ?? ''}' == 'done'
                  ? '更新包已就绪'
                  : '${_updateProgress?['phase'] ?? ''}' == 'error'
                  ? '下载失败'
                  : '正在下载更新',
              subtitle: '${_updateProgress?['message'] ?? ''}',
              progress:
                  (((_updateProgress?['progress'] as num?) ?? 0).toDouble() /
                          100.0)
                      .clamp(0.0, 1.0),
            ),
          ],
          if (updateText.isNotEmpty) ...[
            const SizedBox(height: 16),
            PrismBanner(
              tone: hasError
                  ? PrismTone.danger
                  : updateAvailable
                  ? PrismTone.info
                  : PrismTone.success,
              message: updateText,
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (updateAvailable && notesUrl.isNotEmpty)
                    prism.OutlinedButton(
                      onPressed: () => AppBridge.openExternal(notesUrl),
                      child: const Text('更新说明'),
                    ),
                  if (canOpenDownload)
                    prism.OutlinedButton.icon(
                      onPressed: () => AppBridge.openExternal(releaseUrl),
                      icon: const PrismGlyph(AntGlyphs.openInNew, size: 15),
                      label: const Text('打开下载页面'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.glyph, required this.text});

  final prism_icons.Glyph glyph;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrismGlyph(glyph, size: 15, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          text,
          style: prism.AppTextStyle.footnote
              .of(context)
              .copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return prism.TonalChip(
      label: label,
      color: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
    );
  }
}
