import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';

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
      if (mounted)
        setState(
          () =>
              _version = config is Map ? '${config['version'] ?? '未知'}' : '未知',
        );
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
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
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: columns == 1 ? 3.2 : 1.65,
                    children: [
                      for (final channel
                          in (_author['channels'] as List? ?? [])
                              .whereType<Map>())
                        _channelCard(Map<String, dynamic>.from(channel)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _skillsCard(),
              const SizedBox(height: 16),
              _projectCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _authorCard() {
    final colors = prism.Theme.of(context).colorScheme;
    final name = (_author['name'] ?? '').toString();
    final github = (_author['github'] ?? '').toString().trim();
    final website = (_author['website'] ?? '').toString().trim();
    final email = (_author['email'] ?? '').toString().trim();
    return _AboutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  (_author['initial'] ?? (name.isEmpty ? '志' : name[0]))
                      .toString(),
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
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
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      (_author['title'] ?? '').toString(),
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SizedBox(height: 16),
          Text(
            (_author['bio'] ?? '').toString(),
            style: TextStyle(height: 1.7, color: colors.onSurfaceVariant),
          ),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              if ((_author['location'] ?? '').toString().trim().isNotEmpty)
                _MetaLabel(
                  icon: Icons.place_outlined,
                  text: _author['location'].toString(),
                ),
              if ((_author['joinDate'] ?? '').toString().trim().isNotEmpty)
                _MetaLabel(
                  icon: Icons.calendar_month_outlined,
                  text: '加入于 ' + _author['joinDate'].toString(),
                ),
            ],
          ),
          if (_loadingProfile || _profileLoadError != null) ...[
            const SizedBox(height: 10),
            Text(
              _loadingProfile ? '正在加载作者资料…' : '远程作者资料加载失败，当前显示默认资料。',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (github.isNotEmpty)
                prism.OutlinedButton.icon(
                  onPressed: () => AppBridge.openExternal(github),
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('GitHub'),
                ),
              if (website.isNotEmpty)
                prism.OutlinedButton.icon(
                  onPressed: () => AppBridge.openExternal(website),
                  icon: const Icon(Icons.public, size: 18),
                  label: Text(_stripProtocol(website)),
                ),
              if (email.isNotEmpty)
                prism.OutlinedButton.icon(
                  onPressed: () => AppBridge.openExternal('mailto:' + email),
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text('联系作者'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _channelCard(Map<String, dynamic> channel) {
    final colors = prism.Theme.of(context).colorScheme;
    final href = (channel['href'] ?? '').toString().trim();
    final title = (channel['name'] ?? '').toString();
    final detail = (channel['detail'] ?? '').toString();
    return PrismCard(
      onPressed: href.isEmpty ? null : () => AppBridge.openExternal(href),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _profileIcon((channel['icon'] ?? '').toString(), title),
              size: 24,
              color: colors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((channel['description'] ?? '').toString().isNotEmpty)
                    Text(
                      channel['description'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (href.isNotEmpty)
              Icon(Icons.open_in_new, size: 16, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _skillsCard() {
    return _AboutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '技术栈与技能',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final skill in (_author['skills'] as List? ?? []).map(
                (item) => item.toString(),
              ))
                _SkillChip(label: skill),
            ],
          ),
        ],
      ),
    );
  }

  IconData _profileIcon(String icon, String label) {
    final key = '$icon $label'.toLowerCase();
    if (key.contains('github') || key.contains('code') || key.contains('源码')) {
      return Icons.code;
    }
    if (key.contains('book') || key.contains('juejin') || key.contains('文章')) {
      return Icons.auto_stories_outlined;
    }
    if (key.contains('message') ||
        key.contains('wechat') ||
        key.contains('公众号')) {
      return Icons.chat_bubble_outline;
    }
    if (key.contains('globe') || key.contains('web') || key.contains('博客')) {
      return Icons.public;
    }
    return Icons.link;
  }

  String _stripProtocol(String url) => url
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceFirst(RegExp(r'/$'), '');

  Widget _projectCard() {
    final colors = prism.Theme.of(context).colorScheme;
    final result = _updateResult;
    final projectName = (_project['name'] ?? 'Ant Browser').toString();
    final introBadge = (_project['introBadge'] ?? projectName).toString();
    final updateText = result == null
        ? ''
        : result['updateAvailable'] == true
        ? '发现新版本 ${result['latestVersion'] ?? ''}'
        : result['error']?.toString().isNotEmpty == true
        ? result['error'].toString()
        : '当前已是最新版本';
    return _AboutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '项目介绍',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '$introBadge ${_project['introText'] ?? ''}',
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 20),
          Text(
            projectName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            (_project['description'] ?? '').toString(),
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in (_project['techStack'] as List? ?? []))
                _SkillChip(label: item.toString()),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action
                  in (_project['actions'] as List? ?? []).whereType<Map>())
                prism.OutlinedButton.icon(
                  onPressed: (action['href'] ?? '').toString().trim().isEmpty
                      ? null
                      : () => AppBridge.openExternal(action['href'].toString()),
                  icon: Icon(
                    _profileIcon(
                      (action['icon'] ?? '').toString(),
                      (action['label'] ?? '').toString(),
                    ),
                    size: 18,
                  ),
                  label: Text((action['label'] ?? '').toString()),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const prism.Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前版本：$_version',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              PrismTonalButton(
                onPressed: _checking ? null : _checkUpdate,
                child: _checking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: PrismProgressIndicator(),
                      )
                    : const Text('检查更新'),
              ),
            ],
          ),
          if (updateText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              updateText,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
            if (result?['releaseUrl']?.toString().isNotEmpty == true)
              prism.TextButton.icon(
                onPressed: () =>
                    AppBridge.openExternal(result!['releaseUrl'].toString()),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开下载页面'),
              ),
          ],
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PrismCard(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: prism.Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(22), child: child),
    );
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
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
