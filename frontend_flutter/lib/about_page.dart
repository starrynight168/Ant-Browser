import 'package:prism_ui/icons/icons.dart' as prism_icons;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

const _remoteAuthorUrl = '';
const _remoteAuthorTimeoutMs = 1000;
const _projectUrl = 'https://github.com/black-ant/Ant-Browser';
const _defaultAuthor = <String, dynamic>{
  'name': '志字辈小蚂蚁',
  'initial': '志',
  'title': '全栈开发工程师',
  'bio': '热爱开源，专注于 Web 和桌面应用开发。致力于打造优雅、高效的开发工具和框架。',
  'location': '中国',
  'joinDate': '2020',
  'email': 'contact@antblack.dev',
  'website': 'http://blog.antblack.cn',
  'github': 'https://github.com/black-ant',
  'skills': ['Go', 'React', 'TypeScript', 'Wails', 'Node.js', 'Docker'],
  'channels': [
    {
      'name': '掘金',
      'description': '技术文章与开发记录',
      'detail': 'juejin.cn',
      'href': 'https://juejin.cn/user/3790771822007822',
      'icon': 'book-open',
    },
    {
      'name': '个人博客',
      'description': '独立站文章与项目归档',
      'detail': 'blog.antblack.cn',
      'href': 'http://blog.antblack.cn',
      'icon': 'globe',
    },
    {
      'name': '公众号',
      'description': '微信搜索后即可关注',
      'detail': '整理中',
      'icon': 'message-square',
    },
  ],
};
const _projectProfile = <String, dynamic>{
  'name': 'Ant Browser',
  'introBadge': 'Ant Browser',
  'introText': '是一个面向多账号隔离、代理绑定和本地环境管理的桌面浏览器工具。',
  'techStack': ['Flutter', 'Dart', 'Go', 'Prism UI'],
  'description':
      '项目聚焦浏览器实例隔离、代理池配置、浏览器内核管理、标签检索和快捷启动，适用于跨境电商、社媒运营、本地测试和统一管理浏览器环境。',
  'actions': [
    {'label': '查看源码', 'href': _projectUrl, 'icon': 'github'},
    {
      'label': '下载发布版',
      'href': 'https://github.com/black-ant/Ant-Browser/releases',
      'icon': 'globe',
    },
  ],
};

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '读取中';
  bool _checking = false;
  bool _loadingProfile = true;
  String? _profileLoadError;
  late Map<String, dynamic> _author;
  final Map<String, dynamic> _project = Map<String, dynamic>.from(
    _projectProfile,
  );
  Map<String, dynamic>? _updateResult;

  @override
  void initState() {
    super.initState();
    _author = Map<String, dynamic>.from(_defaultAuthor);
    _loadVersion();
    _loadAuthor();
  }

  Future<void> _loadAuthor() async {
    if (_remoteAuthorUrl.trim().isEmpty) {
      if (mounted) setState(() => _loadingProfile = false);
      return;
    }
    try {
      final payload = await AppBridge.call('FetchRemoteAuthorProfile', [
        _remoteAuthorUrl,
        _remoteAuthorTimeoutMs,
      ]);
      if (mounted) setState(() => _author = _normalizeAuthor(payload));
    } catch (error) {
      if (mounted) {
        setState(() {
          _author = Map<String, dynamic>.from(_defaultAuthor);
          _profileLoadError = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
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
      final result = await AppBridge.call('CheckForUpdates');
      if (mounted) {
        setState(
          () => _updateResult = result is Map
              ? Map<String, dynamic>.from(result)
              : null,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _updateResult = {'error': error.toString()});
    } finally {
      if (mounted) setState(() => _checking = false);
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
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 560
                  ? 1
                  : constraints.maxWidth < 850
                  ? 2
                  : 3;
              final cardWidth = columns == 1
                  ? constraints.maxWidth
                  : ((constraints.maxWidth - 12 * (columns - 1)) / columns)
                        .floorToDouble();
              return Wrap(
                spacing: 12,
                runSpacing: 12,
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
          const SizedBox(height: 12),
          _skillsCard(staggerIndex: 1 + channels.length),
          const SizedBox(height: 12),
          _projectCard(staggerIndex: 2 + channels.length),
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
                      (_author['initial'] ?? (name.isEmpty ? '志' : name[0]))
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
                    const SizedBox(height: 4),
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
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
          if (_loadingProfile || _profileLoadError != null) ...[
            const SizedBox(height: 10),
            Text(
              _loadingProfile ? '正在加载作者资料…' : '远程作者资料加载失败，当前显示默认资料。',
              style: prism.AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (github.isNotEmpty)
                prism.OutlinedButton.icon(
                  onPressed: () => AppBridge.openExternal(github),
                  icon: const PrismGlyph(AntGlyphs.code, size: 17),
                  label: const Text('GitHub'),
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
            const SizedBox(width: 12),
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
                  if ((channel['description'] ?? '').toString().isNotEmpty)
                    Text(
                      channel['description'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
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

  Widget _skillsCard({required int staggerIndex}) {
    return PrismSectionCard(
      title: '技术栈与技能',
      glyph: AntGlyphs.sparkles,
      padding: const EdgeInsets.all(20),
      staggerIndex: staggerIndex,
      staggerDelay: const Duration(milliseconds: 45),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final skill in (_author['skills'] as List? ?? []).map(
            (item) => item.toString(),
          ))
            _SkillChip(label: skill),
        ],
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
    final projectName = (_project['name'] ?? 'Ant Browser').toString();
    final introBadge = (_project['introBadge'] ?? projectName).toString();
    final releaseUrl = '${result?['releaseUrl'] ?? ''}'.trim();
    final canOpenDownload =
        result != null &&
        result['ok'] == true &&
        result['updateAvailable'] == true &&
        releaseUrl.isNotEmpty;
    final hasError = result?['error']?.toString().isNotEmpty == true;
    final updateAvailable = result?['updateAvailable'] == true;
    final updateText = result == null
        ? ''
        : updateAvailable
        ? '发现新版本 ${result['latestVersion'] ?? ''}'
        : hasError
        ? result['error'].toString()
        : '当前已是最新版本';

    return PrismSectionCard(
      title: '项目介绍',
      glyph: AntGlyphs.browser,
      padding: const EdgeInsets.all(22),
      staggerIndex: staggerIndex,
      staggerDelay: const Duration(milliseconds: 45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$introBadge ${_project['introText'] ?? ''}',
            style: prism.AppTextStyle.body
                .of(context)
                .copyWith(color: colors.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 18),
          Text(
            projectName,
            style: prism.AppTextStyle.title3.of(context, emphasized: true),
          ),
          const SizedBox(height: 8),
          Text(
            (_project['description'] ?? '').toString(),
            style: prism.AppTextStyle.body
                .of(context)
                .copyWith(color: colors.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in (_project['techStack'] as List? ?? []))
                _SkillChip(label: item.toString()),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
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
          const SizedBox(height: 14),
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
          if (updateText.isNotEmpty) ...[
            const SizedBox(height: 12),
            PrismBanner(
              tone: hasError
                  ? PrismTone.danger
                  : updateAvailable
                  ? PrismTone.info
                  : PrismTone.success,
              message: updateText,
              trailing: canOpenDownload
                  ? prism.OutlinedButton.icon(
                      onPressed: () => AppBridge.openExternal(releaseUrl),
                      icon: const PrismGlyph(AntGlyphs.openInNew, size: 15),
                      label: const Text('打开下载页面'),
                    )
                  : null,
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
