import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'prism_components.dart';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as prism_icons;

import 'ant_prism_theme.dart';
import 'prism_localizations.dart';
import 'profile_tools_page.dart';
import 'about_page.dart';
import 'automation_pages.dart';
import 'backup_pages.dart';
import 'bookmarks_page.dart';
import 'cores_page.dart';
import 'close_dialog.dart';
import 'extensions_page.dart';
import 'logs_page.dart';
import 'misc_pages.dart';
import 'notification_store.dart';
import 'notifications_page.dart';
import 'proxy_pages.dart';
import 'tags_page.dart';
import 'settings_page.dart';
import 'theme_state.dart';
import 'wails_bridge.dart';

void main() {
  try {
    final settings = WailsBridge.readStorage('app_settings');
    if (settings.isNotEmpty) {
      final value = (jsonDecode(settings) as Map)['theme'];
      if (value is String) setAppThemeMode(value);
    }
  } catch (_) {}
  runApp(const AntBrowserApp());
}

class AntBrowserApp extends StatelessWidget {
  const AntBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, themeMode, child) {
        final prismThemeMode = switch (themeMode) {
          ThemeMode.system => prism.ThemeMode.system,
          ThemeMode.light => prism.ThemeMode.light,
          ThemeMode.dark => prism.ThemeMode.dark,
        };
        return prism.PrismApp(
          title: 'Ant Browser',
          debugShowCheckedModeBanner: false,
          themeMode: prismThemeMode,
          theme: buildAntPrismTheme(Brightness.light),
          darkTheme: buildAntPrismTheme(Brightness.dark),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [AntPrismLocalizationsDelegate()],
          home: MaterialApp(
            title: 'Ant Browser',
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const [AntPrismLocalizationsDelegate()],
            themeMode: themeMode,
            theme: _buildAppTheme(Brightness.light),
            darkTheme: _buildAppTheme(Brightness.dark),
            home: const AntBrowserShell(),
          ),
        );
      },
    );
  }
}

ThemeData _buildAppTheme(Brightness brightness) {
  return buildAntMaterialTheme(brightness);
}

class _NavItem {
  const _NavItem(this.title, this.path);

  final String title;
  final String path;
}

class _NavSection {
  const _NavSection(this.title, this.items);

  final String title;
  final List<_NavItem> items;
}

const _navSections = <_NavSection>[
  _NavSection('指纹浏览器', [
    _NavItem('实例列表', '/browser/list'),
    _NavItem('自动化脚本', '/browser/automation'),
    _NavItem('内核管理', '/browser/cores'),
    _NavItem('插件包管理', '/browser/extensions'),
    _NavItem('代理池配置', '/browser/proxy-pool'),
    _NavItem('代理虚拟分组', '/browser/proxy-virtual-groups'),
    _NavItem('默认书签', '/browser/bookmarks'),
    _NavItem('标签管理', '/browser/tags'),
  ]),
  _NavSection('系统维护', [
    _NavItem('系统设置', '/settings'),
    _NavItem('备份与恢复', '/system/backup'),
    _NavItem('文档中心', '/system/docs'),
    _NavItem('日志查看', '/browser/logs'),
    _NavItem('通知', '/notifications'),
  ]),
];

const _navGlyphs = <String, prism_icons.Glyph>{
  '/browser/list': prism_icons.Glyph([
    prism_icons.GlyphPath('M3 5H21V17H3Z M8 21H16 M12 17V21'),
  ]),
  '/browser/automation': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 3V6 M6 8H18V17H6Z M9 11H9.1 M15 11H15.1 M9 14H15 M4 10V15 M20 10V15',
    ),
  ]),
  '/browser/cores': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M6 6H18V18H6Z M9 9H15V15H9Z M2 8H6 M2 12H6 M2 16H6 M18 8H22 M18 12H22 M18 16H22 M8 2V6 M12 2V6 M16 2V6 M8 18V22 M12 18V22 M16 18V22',
    ),
  ]),
  '/browser/extensions': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M4 4H10V7A2 2 0 1 0 14 7V4H20V10H17A2 2 0 1 0 17 14H20V20H14V17A2 2 0 1 0 10 17V20H4V14H7A2 2 0 1 0 7 10H4Z',
    ),
  ]),
  '/browser/proxy-pool': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 2A10 10 0 1 0 12 22A10 10 0 1 0 12 2 M2 12H22 M12 2C7 7 7 17 12 22 M12 2C17 7 17 17 12 22',
    ),
  ]),
  '/browser/proxy-virtual-groups': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 12L6 6 M12 12L18 6 M12 12L6 18 M12 12L18 18 M4 4A2 2 0 1 0 4 8A2 2 0 1 0 4 4 M20 4A2 2 0 1 0 20 8A2 2 0 1 0 20 4 M4 16A2 2 0 1 0 4 20A2 2 0 1 0 4 16 M20 16A2 2 0 1 0 20 20A2 2 0 1 0 20 16 M10 10A3 3 0 1 0 14 14A3 3 0 1 0 10 10',
    ),
  ]),
  '/browser/bookmarks': prism_icons.Glyph([
    prism_icons.GlyphPath('M6 3H18V21L12 17L6 21Z'),
  ]),
  '/browser/tags': prism_icons.Glyph([
    prism_icons.GlyphPath('M3 12L11 4H20V13L12 21Z M15 8H15.1'),
  ]),
  '/settings': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 8A4 4 0 1 0 12 16A4 4 0 1 0 12 8 M12 2V5 M12 19V22 M2 12H5 M19 12H22 M5 5L7 7 M17 17L19 19 M19 5L17 7 M7 17L5 19',
    ),
  ]),
  '/system/backup': prism_icons.Glyph([
    prism_icons.GlyphPath('M4 4H20V8H4Z M3 9H21V20H3Z M9 13H15'),
  ]),
  '/system/docs': prism_icons.Glyph([
    prism_icons.GlyphPath('M5 3H19V21H5Z M8 7H16 M8 11H16 M8 15H13'),
  ]),
  '/browser/logs': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M6 3H15L19 7V21H6Z M15 3V7H19 M9 11H16 M9 15H16 M9 18H14',
    ),
  ]),
  '/notifications': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M18 10A6 6 0 0 0 6 10C6 17 3 17 3 19H21C21 17 18 17 18 10 M10 22H14',
    ),
  ]),
  '/profile': prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 12A4 4 0 1 0 12 4A4 4 0 1 0 12 12 M4 21C4 17 7 15 12 15C17 15 20 17 20 21',
    ),
  ]),
};

class AntBrowserShell extends StatefulWidget {
  const AntBrowserShell({super.key});

  @override
  State<AntBrowserShell> createState() => _AntBrowserShellState();
}

class _AntBrowserShellState extends State<AntBrowserShell> {
  String _activePath = '/browser/list';
  bool _compactSidebar = false;
  bool _closeDialogOpen = false;
  late final void Function() _removeCloseListener;
  late final NotificationStore _notificationStore;

  @override
  void initState() {
    super.initState();
    _notificationStore = NotificationStore()
      ..addListener(_refreshForNotifications);
    _removeCloseListener = WailsBridge.onEvent('app:request-close', (_) {
      _showCloseDialog();
    });
  }

  void _refreshForNotifications() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _removeCloseListener();
    _notificationStore
      ..removeListener(_refreshForNotifications)
      ..dispose();
    super.dispose();
  }

  String get _activeTitle {
    if (_activePath == '/browser/automation/new') return '新建脚本';
    if (_activePath.startsWith('/browser/automation/')) return '脚本详情';
    if (_activePath == '/system/backup/s3') return 'S3 备份设置';
    if (_activePath == '/system/backup/openlist') return 'OpenList 备份设置';
    if (_activePath == '/browser/proxy-align') return '代理订阅记录';
    if (_activePath.startsWith('/browser/detail/')) return '实例详情';
    if (_activePath.startsWith('/browser/edit/')) return '编辑实例';
    if (_activePath.startsWith('/browser/copy/')) return '复制实例';
    for (final section in _navSections) {
      for (final item in section.items) {
        if (item.path == _activePath) return item.title;
      }
    }
    return _activePath == '/profile' ? '关于我' : 'Ant Browser';
  }

  Future<void> _showCloseDialog() async {
    if (_closeDialogOpen || !mounted) return;
    _closeDialogOpen = true;
    String? action;
    try {
      final platform = await WailsBridge.platform();
      if (!mounted) return;
      action = await Navigator.of(context, rootNavigator: false).push<String>(
        PageRouteBuilder<String>(
          opaque: false,
          barrierDismissible: true,
          barrierColor: const Color(0x990A110E),
          barrierLabel: '关闭确认',
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (context, animation, secondaryAnimation) =>
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      Navigator.of(context).maybePop(),
                },
                child: Focus(
                  autofocus: true,
                  child: Center(
                    child: CloseDialog(
                      isWindows: platform.toLowerCase() == 'windows',
                    ),
                  ),
                ),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curve,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.965, end: 1).animate(curve),
                child: child,
              ),
            );
          },
        ),
      );
    } finally {
      _closeDialogOpen = false;
    }
    if (!mounted || action == null) return;
    if (action == 'minimize') {
      if ((await WailsBridge.platform()).toLowerCase() == 'windows') {
        WailsBridge.hideWindow();
      } else {
        WailsBridge.minimiseWindow();
      }
      return;
    }
    if (action == 'quit-app') {
      await WailsBridge.call('QuitAppOnly');
      return;
    }
    if (action == 'quit-all') {
      WailsBridge.hideWindow();
      try {
        await WailsBridge.call('ForceQuit');
      } catch (_) {
        WailsBridge.quit();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        color: colors.surfaceContainer,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            _Sidebar(
              activePath: _activePath,
              compact: _compactSidebar,
              unreadCount: _notificationStore.unreadCount,
              onSelect: (path) => setState(() => _activePath = path),
              onToggle: () =>
                  setState(() => _compactSidebar = !_compactSidebar),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: prism.Surface(
                  color: prism.ColorScheme.of(context).surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PageHeader(title: _activeTitle),
                      Expanded(
                        child: prism.PageTransitionSwitcher(
                          duration: const Duration(milliseconds: 240),
                          transitionBuilder:
                              (child, animation, secondaryAnimation) =>
                                  prism.FadeThroughTransition(
                                    animation: animation,
                                    secondaryAnimation: secondaryAnimation,
                                    child: child,
                                  ),
                          child: KeyedSubtree(
                            key: ValueKey(_activePath),
                            child:
                                _activePath == '/browser/list' ||
                                    _activePath == '/browser/monitor'
                                ? BrowserListPage(
                                    onOpenDetails: (id) => setState(
                                      () => _activePath = '/browser/detail/$id',
                                    ),
                                  )
                                : _activePath.startsWith('/browser/detail/')
                                ? BrowserProfileToolsPage(
                                    profileId: _activePath.split('/').last,
                                    onBack: () => setState(
                                      () => _activePath = '/browser/list',
                                    ),
                                  )
                                : _activePath.startsWith('/browser/edit/') ||
                                      _activePath.startsWith('/browser/copy/')
                                ? BrowserListPage(
                                    onOpenDetails: (id) => setState(
                                      () => _activePath = '/browser/detail/$id',
                                    ),
                                    initialQuery:
                                        _activePath.split('/').last == 'new'
                                        ? ''
                                        : _activePath.split('/').last,
                                  )
                                : _activePath == '/profile'
                                ? const AboutPage()
                                : _activePath == '/browser/logs'
                                ? const LogsPage()
                                : _activePath == '/browser/bookmarks'
                                ? const BookmarksPage()
                                : _activePath == '/notifications'
                                ? NotificationsPage(
                                    store: _notificationStore,
                                    onNavigate: (path) =>
                                        setState(() => _activePath = path),
                                  )
                                : _activePath == '/browser/tags'
                                ? const TagsPage()
                                : _activePath == '/settings'
                                ? const SettingsPage()
                                : _activePath == '/browser/cores'
                                ? const CoresPage()
                                : _activePath == '/browser/extensions'
                                ? const ExtensionsPage()
                                : _activePath == '/browser/proxy-pool'
                                ? ProxyPoolPage(
                                    onOpenGroups: () => setState(
                                      () => _activePath =
                                          '/browser/proxy-virtual-groups',
                                    ),
                                    onOpenAlign: () => setState(
                                      () =>
                                          _activePath = '/browser/proxy-align',
                                    ),
                                  )
                                : _activePath == '/browser/proxy-virtual-groups'
                                ? const ProxyGroupsPage()
                                : _activePath == '/browser/proxy-align'
                                ? ProxyAlignPage(
                                    onBack: () => setState(
                                      () => _activePath = '/browser/proxy-pool',
                                    ),
                                  )
                                : _activePath == '/browser/automation'
                                ? AutomationPage(
                                    onOpen: (id) => setState(
                                      () => _activePath =
                                          '/browser/automation/$id',
                                    ),
                                    onCreate: () => setState(
                                      () => _activePath =
                                          '/browser/automation/new',
                                    ),
                                  )
                                : _activePath.startsWith('/browser/automation/')
                                ? AutomationScriptDetailPage(
                                    scriptId: _activePath.split('/').last,
                                    onBack: () => setState(
                                      () => _activePath = '/browser/automation',
                                    ),
                                    onCreated: (id) => setState(
                                      () => _activePath =
                                          '/browser/automation/$id',
                                    ),
                                  )
                                : _activePath == '/system/backup'
                                ? BackupPage(
                                    onOpenS3: () => setState(
                                      () => _activePath = '/system/backup/s3',
                                    ),
                                    onOpenOpenList: () => setState(
                                      () => _activePath =
                                          '/system/backup/openlist',
                                    ),
                                  )
                                : _activePath == '/system/backup/s3'
                                ? S3ConfigPage(
                                    onBack: () => setState(
                                      () => _activePath = '/system/backup',
                                    ),
                                  )
                                : _activePath == '/system/backup/openlist'
                                ? OpenListConfigPage(
                                    onBack: () => setState(
                                      () => _activePath = '/system/backup',
                                    ),
                                  )
                                : _activePath == '/system/docs' ||
                                      _activePath == '/browser/launch-api' ||
                                      _activePath == '/system/tutorial'
                                ? const DocsPage()
                                : _activePath == '/charts'
                                ? const ChartsPage()
                                : const BrowserListPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.activePath,
    required this.compact,
    required this.unreadCount,
    required this.onSelect,
    required this.onToggle,
  });

  final String activePath;
  final bool compact;
  final int unreadCount;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final section in _navSections) ...section.items,
      const _NavItem('关于我', '/profile'),
    ];
    var selectedPath = activePath;
    if (selectedPath.startsWith('/browser/detail/') ||
        selectedPath.startsWith('/browser/edit/') ||
        selectedPath.startsWith('/browser/copy/') ||
        selectedPath == '/browser/monitor') {
      selectedPath = '/browser/list';
    } else if (selectedPath.startsWith('/browser/automation/')) {
      selectedPath = '/browser/automation';
    } else if (selectedPath == '/browser/proxy-align') {
      selectedPath = '/browser/proxy-pool';
    } else if (selectedPath.startsWith('/system/backup/')) {
      selectedPath = '/system/backup';
    } else if (selectedPath == '/browser/launch-api' ||
        selectedPath == '/system/tutorial') {
      selectedPath = '/system/docs';
    }
    final selectedIndex = items.indexWhere((item) => item.path == selectedPath);
    final color = prism.ColorScheme.of(context).surfaceContainerLow;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: prism.Surface(
        color: color,
        child: prism.NavigationSidebar(
          destinations: [
            for (final item in items)
              prism.SidebarDestination(
                glyph: _navGlyphs[item.path]!,
                label: item.path == '/notifications' && unreadCount > 0
                    ? '${item.title} (${unreadCount > 99 ? '99+' : unreadCount})'
                    : item.title,
              ),
          ],
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          expanded: !compact,
          onSelected: (index) => onSelect(items[index].path),
          onToggle: onToggle,
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: Text(
          title,
          key: ValueKey(title),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class BrowserListPage extends StatefulWidget {
  const BrowserListPage({
    super.key,
    this.initialQuery = '',
    this.onOpenDetails,
  });

  final String initialQuery;
  final ValueChanged<String>? onOpenDetails;

  @override
  State<BrowserListPage> createState() => _BrowserListPageState();
}

class _BrowserListPageState extends State<BrowserListPage> {
  final _searchController = TextEditingController();
  final Set<String> _selectedProfileIds = {};
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  String? _error;
  String? _busyProfile;
  String _query = '';
  String _statusFilter = 'all';
  String _tagFilter = '';
  String _coreFilter = '';
  String _proxyFilter = '';
  String _groupFilter = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _searchController.text = widget.initialQuery;
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await WailsBridge.call('BrowserProfileList');
      final rows = result is List ? result : const [];
      if (!mounted) return;
      setState(() {
        _profiles = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      });
      try {
        final groups = await WailsBridge.call('ListGroups');
        if (mounted) {
          setState(() {
            _groups = (groups as List? ?? [])
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList();
          });
        }
      } catch (_) {}
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleProfile(Map<String, dynamic> profile) async {
    final id = profile['profileId']?.toString() ?? '';
    if (id.isEmpty) return;
    final running = profile['running'] == true;
    setState(() => _busyProfile = id);
    try {
      if (!running) await _warmProfileProxy(profile);
      await WailsBridge.call(
        running ? 'BrowserInstanceStop' : 'BrowserInstanceStart',
        [id],
      );
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busyProfile = null);
    }
  }

  Future<void> _warmProfileProxy(Map<String, dynamic> profile) async {
    final proxyId = (profile['proxyId'] ?? '').toString();
    final proxyConfig = (profile['proxyConfig'] ?? '').toString();
    if (proxyId.isEmpty && proxyConfig.isEmpty) return;
    try {
      await WailsBridge.call('BrowserProxyWarmupBridgeWithConfig', [
        proxyId,
        proxyConfig,
      ]);
    } catch (_) {}
  }

  List<String> _withAdaptiveDefaultWindowSize(List<String> args) {
    final normalized = args
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (normalized.any(
      (item) => item.toLowerCase().startsWith('--window-size='),
    )) {
      return normalized;
    }
    final size = MediaQuery.maybeOf(context)?.size;
    final availableWidth = size?.width ?? 1920;
    final availableHeight = size?.height ?? 1080;
    final width = (availableWidth * 0.42).round().clamp(960, 1440).toInt();
    final maxHeight = (availableHeight * 0.82)
        .floor()
        .clamp(540, 100000)
        .toInt();
    final height = (width * 9 / 16).round().clamp(540, maxHeight).toInt();
    return [...normalized, '--window-size=$width,$height'];
  }

  Future<void> _restartProfile(Map<String, dynamic> profile) async {
    final id = profile['profileId']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _busyProfile = id);
    try {
      await WailsBridge.call('BrowserInstanceRestart', [id]);
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重启失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busyProfile = null);
    }
  }

  Future<void> _manageGroups() async {
    final name = TextEditingController();
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('实例分组'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: '新分组名称'),
                      ),
                    ),
                    IconButton(
                      tooltip: '新建分组',
                      onPressed: () async {
                        if (name.text.trim().isEmpty) return;
                        await WailsBridge.call('CreateGroup', [
                          {
                            'groupName': name.text.trim(),
                            'parentId': '',
                            'sortOrder': _groups.length,
                          },
                        ]);
                        name.clear();
                        final groups = await WailsBridge.call('ListGroups');
                        _groups = (groups as List? ?? [])
                            .whereType<Map>()
                            .map((row) => Map<String, dynamic>.from(row))
                            .toList();
                        setDialog(() {});
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final group in _groups)
                        ListTile(
                          title: Text((group['groupName'] ?? '').toString()),
                          subtitle: Text('${group['instanceCount'] ?? 0} 个实例'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              final groupId = (group['groupId'] ?? '')
                                  .toString();
                              if (action == 'rename') {
                                name.text = (group['groupName'] ?? '')
                                    .toString();
                                final next = await showDialog<String>(
                                  context: context,
                                  useRootNavigator: false,
                                  builder: (context) => AlertDialog(
                                    title: const Text('重命名分组'),
                                    content: TextField(controller: name),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(
                                          context,
                                          name.text.trim(),
                                        ),
                                        child: const Text('保存'),
                                      ),
                                    ],
                                  ),
                                );
                                if (next != null && next.isNotEmpty) {
                                  await WailsBridge.call('UpdateGroup', [
                                    groupId,
                                    {
                                      'groupName': next,
                                      'parentId': group['parentId'] ?? '',
                                      'sortOrder': group['sortOrder'] ?? 0,
                                    },
                                  ]);
                                }
                              } else {
                                final yes = await showDialog<bool>(
                                  context: context,
                                  useRootNavigator: false,
                                  builder: (context) => AlertDialog(
                                    title: const Text('删除分组？'),
                                    content: const Text('分组内的实例会变为未分组。'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (yes == true)
                                  await WailsBridge.call('DeleteGroup', [
                                    groupId,
                                  ]);
                              }
                              final groups = await WailsBridge.call(
                                'ListGroups',
                              );
                              _groups = (groups as List? ?? [])
                                  .whereType<Map>()
                                  .map((row) => Map<String, dynamic>.from(row))
                                  .toList();
                              await _reload();
                              setDialog(() {});
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('重命名'),
                              ),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    await _reload();
  }

  Future<void> _editProfile([Map<String, dynamic>? profile]) async {
    final name = TextEditingController(
      text: (profile?['profileName'] ?? '').toString(),
    );
    final tags = TextEditingController(
      text: (profile?['tags'] as List? ?? []).join(', '),
    );
    final keywords = TextEditingController(
      text: (profile?['keywords'] as List? ?? []).join(', '),
    );
    final userDataDir = TextEditingController(
      text: (profile?['userDataDir'] ?? '').toString(),
    );
    final memoryLimit = TextEditingController(
      text: (profile?['memoryLimitMb'] ?? 0).toString(),
    );
    final fingerprintArgs = TextEditingController(
      text: (profile?['fingerprintArgs'] as List? ?? []).join('\n'),
    );
    final launchArgs = TextEditingController(
      text: (profile?['launchArgs'] as List? ?? []).join('\n'),
    );
    final localProxyConfig = TextEditingController(
      text: (profile?['proxyConfig'] ?? '').toString(),
    );
    final proxyGroupName = TextEditingController(
      text: (profile?['proxyGroupName'] ?? '').toString(),
    );
    List<Map<String, dynamic>> cores = [];
    List<Map<String, dynamic>> proxies = [];
    List<Map<String, dynamic>> virtualGroups = [];
    try {
      final result = await Future.wait([
        WailsBridge.call('BrowserCoreList'),
        WailsBridge.call('BrowserProxyList'),
        WailsBridge.call('BrowserProxyVirtualGroupList'),
        WailsBridge.call('GetBrowserSettings'),
      ]);
      cores = (result[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      proxies = (result[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      virtualGroups = (result[2] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (profile == null && result[3] is Map) {
        final settings = Map<String, dynamic>.from(result[3] as Map);
        fingerprintArgs.text = _withAdaptiveDefaultWindowSize(
          (settings['defaultFingerprintArgs'] as List? ?? [])
              .map((item) => item.toString())
              .toList(),
        ).join('\n');
        launchArgs.text = (settings['defaultLaunchArgs'] as List? ?? [])
            .map((item) => item.toString())
            .join('\n');
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      name.dispose();
      tags.dispose();
      keywords.dispose();
      userDataDir.dispose();
      memoryLimit.dispose();
      fingerprintArgs.dispose();
      launchArgs.dispose();
      localProxyConfig.dispose();
      proxyGroupName.dispose();
      return;
    }
    String? coreId = (profile?['coreId'] ?? '').toString();
    if (!cores.any((core) => core['coreId'] == coreId)) {
      final defaultCore = cores.where((core) => core['isDefault'] == true);
      coreId = defaultCore.isNotEmpty
          ? defaultCore.first['coreId']?.toString()
          : cores.isNotEmpty
          ? cores.first['coreId']?.toString()
          : null;
    }
    final directProxy = proxies.where(
      (proxy) => proxy['proxyConfig'] == 'direct://',
    );
    String? proxyId =
        (profile?['proxyId'] ??
                (directProxy.isNotEmpty ? directProxy.first['proxyId'] : ''))
            .toString();
    String restoreMode = (profile?['restoreLastSession'] ?? '').toString();
    final proxyModeValue = (profile?['proxyMode'] ?? 'fixed').toString();
    var proxyMode = proxyModeValue.isEmpty ? 'fixed' : proxyModeValue;
    var groupId = (profile?['groupId'] ?? '').toString();
    var resolvingLocation = false;
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(profile == null ? '新建浏览器实例' : '编辑实例'),
          content: SizedBox(
            width: 500,
            height: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '实例名称'),
                ),
                TextField(
                  controller: userDataDir,
                  decoration: const InputDecoration(
                    labelText: '用户数据目录（留空自动生成）',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: coreId,
                  decoration: const InputDecoration(labelText: '浏览器内核'),
                  items: [
                    for (final core in cores)
                      DropdownMenuItem(
                        value: core['coreId']?.toString(),
                        child: Text(
                          (core['coreName'] ?? core['coreId'] ?? '').toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialog(() => coreId = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue:
                      _groups.any((group) => group['groupId'] == groupId)
                      ? groupId
                      : '',
                  decoration: const InputDecoration(labelText: '实例分组'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('未分组')),
                    for (final group in _groups)
                      DropdownMenuItem(
                        value: group['groupId']?.toString(),
                        child: Text((group['groupName'] ?? '').toString()),
                      ),
                  ],
                  onChanged: (value) => setDialog(() => groupId = value ?? ''),
                ),
                DropdownButtonFormField<String>(
                  initialValue:
                      ['fixed', 'dynamic', 'local'].contains(proxyMode)
                      ? proxyMode
                      : 'fixed',
                  decoration: const InputDecoration(labelText: '代理模式'),
                  items: const [
                    DropdownMenuItem(value: 'fixed', child: Text('固定代理')),
                    DropdownMenuItem(value: 'dynamic', child: Text('动态代理')),
                    DropdownMenuItem(value: 'local', child: Text('本地代理配置')),
                  ],
                  onChanged: (value) =>
                      setDialog(() => proxyMode = value ?? 'fixed'),
                ),
                if (proxyMode == 'fixed')
                  DropdownButtonFormField<String>(
                    initialValue:
                        proxies.any((proxy) => proxy['proxyId'] == proxyId)
                        ? proxyId
                        : null,
                    decoration: const InputDecoration(labelText: '代理'),
                    items: [
                      for (final proxy in proxies)
                        DropdownMenuItem(
                          value: proxy['proxyId']?.toString(),
                          child: Text(
                            (proxy['proxyName'] ?? proxy['proxyId'] ?? '')
                                .toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setDialog(() => proxyId = value),
                  ),
                if (proxyMode == 'dynamic') ...[
                  DropdownButtonFormField<String>(
                    initialValue:
                        [
                          ...proxies.map(
                            (proxy) => (proxy['groupName'] ?? '').toString(),
                          ),
                          ...virtualGroups.map(
                            (group) => (group['groupName'] ?? '').toString(),
                          ),
                        ].contains(proxyGroupName.text)
                        ? proxyGroupName.text
                        : null,
                    decoration: const InputDecoration(labelText: '动态代理分组'),
                    items:
                        {
                              ...proxies.map(
                                (proxy) =>
                                    (proxy['groupName'] ?? '').toString(),
                              ),
                              ...virtualGroups.map(
                                (group) =>
                                    (group['groupName'] ?? '').toString(),
                              ),
                              if (proxyGroupName.text.trim().isNotEmpty)
                                proxyGroupName.text.trim(),
                            }
                            .where((name) => name.trim().isNotEmpty)
                            .map(
                              (name) => DropdownMenuItem(
                                value: name,
                                child: Text(name),
                              ),
                            )
                            .toList(),
                    onChanged: (value) => proxyGroupName.text = value ?? '',
                  ),
                ],
                if (proxyMode == 'local')
                  TextField(
                    controller: localProxyConfig,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '本地代理配置',
                      hintText: '例如 http://127.0.0.1:7890',
                      alignLabelWithHint: true,
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: restoreMode.isEmpty ? '' : restoreMode,
                  decoration: const InputDecoration(labelText: '恢复上次浏览器会话'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('使用系统默认')),
                    DropdownMenuItem(value: 'enabled', child: Text('开启')),
                    DropdownMenuItem(value: 'disabled', child: Text('关闭')),
                  ],
                  onChanged: (value) =>
                      setDialog(() => restoreMode = value ?? ''),
                ),
                TextField(
                  controller: memoryLimit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '内存上限（MB，0 表示默认）',
                  ),
                ),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
                ),
                TextField(
                  controller: keywords,
                  decoration: const InputDecoration(labelText: '搜索关键词（逗号分隔）'),
                ),
                TextField(
                  controller: fingerprintArgs,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '指纹启动参数（每行一项）'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        resolvingLocation ||
                            proxyMode != 'fixed' ||
                            proxyId == null
                        ? null
                        : () async {
                            setDialog(() => resolvingLocation = true);
                            try {
                              final value = await WailsBridge.call(
                                'BrowserProxyResolveLocation',
                                [proxyId],
                              );
                              if (value is Map && value['ok'] == true) {
                                final args = fingerprintArgs.text
                                    .split('\n')
                                    .map((item) => item.trim())
                                    .where((item) => item.isNotEmpty)
                                    .toList();
                                fingerprintArgs.text =
                                    _applyLocaleToFingerprintArgs(
                                      args,
                                      (value['lang'] ?? '').toString(),
                                      (value['timezone'] ?? '').toString(),
                                    ).join('\n');
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '已应用 ${value['lang'] ?? ''} / ${value['timezone'] ?? ''}（${[value['country'], value['region'], value['city']].where((item) => item != null && item.toString().isNotEmpty).join(' / ')}）',
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                throw StateError(
                                  value is Map
                                      ? (value['error'] ?? '未匹配到代理定位')
                                            .toString()
                                      : '未匹配到代理定位',
                                );
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                setDialog(() => resolvingLocation = false);
                              }
                            }
                          },
                    icon: resolvingLocation
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.location_searching),
                    label: const Text('按代理出口设置语言和时区'),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showJsonResult(
                        '指纹版本适配矩阵',
                        WailsBridge.call('BrowserProfileFingerprintMatrix', [
                          profile?['profileId'] ?? '',
                          coreId ?? '',
                          fingerprintArgs.text
                              .split('\n')
                              .map((value) => value.trim())
                              .where((value) => value.isNotEmpty)
                              .toList(),
                        ]),
                      ),
                      icon: const Icon(Icons.grid_view_outlined),
                      label: const Text('查看适配矩阵'),
                    ),
                    if (profile != null) ...[
                      TextButton.icon(
                        onPressed: () => _showJsonResult(
                          '指纹自测结果',
                          WailsBridge.call('BrowserProfileFingerprintCheck', [
                            profile['profileId'],
                          ]),
                        ),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('运行指纹自测'),
                      ),
                      TextButton.icon(
                        onPressed: () => _showJsonResult(
                          '指纹检测页面',
                          WailsBridge.call(
                            'BrowserInstanceOpenFingerprintCheck',
                            [profile['profileId']],
                          ),
                        ),
                        icon: const Icon(Icons.open_in_browser_outlined),
                        label: const Text('在浏览器打开检测页'),
                      ),
                    ],
                  ],
                ),
                TextField(
                  controller: launchArgs,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '浏览器启动参数（每行一项）'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      setState(() => _busyProfile = profile?['profileId']?.toString() ?? 'new');
      try {
        final selectedProxy = proxies.where(
          (proxy) => proxy['proxyId'] == proxyId,
        );
        final fixedProxyId = selectedProxy.isNotEmpty
            ? selectedProxy.first['proxyId']
            : (profile?['proxyId'] ?? '');
        final fixedProxyConfig = selectedProxy.isNotEmpty
            ? selectedProxy.first['proxyConfig']
            : (profile?['proxyConfig'] ?? 'direct://');
        final tagsToList = (String value) => value
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final linesToList = (String value) => value
            .split('\n')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final input = <String, dynamic>{
          'profileName': name.text.trim(),
          'userDataDir': userDataDir.text.trim(),
          'coreId': coreId ?? '',
          'restoreLastSession': restoreMode,
          'fingerprintArgs': linesToList(fingerprintArgs.text),
          'proxyMode': proxyMode,
          'proxyId': proxyMode == 'fixed' ? fixedProxyId : '',
          'proxyConfig': proxyMode == 'local'
              ? localProxyConfig.text.trim()
              : proxyMode == 'fixed'
              ? fixedProxyConfig
              : '',
          'proxyGroupName': proxyMode == 'dynamic'
              ? proxyGroupName.text.trim()
              : '',
          'memoryLimitMb': int.tryParse(memoryLimit.text) ?? 0,
          'launchArgs': linesToList(launchArgs.text),
          'tags': tagsToList(tags.text),
          'keywords': tagsToList(keywords.text),
          'groupId': groupId,
        };
        if (proxyMode == 'dynamic' && proxyGroupName.text.trim().isEmpty) {
          throw StateError('请选择动态代理分组');
        }
        if (proxyMode == 'local' && localProxyConfig.text.trim().isEmpty) {
          throw StateError('请填写本地代理配置');
        }
        if (proxyMode == 'fixed' || proxyMode == 'local') {
          final config = proxyMode == 'local'
              ? localProxyConfig.text.trim()
              : fixedProxyConfig.toString();
          final proxyIdToValidate = proxyMode == 'fixed'
              ? fixedProxyId.toString()
              : '';
          final validation = await WailsBridge.call('ValidateProxyConfig', [
            config,
            proxyIdToValidate,
          ]);
          if (validation is Map && validation['supported'] == false) {
            throw StateError((validation['errorMsg'] ?? '代理配置无效').toString());
          }
        }
        await WailsBridge.call(
          profile == null ? 'BrowserProfileCreate' : 'BrowserProfileUpdate',
          profile == null ? [input] : [profile['profileId'], input],
        );
        await _reload();
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      } finally {
        if (mounted) setState(() => _busyProfile = null);
      }
    }
    name.dispose();
    tags.dispose();
    keywords.dispose();
    userDataDir.dispose();
    memoryLimit.dispose();
    fingerprintArgs.dispose();
    launchArgs.dispose();
    localProxyConfig.dispose();
    proxyGroupName.dispose();
  }

  Future<void> _showJsonResult(String title, Future<dynamic> request) async {
    try {
      final value = await request;
      final text = const JsonEncoder.withIndent('  ').convert(value);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 680,
            height: 520,
            child: SingleChildScrollView(child: SelectableText(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  List<String> _applyLocaleToFingerprintArgs(
    List<String> args,
    String lang,
    String timezone,
  ) {
    final next = [...args];
    void upsert(String name, String value) {
      if (value.trim().isEmpty) return;
      final prefix = '$name=';
      final index = next.indexWhere(
        (item) => item.toLowerCase().startsWith(prefix.toLowerCase()),
      );
      final argument = '$prefix${value.trim()}';
      if (index < 0) {
        next.add(argument);
      } else {
        next[index] = argument;
      }
    }

    final normalizedLang = lang.trim();
    upsert('--lang', normalizedLang);
    final languageBase = normalizedLang.split(RegExp('[-_]')).first;
    upsert(
      '--accept-lang',
      normalizedLang.isEmpty || languageBase == normalizedLang
          ? normalizedLang
          : '$normalizedLang,$languageBase',
    );
    upsert('--timezone', timezone);
    return next;
  }

  Future<void> _copyProfile(Map<String, dynamic> profile) async {
    final controller = TextEditingController(
      text: '${profile['profileName'] ?? '实例'} - 副本',
    );
    var mode = 'auto_fingerprint';
    final targets = <String>{'seed'};
    const targetLabels = <String, String>{
      'seed': '指纹种子',
      'identity': '浏览器身份',
      'locale': '语言与时区',
      'screen': '窗口大小',
      'hardware': '硬件参数',
      'network': '网络与伪装',
    };
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('复制实例配置'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '新实例名称'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: '复制方式'),
                  items: const [
                    DropdownMenuItem(value: 'regular', child: Text('直接复制')),
                    DropdownMenuItem(
                      value: 'auto_fingerprint',
                      child: Text('自动化指纹'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialog(() => mode = value ?? 'regular'),
                ),
                if (mode == 'auto_fingerprint') ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('选择自动处理的指纹项目'),
                    ),
                  ),
                  for (final entry in targetLabels.entries)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      value: targets.contains(entry.key),
                      onChanged: (selected) => setDialog(() {
                        if (selected == true) {
                          targets.add(entry.key);
                        } else {
                          targets.remove(entry.key);
                        }
                      }),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: mode == 'auto_fingerprint' && targets.isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                      'mode': mode,
                      'automationTargets': targets.toList(),
                    }),
              child: const Text('生成配置'),
            ),
          ],
        ),
      ),
    );
    if (result != null && controller.text.trim().isNotEmpty) {
      try {
        await WailsBridge.call('BrowserProfileCopyWithOptions', [
          profile['profileId'],
          controller.text.trim(),
          result,
        ]);
        await _reload();
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
    controller.dispose();
  }

  Future<void> _editLaunchCode(Map<String, dynamic> profile) async {
    final id = (profile['profileId'] ?? '').toString();
    if (id.isEmpty) return;
    final code = TextEditingController(
      text: (profile['launchCode'] ?? '').toString(),
    );
    try {
      final value = await WailsBridge.call('BrowserProfileGetCode', [id]);
      if (value is String && value.isNotEmpty) code.text = value;
    } catch (_) {}
    final nextCode = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('管理启动码'),
          content: TextField(
            controller: code,
            decoration: const InputDecoration(
              labelText: '启动码',
              helperText: '启动码用于通过接口查找并启动此实例。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  final value = await WailsBridge.call(
                    'BrowserProfileRegenerateCode',
                    [id],
                  );
                  setDialog(() => code.text = (value ?? '').toString());
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }
              },
              child: const Text('重新生成'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, code.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (nextCode == null) {
      code.dispose();
      return;
    }
    try {
      await WailsBridge.call('BrowserProfileSetCode', [id, nextCode]);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('启动码已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      code.dispose();
    }
  }

  Future<void> _deleteProfile(Map<String, dynamic> profile) async {
    final yes = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('移入回收站？'),
        content: Text((profile['profileName'] ?? '').toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await WailsBridge.call('BrowserProfileDelete', [profile['profileId']]);
        await _reload();
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _importProfiles() async {
    try {
      final previewResult = await WailsBridge.call(
        'BrowserProfilePackagePrepareImport',
      );
      if (previewResult is! Map) return;
      final preview = Map<String, dynamic>.from(previewResult);
      if (preview['cancelled'] == true) return;
      final profiles = (preview['profiles'] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final actions = profiles
          .map(
            (profile) => <String, dynamic>{
              'sourceProfileId': profile['sourceProfileId'],
              'sourceIndex': profile['sourceIndex'] ?? 0,
              'mode': profile['suggestedAction'] ?? 'new',
              'profileName':
                  profile['suggestedProfileName'] ??
                  profile['sourceProfileName'] ??
                  '',
            },
          )
          .toList();
      final confirmedActions = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text('导入 ${preview['profileCount'] ?? profiles.length} 个实例'),
            content: SizedBox(
              width: 620,
              height: 460,
              child: profiles.isEmpty
                  ? const Center(child: Text('压缩包里没有实例'))
                  : ListView.separated(
                      itemCount: profiles.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
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
                                (profile['sourceProfileName'] ?? '未命名实例')
                                    .toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if ((profile['targetProfileName'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text('匹配到本机实例：${profile['targetProfileName']}'),
                              DropdownButton<String>(
                                value: choices.contains(action['mode'])
                                    ? action['mode'] as String
                                    : 'new',
                                items: [
                                  const DropdownMenuItem(
                                    value: 'new',
                                    child: Text('新建为一个实例'),
                                  ),
                                  if (canOverwrite)
                                    const DropdownMenuItem(
                                      value: 'overwrite',
                                      child: Text('覆盖匹配到的实例'),
                                    ),
                                  const DropdownMenuItem(
                                    value: 'rename',
                                    child: Text('重命名后导入'),
                                  ),
                                ],
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
                                TextFormField(
                                  key: ValueKey('rename-$index'),
                                  initialValue: (action['profileName'] ?? '')
                                      .toString(),
                                  decoration: const InputDecoration(
                                    labelText: '导入后的名称',
                                  ),
                                  onChanged: (value) =>
                                      action['profileName'] = value,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, actions),
                child: const Text('继续'),
              ),
            ],
          ),
        ),
      );
      if (confirmedActions == null) return;
      if (confirmedActions.any(
        (action) =>
            action['mode'] == 'rename' &&
            (action['profileName'] ?? '').toString().trim().isEmpty,
      )) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('请填写重命名后的实例名称')));
        }
        return;
      }
      var password = '';
      if (preview['portableSessionAvailable'] == true) {
        final value = await _askPortableSessionPassword();
        if (value == null) return;
        password = value;
      }
      final result = await WailsBridge.call(
        'BrowserProfilePackageImportWithOptions',
        [
          preview['zipPath'],
          {
            'conflictMode': 'new',
            'confirmConflict': true,
            'actions': confirmedActions,
            'portableSessionPassword': password,
          },
        ],
      );
      final imported = result is Map ? Map<String, dynamic>.from(result) : {};
      if (imported['cancelled'] == true) return;
      await _reload();
      if (mounted) {
        final message =
            imported['message'] ?? '已导入 ${imported['importedCount'] ?? 0} 个实例';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message.toString())));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<String?> _askPortableSessionPassword() async {
    final password = TextEditingController();
    var errorText = '';
    final value = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('迁移登录态'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('输入导出时设置的密码；留空可跳过登录态迁移。'),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '迁移密码（至少 8 个字符）',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('跳过'),
            ),
            FilledButton(
              onPressed: () {
                if (password.text.isNotEmpty &&
                    password.text.runes.length < 8) {
                  setDialog(() => errorText = '密码至少需要 8 个字符');
                  return;
                }
                Navigator.pop(context, password.text);
              },
              child: const Text('继续'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    return value;
  }

  Future<void> _exportProfiles([List<String>? requestedIds]) async {
    final ids =
        requestedIds ??
        _profiles
            .map((item) => item['profileId']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
    if (ids.isEmpty) return;
    final running = _profiles
        .where((profile) => ids.contains(profile['profileId']))
        .where((profile) => profile['running'] == true)
        .map((profile) => (profile['profileName'] ?? '').toString())
        .toList();
    if (running.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先关闭运行中的实例再导出：${running.take(3).join('、')}')),
      );
      return;
    }
    final password = TextEditingController();
    var passwordError = '';
    final exportPassword = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('导出实例'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('可设置密码，一并迁移实例的登录态 Cookie。'),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '登录态迁移密码（至少 8 个字符）',
                  errorText: passwordError.isEmpty ? null : passwordError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('仅导出配置'),
            ),
            FilledButton(
              onPressed: () {
                if (password.text.runes.length < 8) {
                  setDialog(() => passwordError = '密码至少需要 8 个字符');
                  return;
                }
                Navigator.pop(context, password.text);
              },
              child: const Text('导出并迁移登录态'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    if (exportPassword == null) return;
    try {
      final result = await WailsBridge.call(
        'BrowserProfilePackageExportWithOptions',
        [
          ids,
          {'portableSessionPassword': exportPassword},
        ],
      );
      final value = Map<String, dynamic>.from(result as Map);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (value['portableSessionWarning'] ?? value['message'] ?? '实例导出已完成')
                  .toString(),
            ),
          ),
        );
      if (mounted) setState(() => _selectedProfileIds.clear());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _batchDeleteProfiles() async {
    final ids = _selectedProfileIds.toList();
    if (ids.isEmpty) return;
    final running = _profiles.any(
      (profile) =>
          ids.contains(profile['profileId']) && profile['running'] == true,
    );
    if (running) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先关闭运行中的实例再删除')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('批量移入回收站？'),
        content: Text('将移入 ${ids.length} 个实例。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final id in ids) {
        await WailsBridge.call('BrowserProfileDelete', [id]);
      }
      setState(() => _selectedProfileIds.clear());
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _batchToggleProfiles(bool start) async {
    final rows = _profiles.where(
      (profile) =>
          _selectedProfileIds.contains(profile['profileId']) &&
          (profile['running'] == true) != start,
    );
    if (rows.isEmpty) return;
    setState(() => _busyProfile = '__batch__');
    try {
      for (final profile in rows) {
        final id = (profile['profileId'] ?? '').toString();
        if (start) await _warmProfileProxy(profile);
        await WailsBridge.call(
          start ? 'BrowserInstanceStart' : 'BrowserInstanceStop',
          [id],
        );
      }
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busyProfile = null);
    }
  }

  Future<void> _showTrash() async {
    List<Map<String, dynamic>> rows = [];
    try {
      final result = await WailsBridge.call('BrowserProfileTrashList');
      rows = (result as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('实例回收站'),
          content: SizedBox(
            width: 560,
            height: 420,
            child: rows.isEmpty
                ? const Center(child: Text('回收站是空的'))
                : ListView(
                    children: [
                      for (final row in rows)
                        PrismListTile(
                          title: Text(
                            (row['profileName'] ?? '未命名实例').toString(),
                          ),
                          subtitle: Text((row['deletedAt'] ?? '').toString()),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: '恢复',
                                onPressed: () async {
                                  try {
                                    await WailsBridge.call(
                                      'BrowserProfileRestore',
                                      [row['profileId']],
                                    );
                                    rows.remove(row);
                                    setDialog(() {});
                                    await _reload();
                                  } catch (error) {
                                    if (mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
                                          );
                                  }
                                },
                                icon: const Icon(Icons.restore),
                              ),
                              IconButton(
                                tooltip: '彻底删除',
                                onPressed: () async {
                                  final yes = await showDialog<bool>(
                                    context: context,
                                    useRootNavigator: false,
                                    builder: (context) => AlertDialog(
                                      title: const Text('彻底删除实例？'),
                                      content: const Text('此操作无法撤销。'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (yes != true) return;
                                  try {
                                    await WailsBridge.call(
                                      'BrowserProfilePermanentlyDelete',
                                      [row['profileId']],
                                    );
                                    rows.remove(row);
                                    setDialog(() {});
                                  } catch (error) {
                                    if (mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
                                          );
                                  }
                                },
                                icon: const Icon(Icons.delete_forever_outlined),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            if (rows.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    useRootNavigator: false,
                    builder: (context) => AlertDialog(
                      title: const Text('清理过期实例？'),
                      content: const Text('只会永久删除已超过保留期的实例。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('清理'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true) {
                    await WailsBridge.call('BrowserProfileTrashCleanup');
                    final refreshed = await WailsBridge.call(
                      'BrowserProfileTrashList',
                    );
                    rows = (refreshed as List? ?? [])
                        .whereType<Map>()
                        .map((item) => Map<String, dynamic>.from(item))
                        .toList();
                    setDialog(() {});
                  }
                },
                child: const Text('清理过期实例'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tagOptions =
        _profiles
            .expand(
              (profile) =>
                  (profile['tags'] as List? ?? []).map((tag) => tag.toString()),
            )
            .where((tag) => tag.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final coreOptions =
        _profiles
            .map((profile) => (profile['coreId'] ?? '').toString())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final proxyOptions =
        _profiles
            .map(
              (profile) =>
                  (profile['proxyGroupName'] ??
                          profile['proxyName'] ??
                          profile['proxyId'] ??
                          profile['proxyConfig'] ??
                          '')
                      .toString(),
            )
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final visible = _profiles.where((profile) {
      final query = _query.trim().toLowerCase();
      final searchable =
          '${profile['profileName'] ?? ''} ${profile['profileId'] ?? ''} ${(profile['keywords'] as List? ?? []).join(' ')} ${(profile['tags'] as List? ?? []).join(' ')}'
              .toLowerCase();
      if (query.isNotEmpty && !searchable.contains(query)) return false;
      if (_statusFilter == 'running' && profile['running'] != true)
        return false;
      if (_statusFilter == 'stopped' && profile['running'] == true)
        return false;
      if (_tagFilter.isNotEmpty &&
          !(profile['tags'] as List? ?? []).contains(_tagFilter))
        return false;
      if (_coreFilter.isNotEmpty &&
          profile['coreId']?.toString() != _coreFilter)
        return false;
      final proxyLabel =
          (profile['proxyGroupName'] ??
                  profile['proxyName'] ??
                  profile['proxyId'] ??
                  profile['proxyConfig'] ??
                  '')
              .toString();
      if (_proxyFilter.isNotEmpty && proxyLabel != _proxyFilter) return false;
      if (_groupFilter.isNotEmpty &&
          profile['groupId']?.toString() != _groupFilter)
        return false;
      return true;
    }).toList();
    final visibleIds = visible
        .map((profile) => profile['profileId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final allVisibleSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selectedProfileIds.contains);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '管理浏览器实例与独立配置',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showTrash,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('回收站'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _manageGroups,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('分组'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _importProfiles,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('导入实例'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _profiles.isEmpty ? null : _exportProfiles,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('导出实例'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _editProfile(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建配置'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton.icon(
                onPressed: visibleIds.isEmpty
                    ? null
                    : () => setState(() {
                        if (allVisibleSelected) {
                          _selectedProfileIds.removeAll(visibleIds);
                        } else {
                          _selectedProfileIds.addAll(visibleIds);
                        }
                      }),
                icon: Icon(
                  allVisibleSelected ? Icons.deselect : Icons.select_all,
                ),
                label: Text(allVisibleSelected ? '取消全选' : '全选当前结果'),
              ),
              const Spacer(),
              Text('共 ${visible.length} 个实例'),
            ],
          ),
          if (_selectedProfileIds.isNotEmpty) ...[
            Row(
              children: [
                Text('已选 ${_selectedProfileIds.length} 个实例'),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busyProfile == null
                      ? () => _batchToggleProfiles(true)
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('批量启动'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busyProfile == null
                      ? () => _batchToggleProfiles(false)
                      : null,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('批量关闭'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busyProfile == null
                      ? () => _exportProfiles(_selectedProfileIds.toList())
                      : null,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('导出'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _busyProfile == null ? _batchDeleteProfiles : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('移入回收站'),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: '搜索实例名称或编号',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFilter,
                  decoration: const InputDecoration(labelText: '状态'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('全部状态')),
                    DropdownMenuItem(value: 'running', child: Text('运行中')),
                    DropdownMenuItem(value: 'stopped', child: Text('已停止')),
                  ],
                  onChanged: (value) =>
                      setState(() => _statusFilter = value ?? 'all'),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: tagOptions.contains(_tagFilter)
                      ? _tagFilter
                      : '',
                  decoration: const InputDecoration(labelText: '标签'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部标签')),
                    for (final tag in tagOptions)
                      DropdownMenuItem(value: tag, child: Text(tag)),
                  ],
                  onChanged: (value) =>
                      setState(() => _tagFilter = value ?? ''),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: coreOptions.contains(_coreFilter)
                      ? _coreFilter
                      : '',
                  decoration: const InputDecoration(labelText: '内核'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部内核')),
                    for (final core in coreOptions)
                      DropdownMenuItem(value: core, child: Text(core)),
                  ],
                  onChanged: (value) =>
                      setState(() => _coreFilter = value ?? ''),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  initialValue: proxyOptions.contains(_proxyFilter)
                      ? _proxyFilter
                      : '',
                  decoration: const InputDecoration(labelText: '代理'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部代理')),
                    for (final proxy in proxyOptions)
                      DropdownMenuItem(
                        value: proxy,
                        child: Text(proxy, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _proxyFilter = value ?? ''),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  initialValue:
                      _groups.any((group) => group['groupId'] == _groupFilter)
                      ? _groupFilter
                      : '',
                  decoration: const InputDecoration(labelText: '分组'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部分组')),
                    for (final group in _groups)
                      DropdownMenuItem(
                        value: group['groupId']?.toString(),
                        child: Text((group['groupName'] ?? '').toString()),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _groupFilter = value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorPanel(message: _error!, onRetry: _reload)
                : visible.isEmpty
                ? _EmptyProfiles(hasProfiles: _profiles.isNotEmpty)
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final profile = visible[index];
                      final running = profile['running'] == true;
                      final id = profile['profileId']?.toString() ?? '';
                      final name = profile['profileName']?.toString().trim();
                      final busy = _busyProfile == id;
                      final tags =
                          (profile['tags'] as List?)
                              ?.map((tag) => tag.toString())
                              .where((tag) => tag.isNotEmpty)
                              .toList() ??
                          const <String>[];
                      return PrismCard(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _selectedProfileIds.contains(id),
                                onChanged: (selected) => setState(() {
                                  if (selected == true) {
                                    _selectedProfileIds.add(id);
                                  } else {
                                    _selectedProfileIds.remove(id);
                                  }
                                }),
                              ),
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.language,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name == null || name.isEmpty
                                          ? '未命名实例'
                                          : name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (tags.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: tags
                                        .take(3)
                                        .map(
                                          (tag) => Chip(
                                            label: Text(
                                              tag,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 16),
                              _RunningStatus(running: running),
                              const SizedBox(width: 12),
                              FilledButton.tonalIcon(
                                onPressed: busy
                                    ? null
                                    : () => _toggleProfile(profile),
                                icon: busy
                                    ? const SizedBox.square(
                                        dimension: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        running ? Icons.stop : Icons.play_arrow,
                                        size: 18,
                                      ),
                                label: Text(running ? '关闭' : '启动'),
                              ),
                              PopupMenuButton<String>(
                                tooltip: '更多操作',
                                onSelected: (action) {
                                  if (action == 'edit') _editProfile(profile);
                                  if (action == 'copy') _copyProfile(profile);
                                  if (action == 'delete')
                                    _deleteProfile(profile);
                                  if (action == 'detail')
                                    widget.onOpenDetails?.call(id);
                                  if (action == 'restart')
                                    _restartProfile(profile);
                                  if (action == 'export') _exportProfiles([id]);
                                  if (action == 'code')
                                    _editLaunchCode(profile);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'detail',
                                    child: Text('查看详情'),
                                  ),
                                  PopupMenuItem(
                                    value: 'restart',
                                    child: Text('重启实例'),
                                  ),
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑实例'),
                                  ),
                                  PopupMenuItem(
                                    value: 'copy',
                                    child: Text('复制配置'),
                                  ),
                                  PopupMenuItem(
                                    value: 'code',
                                    child: Text('管理启动码'),
                                  ),
                                  PopupMenuItem(
                                    value: 'export',
                                    child: Text('导出实例'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('移入回收站'),
                                  ),
                                ],
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
}

class _RunningStatus extends StatelessWidget {
  const _RunningStatus({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    final color = running
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          running ? '运行中' : '已停止',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }
}

class _EmptyProfiles extends StatelessWidget {
  const _EmptyProfiles({required this.hasProfiles});

  final bool hasProfiles;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.web_asset_off_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(hasProfiles ? '没有匹配的实例' : '还没有浏览器实例'),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 38,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 10),
          const Text('无法连接到应用服务'),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
