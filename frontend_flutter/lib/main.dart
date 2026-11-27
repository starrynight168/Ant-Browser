import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:flutter/foundation.dart' show FlutterError, kDebugMode;
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
import 'quick_launch_dialog.dart';
import 'tags_page.dart';
import 'settings_page.dart';
import 'app_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installDebugErrorLogging();
  await AppBridge.initialize();
  try {
    final settings = AppBridge.readStorage('app_settings');
    if (settings.isNotEmpty) {
      final saved = jsonDecode(settings) as Map;
      final value = saved['theme'];
      if (value is String) setAppThemeMode(value);
      final color = saved['themeColor'];
      if (color is String) setAppThemeColor(color);
      final style = saved['themeStyle'];
      if (style is String) setAppThemeStyle(style);
      final motion = saved['motionIntensity'];
      if (motion is num) setAppMotionIntensity(motion);
    }
  } catch (_) {}
  runApp(const AntBrowserApp());
}

void _installDebugErrorLogging() {
  if (!kDebugMode) return;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(_writeDebugError(details.toString(), details.stack));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_writeDebugError(error.toString(), stack));
    return false;
  };
}

Future<void> _writeDebugError(String error, StackTrace? stack) async {
  try {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}ant-browser-flutter-error.log',
    );
    await file.writeAsString(
      '${DateTime.now().toIso8601String()}\n$error\n${stack ?? ''}\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

class AntBrowserApp extends StatelessWidget {
  const AntBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        appThemeMode,
        appThemeColor,
        appThemeStyle,
      ]),
      builder: (context, _) {
        final themeMode = appThemeMode.value;
        final seedColor = appThemeColor.value;
        final style = appThemeStyle.value;
        return prism.PrismApp(
          title: 'Ant Browser',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: [AntPrismLocalizationsDelegate()],
          themeMode: themeMode,
          theme: buildAntPrismTheme(Brightness.light, seedColor, style),
          darkTheme: buildAntPrismTheme(Brightness.dark, seedColor, style),
          builder: (context, child) {
            final size = MediaQuery.sizeOf(context);
            final theme = prism.Theme.of(context);
            final cs = theme.colorScheme;
            final isDark = theme.brightness == Brightness.dark;
            final neutralFill = cs.onSurface.withValues(
              alpha: isDark ? 0.10 : 0.06,
            );
            final neutralHover = cs.onSurface.withValues(
              alpha: isDark ? 0.16 : 0.11,
            );
            final primaryTint = cs.primary.withValues(
              alpha: isDark ? 0.24 : 0.14,
            );
            final primaryTintHover = cs.primary.withValues(
              alpha: isDark ? 0.34 : 0.22,
            );
            final textSoftFill = cs.onSurface.withValues(
              alpha: isDark ? 0.06 : 0.04,
            );
            return ValueListenableBuilder<bool>(
              valueListenable: appMotionEnabled,
              builder: (context, motionEnabled, inner) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: !motionEnabled),
                child: inner!,
              ),
              child: prism.ViewScope(
                size: size,
                isMobile: size.width < 600,
                child: prism.ButtonTheme.merge(
                  data: prism.ButtonThemeData(
                    outlined: prism.ButtonStyle(
                      backgroundColor: WidgetStateProperty.fromMap({
                        WidgetState.disabled: neutralFill.withValues(
                          alpha: 0.45,
                        ),
                        WidgetState.hovered: neutralHover,
                        WidgetState.any: neutralFill,
                      }),
                      foregroundColor: WidgetStateProperty.fromMap({
                        WidgetState.disabled: cs.onSurface.withValues(
                          alpha: 0.36,
                        ),
                        WidgetState.any: cs.onSurface,
                      }),
                      overlayColor: WidgetStateProperty.fromMap({
                        WidgetState.hovered: cs.onSurface.withValues(
                          alpha: 0.05,
                        ),
                        WidgetState.pressed: cs.onSurface.withValues(
                          alpha: 0.10,
                        ),
                        WidgetState.any: const Color(0x00000000),
                      }),
                      side: const WidgetStatePropertyAll(BorderSide.none),
                      shape: prism.AppShape.full,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 0,
                      ),
                    ),
                    filled: prism.ButtonStyle(
                      backgroundColor: WidgetStateProperty.fromMap({
                        WidgetState.disabled: neutralFill.withValues(
                          alpha: 0.45,
                        ),
                        WidgetState.hovered: primaryTintHover,
                        WidgetState.any: primaryTint,
                      }),
                      foregroundColor: WidgetStateProperty.fromMap({
                        WidgetState.disabled: cs.onSurface.withValues(
                          alpha: 0.36,
                        ),
                        WidgetState.any: cs.primary,
                      }),
                      overlayColor: WidgetStateProperty.fromMap({
                        WidgetState.hovered: cs.primary.withValues(alpha: 0.08),
                        WidgetState.pressed: cs.primary.withValues(alpha: 0.14),
                        WidgetState.any: const Color(0x00000000),
                      }),
                      side: const WidgetStatePropertyAll(BorderSide.none),
                      shape: prism.AppShape.full,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 0,
                      ),
                    ),
                    text: prism.ButtonStyle(
                      backgroundColor: WidgetStateProperty.fromMap({
                        WidgetState.disabled: const Color(0x00000000),
                        WidgetState.hovered: neutralHover,
                        WidgetState.any: textSoftFill,
                      }),
                      foregroundColor: WidgetStateProperty.fromMap({
                        WidgetState.disabled: cs.onSurface.withValues(
                          alpha: 0.36,
                        ),
                        WidgetState.any: cs.onSurface,
                      }),
                      overlayColor: WidgetStateProperty.fromMap({
                        WidgetState.hovered: cs.onSurface.withValues(
                          alpha: 0.05,
                        ),
                        WidgetState.pressed: cs.onSurface.withValues(
                          alpha: 0.10,
                        ),
                        WidgetState.any: const Color(0x00000000),
                      }),
                      side: const WidgetStatePropertyAll(BorderSide.none),
                      shape: prism.AppShape.full,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 0,
                      ),
                    ),
                    icon: prism.ButtonStyle(
                      backgroundColor: WidgetStateProperty.fromMap({
                        WidgetState.disabled: const Color(0x00000000),
                        WidgetState.hovered: neutralHover,
                        WidgetState.any: textSoftFill,
                      }),
                      foregroundColor: WidgetStateProperty.fromMap({
                        WidgetState.disabled: cs.onSurface.withValues(
                          alpha: 0.36,
                        ),
                        WidgetState.selected: cs.primary,
                        WidgetState.any: cs.onSurfaceVariant,
                      }),
                      side: WidgetStateProperty.fromMap({
                        WidgetState.disabled: BorderSide.none,
                        WidgetState.hovered: BorderSide(
                          color: cs.primary.withValues(
                            alpha: isDark ? 0.30 : 0.22,
                          ),
                          width: 1,
                        ),
                        WidgetState.any: BorderSide(
                          color: cs.outlineVariant.withValues(
                            alpha: isDark ? 0.22 : 0.28,
                          ),
                          width: 1,
                        ),
                      }),
                      overlayColor: WidgetStateProperty.fromMap({
                        WidgetState.hovered: cs.onSurface.withValues(
                          alpha: 0.06,
                        ),
                        WidgetState.pressed: cs.onSurface.withValues(
                          alpha: 0.14,
                        ),
                        WidgetState.any: const Color(0x00000000),
                      }),
                      shape: prism.AppShape.full,
                    ),
                  ),
                  child: child!,
                ),
              ),
            );
          },
          home: const _AntBrowserBootHost(),
        );
      },
    );
  }
}

class _AntBrowserBootHost extends StatefulWidget {
  const _AntBrowserBootHost();

  @override
  State<_AntBrowserBootHost> createState() => _AntBrowserBootHostState();
}

class _AntBrowserBootHostState extends State<_AntBrowserBootHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    final spec = PrismMotionSpec.current;
    final motionOn = spec.enabled;
    _controller = AnimationController(
      vsync: this,
      duration: motionOn ? const Duration(milliseconds: 980) : Duration.zero,
    );
    if (!motionOn) {
      _dismissed = true;
    } else {
      _controller.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _dismissed = true);
        }
      });
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) {
      return const AntBrowserShell();
    }
    final colors = prism.Theme.of(context).colorScheme;
    final isDark = prism.Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final reveal = Curves.easeOutCubic.transform(
              ((_controller.value - 0.62) / 0.38).clamp(0.0, 1.0),
            );
            final scale = 0.985 + 0.015 * reveal;
            return Transform.scale(scale: scale, child: child);
          },
          child: const AntBrowserShell(),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final enter = Curves.easeOutBack.transform(
              (t / 0.36).clamp(0.0, 1.0),
            );
            final progress = Curves.easeInOutCubic.transform(
              ((t - 0.08) / 0.56).clamp(0.0, 1.0),
            );
            final exit = Curves.easeInCubic.transform(
              ((t - 0.66) / 0.34).clamp(0.0, 1.0),
            );
            final opacity = (1.0 - exit).clamp(0.0, 1.0);
            final exitScale = 1.0 + 0.03 * exit;
            return IgnorePointer(
              ignoring: exit > 0.35,
              child: Opacity(
                opacity: opacity,
                child: ColoredBox(
                  color: colors.surface,
                  child: Center(
                    child: Transform.scale(
                      scale: exitScale,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: colors.surfaceContainerLow,
                          shape: RoundedSuperellipseBorder(
                            borderRadius: prism.AppRadius.all(
                              prism.AppCorner.xxl,
                            ),
                            side: BorderSide(
                              color: colors.outlineVariant.withValues(
                                alpha: isDark ? 0.28 : 0.35,
                              ),
                              width: 1,
                            ),
                          ),
                          shadows: [
                            BoxShadow(
                              color: colors.shadow.withValues(
                                alpha: isDark ? 0.32 : 0.08,
                              ),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 34,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.scale(
                                scale: 0.78 + 0.22 * enter,
                                child: SizedBox.square(
                                  dimension: 72,
                                  child: DecoratedBox(
                                    decoration: ShapeDecoration(
                                      color: colors.primaryContainer,
                                      shape: RoundedSuperellipseBorder(
                                        borderRadius: prism.AppRadius.all(
                                          prism.AppCorner.xl,
                                        ),
                                        side: BorderSide(
                                          color: colors.primary.withValues(
                                            alpha: isDark ? 0.38 : 0.24,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: Center(
                                      child: PrismGlyph(
                                        AntGlyphs.browser,
                                        size: 34,
                                        color: colors.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Ant Browser',
                                style: prism.AppTextStyle.title2.of(
                                  context,
                                  emphasized: true,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '正在准备指纹浏览器工作区…',
                                style: prism.AppTextStyle.footnote
                                    .of(context)
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 22),
                              SizedBox(
                                width: 220,
                                child: prism.LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
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
  '/browser/list': AntGlyphs.browser,
  '/browser/automation': AntGlyphs.robot,
  '/browser/cores': AntGlyphs.cpu,
  '/browser/extensions': AntGlyphs.extension,
  '/browser/proxy-pool': AntGlyphs.globe,
  '/browser/proxy-virtual-groups': AntGlyphs.hub,
  '/browser/bookmarks': AntGlyphs.bookmark,
  '/browser/tags': AntGlyphs.tag,
  '/settings': AntGlyphs.settings,
  '/system/backup': AntGlyphs.archive,
  '/system/docs': AntGlyphs.docs,
  '/browser/logs': AntGlyphs.logs,
  '/notifications': AntGlyphs.bell,
  '/profile': AntGlyphs.user,
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
  bool _quickLaunchOpen = false;
  bool _updateAvailable = false;
  late final void Function() _removeCloseListener;
  late final void Function() _removeUpdateListener;
  late final NotificationStore _notificationStore;

  @override
  void initState() {
    super.initState();
    _notificationStore = NotificationStore();
    _removeCloseListener = AppBridge.onEvent('app:request-close', (_) {
      _showCloseDialog();
    });
    _removeUpdateListener = AppBridge.onEvent('app:update:available', (
      payload,
    ) {
      if (!mounted) return;
      final available = payload is! Map || payload['updateAvailable'] != false;
      if (available) setState(() => _updateAvailable = true);
    });
    unawaited(_checkInitialUpdateBadge());
  }

  Future<void> _checkInitialUpdateBadge() async {
    try {
      final res = await AppBridge.call('CheckAppUpdate');
      if (mounted && res is Map) {
        setState(() {
          _updateAvailable =
              res['ok'] == true && res['updateAvailable'] == true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _removeCloseListener();
    _removeUpdateListener();
    _notificationStore.dispose();
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
      final platform = await AppBridge.platform();
      if (!mounted) return;
      final motionSpec = PrismMotionSpec.current;
      action = await Navigator.of(context, rootNavigator: false).push<String>(
        PageRouteBuilder<String>(
          opaque: false,
          barrierDismissible: true,
          barrierColor: const Color(0x990A110E),
          barrierLabel: '关闭确认',
          transitionDuration: motionSpec.enabled
              ? motionSpec.pageDuration
              : Duration.zero,
          reverseTransitionDuration: motionSpec.enabled
              ? motionSpec.barDuration
              : Duration.zero,
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
            if (!motionSpec.enabled) return child;
            final curve = CurvedAnimation(
              parent: animation,
              curve: motionSpec.smoothCurve,
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
      if ((await AppBridge.platform()).toLowerCase() == 'windows') {
        AppBridge.hideWindow();
      } else {
        AppBridge.minimiseWindow();
      }
      return;
    }
    if (action == 'quit-app') {
      await AppBridge.call('QuitAppOnly');
      return;
    }
    if (action == 'quit-all') {
      AppBridge.hideWindow();
      try {
        await AppBridge.call('ForceQuit');
      } catch (_) {
        AppBridge.quit();
      }
    }
  }

  Future<void> _showQuickLaunch() async {
    if (_quickLaunchOpen || !mounted) return;
    _quickLaunchOpen = true;
    try {
      await showPrismDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const QuickLaunchDialog(),
      );
    } finally {
      _quickLaunchOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _showQuickLaunch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _showQuickLaunch,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: colors.surfaceContainer,
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _notificationStore,
                builder: (context, _) => _Sidebar(
                  activePath: _activePath,
                  compact: _compactSidebar,
                  unreadCount: _notificationStore.unreadCount,
                  updateAvailable: _updateAvailable,
                  onSelect: (path) => setState(() => _activePath = path),
                  onToggle: () =>
                      setState(() => _compactSidebar = !_compactSidebar),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: prism.Surface(
                  color: prism.SurfaceLevel.page.colorOf(colors),
                  shape: prism.AppShape.xxl,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrismPageHeader(
                        title: _activeTitle,
                        trailing: _QuickLaunchTrigger(
                          onPressed: _showQuickLaunch,
                        ),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: appMotionIntensity,
                          builder: (context, child) =>
                              prism.PageTransitionSwitcher(
                                duration: PrismMotionSpec.current.pageDuration,
                                transitionBuilder:
                                    PrismSlideThroughTransition.builder,
                                child: child!,
                              ),
                          child: KeyedSubtree(
                            key: ValueKey(_activePath),
                            child: _activePath == '/browser/list'
                                ? BrowserListPage(
                                    onOpenDetails: (id) => setState(
                                      () => _activePath = '/browser/detail/$id',
                                    ),
                                    onOpenExtensionManagement: () => setState(
                                      () => _activePath = '/browser/extensions',
                                    ),
                                    onOpenBackup: () => setState(
                                      () => _activePath = '/system/backup',
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
                                    onOpenExtensionManagement: () => setState(
                                      () => _activePath = '/browser/extensions',
                                    ),
                                    initialQuery:
                                        _activePath.split('/').last == 'new'
                                        ? ''
                                        : _activePath.split('/').last,
                                  )
                                : _activePath == '/profile'
                                ? AboutPage(
                                    onUpdateStatusChanged: (available) {
                                      if (mounted) {
                                        setState(
                                          () => _updateAvailable = available,
                                        );
                                      }
                                    },
                                  )
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
                                    onRun: (id) => setState(
                                      () => _activePath =
                                          '/browser/automation/run/$id',
                                    ),
                                    onCreate: () => setState(
                                      () => _activePath =
                                          '/browser/automation/new',
                                    ),
                                  )
                                : _activePath.startsWith(
                                    '/browser/automation/run/',
                                  )
                                ? AutomationScriptDetailPage(
                                    scriptId: _activePath.split('/').last,
                                    autoRun: true,
                                    onBack: () => setState(
                                      () => _activePath = '/browser/automation',
                                    ),
                                    onCreated: (id) => setState(
                                      () => _activePath =
                                          '/browser/automation/$id',
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
                                : _activePath == '/system/docs'
                                ? const DocsPage()
                                : const BrowserListPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
    this.updateAvailable = false,
    required this.onSelect,
    required this.onToggle,
  });

  final String activePath;
  final bool compact;
  final int unreadCount;
  final bool updateAvailable;
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
        selectedPath.startsWith('/browser/copy/')) {
      selectedPath = '/browser/list';
    } else if (selectedPath.startsWith('/browser/automation/')) {
      selectedPath = '/browser/automation';
    } else if (selectedPath == '/browser/proxy-align') {
      selectedPath = '/browser/proxy-pool';
    } else if (selectedPath.startsWith('/system/backup/')) {
      selectedPath = '/system/backup';
    }
    final selectedIndex = items.indexWhere((item) => item.path == selectedPath);
    final color = prism.ColorScheme.of(context).surfaceContainerLow;
    return prism.Surface(
      color: color,
      shape: prism.AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: prism.NavigationSidebar(
        destinations: [
          for (final item in items)
            prism.SidebarDestination(
              glyph: _navGlyphs[item.path]!,
              dividerBefore:
                  item.path == '/browser/proxy-pool' ||
                  item.path == '/browser/bookmarks' ||
                  item.path == '/settings' ||
                  item.path == '/profile',
              label: item.path == '/notifications' && unreadCount > 0
                  ? '${item.title} (${unreadCount > 99 ? '99+' : unreadCount})'
                  : item.path == '/profile' && updateAvailable
                  ? '${item.title} · 新版本'
                  : item.title,
            ),
        ],
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        expanded: !compact,
        onSelected: (index) => onSelect(items[index].path),
        onToggle: onToggle,
      ),
    );
  }
}

class _QuickLaunchTrigger extends StatelessWidget {
  const _QuickLaunchTrigger({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    // 壳层走 PrismTonalButton（tonal 胶囊 + hover/press overlay），
    // 不再手搓 ShapeDecoration；键帽保留 Surface。
    return PrismHoverMotion(
      hoverScale: 1.06,
      pressScale: 0.925,
      child: PrismTonalButton(
        onPressed: onPressed,
        style: prism.ButtonStyle(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.fromLTRB(13, 0, 9, 0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrismGlyph(AntGlyphs.bolt, size: 15, color: colors.primary),
            const SizedBox(width: 10),
            Text(
              '快捷启动',
              style: prism.AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: colors.onSurface),
            ),
            const SizedBox(width: 10),
            prism.Surface(
              color: colors.surfaceContainerLowest,
              shape: prism.AppShape.sm,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: Text(
                  'Ctrl K',
                  style: prism.AppTextStyle.caption2
                      .of(context, emphasized: true)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          ],
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
    this.onOpenExtensionManagement,
    this.onOpenBackup,
  });

  final String initialQuery;
  final ValueChanged<String>? onOpenDetails;
  final VoidCallback? onOpenExtensionManagement;
  final VoidCallback? onOpenBackup;

  @override
  State<BrowserListPage> createState() => _BrowserListPageState();
}

class _BrowserListPageState extends State<BrowserListPage> {
  final _searchController = TextEditingController();
  final Set<String> _selectedProfileIds = {};
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _cores = [];
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _virtualGroups = [];
  final Map<String, int> _proxyLatencyMs = {};
  final Map<String, String> _proxyLatencyError = {};
  final Set<String> _testingProxyIds = {};
  final Set<String> _tagFilters = {};
  final List<void Function()> _eventUnsubscribers = [];
  bool _loading = true;
  bool _reloading = false;
  bool _silentRefreshInFlight = false;
  bool _filtersCollapsed = false;
  String? _error;
  String? _busyProfile;
  Timer? _profileRefreshTimer;
  String _viewMode = 'list';
  String _query = '';
  String _statusFilter = 'all';
  String _coreFilter = '';
  String _proxyFilter = '';
  String _groupFilter = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    final savedView = AppBridge.readStorage('browser:viewMode');
    if (savedView == 'card') _viewMode = 'card';
    _filtersCollapsed =
        AppBridge.readStorage('browser:headerCollapsed') == 'true';
    final savedFilters = AppBridge.readStorage('browser:filters');
    if (savedFilters.isNotEmpty) {
      try {
        final filters = jsonDecode(savedFilters) as Map;
        if (widget.initialQuery.isEmpty) {
          _query = '${filters['keyword'] ?? filters['kwSearch'] ?? ''}';
        }
        final savedStatus = '${filters['status'] ?? ''}';
        _statusFilter = savedStatus.isEmpty ? 'all' : savedStatus;
        _coreFilter = '${filters['coreId'] ?? ''}';
        _proxyFilter = '${filters['proxyId'] ?? ''}';
        _groupFilter = '${filters['groupId'] ?? ''}';
        _tagFilters.addAll(
          (filters['tags'] as List? ?? []).map((tag) => tag.toString()),
        );
      } catch (_) {}
    }
    _searchController.text = _query;
    _listenInstanceEvents();
    _profileRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshProfilesSilently()),
    );
    _reload();
  }

  void _listenInstanceEvents() {
    for (final event in const [
      'app:ready',
      'browser:instance:started',
      'browser:instance:stopped',
      'browser:instance:updated',
      'browser:instance:crashed',
    ]) {
      _eventUnsubscribers.add(
        AppBridge.onEvent(event, (_) => unawaited(_refreshProfilesSilently())),
      );
    }
  }

  @override
  void dispose() {
    _profileRefreshTimer?.cancel();
    for (final remove in _eventUnsubscribers) {
      remove();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshProfilesSilently() async {
    if (!mounted || _reloading || _silentRefreshInFlight) return;
    _silentRefreshInFlight = true;
    try {
      final result = await AppBridge.call('BrowserProfileList');
      if (!mounted) return;
      setState(() {
        _profiles = (result as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      });
    } catch (_) {
    } finally {
      _silentRefreshInFlight = false;
    }
  }

  Future<void> _loadFilterCatalogs() async {
    final results = await Future.wait([
      AppBridge.call('ListGroups').catchError((_) => null),
      AppBridge.call('BrowserCoreList').catchError((_) => null),
      AppBridge.call('BrowserProxyList').catchError((_) => null),
      AppBridge.call('BrowserProxyVirtualGroupList').catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _groups = (results[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _cores = (results[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _proxies = (results[2] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _virtualGroups = (results[3] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      for (final proxy in _proxies) {
        final pid = (proxy['proxyId'] ?? '').toString();
        final lat = proxy['lastLatencyMs'];
        if (pid.isNotEmpty && lat is num && lat > 0) {
          _proxyLatencyMs[pid] = lat.toInt();
        }
      }
    });
  }

  Future<void> _reload() async {
    if (_reloading || !mounted) return;
    _reloading = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AppBridge.call('BrowserProfileList');
      final rows = result is List ? result : const [];
      if (!mounted) return;
      setState(() {
        _profiles = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      });
      await _loadFilterCatalogs();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _reloading = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleProfile(Map<String, dynamic> profile) async {
    final id = profile['profileId']?.toString() ?? '';
    if (id.isEmpty) return;
    final running = profile['running'] == true;
    setState(() => _busyProfile = id);
    try {
      if (!running) {
        final validation = await AppBridge.call('ValidateProxyConfig', [
          (profile['proxyConfig'] ?? '').toString(),
          (profile['proxyId'] ?? '').toString(),
        ]);
        if (validation is Map && validation['supported'] == false) {
          await _showProxyStartDialog(
            profile,
            (validation['errorMsg'] ?? '当前代理链路不可用').toString(),
          );
          return;
        }
        await _warmProfileProxy(profile);
      }
      final result = await AppBridge.call(
        running ? 'BrowserInstanceStop' : 'BrowserInstanceStart',
        [id],
      );
      await _reload();
      if (!running && result is Map && mounted) {
        final warning = (result['runtimeWarning'] ?? '').toString().trim();
        if (warning.isNotEmpty) {
          showPrismNotice(context, '实例已启动（提示：$warning）');
        } else if (result['debugReady'] == false) {
          showPrismNotice(context, '实例已启动，调试接口待就绪');
        }
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, ('操作失败：$error').toString());
      }
    } finally {
      if (mounted) setState(() => _busyProfile = null);
    }
  }

  Future<void> _showProxyStartDialog(
    Map<String, dynamic> profile,
    String error,
  ) async {
    final action = await showPrismDialog<String>(
      context: context,
      builder: (dialogContext) => PrismDialog(
        title: const Text('代理链路不可用'),
        content: Text('$error\n\n可以本次直连启动，或先修改实例代理。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          prism.OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, 'edit'),
            child: const Text('修改代理'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'direct'),
            child: const Text('直连启动'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _editProfile(profile);
    if (action == 'direct') await _startProfileDirect(profile);
  }

  Future<void> _startProfileDirect(Map<String, dynamic> profile) async {
    final id = (profile['profileId'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() => _busyProfile = id);
    try {
      final result = await AppBridge.call('BrowserInstanceStartDirect', [id]);
      await _reload();
      if (result is Map && mounted) {
        final warning = (result['runtimeWarning'] ?? '').toString().trim();
        if (warning.isNotEmpty) {
          showPrismNotice(context, '已直连启动（提示：$warning）');
        }
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '直连启动失败：$error');
    } finally {
      if (mounted) setState(() => _busyProfile = null);
    }
  }

  Future<void> _testProfileProxy(Map<String, dynamic> profile) async {
    final profileId = (profile['profileId'] ?? '').toString();
    if (profileId.isEmpty || _testingProxyIds.contains(profileId)) return;
    setState(() => _testingProxyIds.add(profileId));
    try {
      var proxyId = (profile['proxyId'] ?? '').toString();
      if ((profile['proxyMode'] ?? '').toString() == 'dynamic') {
        final groups = await AppBridge.call('BrowserProxyVirtualGroupList');
        final groupName = (profile['proxyGroupName'] ?? '').toString();
        final matches = (groups as List? ?? []).whereType<Map>().where(
          (group) => group['groupName']?.toString() == groupName,
        );
        if (matches.isNotEmpty) {
          final group = matches.first;
          proxyId =
              (group['selectedProxyId'] ?? group['preferredProxyId'] ?? '')
                  .toString();
          if (proxyId.isEmpty) {
            final members = group['memberProxyIds'] as List? ?? [];
            if (members.isNotEmpty) proxyId = members.first.toString();
          }
        }
      }
      final proxyConfig = (profile['proxyConfig'] ?? '').toString();
      if (proxyId.isEmpty && proxyConfig.isEmpty) {
        if (mounted) showPrismNotice(context, '当前实例没有可测速的代理');
        return;
      }
      final result = proxyId.isNotEmpty
          ? await AppBridge.call('BrowserProxyTestSpeed', [proxyId])
          : await AppBridge.call('TestProxyConnectivity', [
              profileId,
              proxyConfig,
            ]);
      final values = result is Map ? Map<String, dynamic>.from(result) : {};
      final ok = values['ok'] == true;
      final latency = values['latencyMs'];
      final key = proxyId.isNotEmpty ? proxyId : profileId;
      if (mounted) {
        setState(() {
          if (ok && latency is num) {
            _proxyLatencyMs[key] = latency.toInt();
            _proxyLatencyError.remove(key);
          } else {
            _proxyLatencyMs.remove(key);
            _proxyLatencyError[key] = (values['error'] ?? '连接失败').toString();
          }
        });
      }
      final message = ok
          ? '代理可用，延迟 ${values['latencyMs'] ?? 0} ms'
          : '代理测试失败：${values['error'] ?? '连接失败'}';
      if (mounted) showPrismNotice(context, message);
    } catch (error) {
      if (mounted) showPrismNotice(context, '代理测试失败：$error');
    } finally {
      if (mounted) setState(() => _testingProxyIds.remove(profileId));
    }
  }

  Future<void> _pickProfileProxy(Map<String, dynamic> profile) async {
    final profileId = (profile['profileId'] ?? '').toString();
    if (profileId.isEmpty) return;
    try {
      final responses = await Future.wait([
        AppBridge.call('BrowserProxyList'),
        AppBridge.call('BrowserProxyVirtualGroupList'),
      ]);
      final proxies = (responses[0] as List? ?? [])
          .whereType<Map>()
          .map((proxy) => Map<String, dynamic>.from(proxy))
          .toList();
      final direct = proxies.any(
        (proxy) => proxy['proxyConfig'] == 'direct://',
      );
      if (!direct) {
        proxies.insert(0, {
          'proxyId': '',
          'proxyName': '直连',
          'proxyConfig': 'direct://',
          '_kind': 'direct',
        });
      }
      final virtualGroups = (responses[1] as List? ?? [])
          .whereType<Map>()
          .map((group) => Map<String, dynamic>.from(group))
          .toList();
      final entityGroups =
          proxies
              .map((p) => (p['groupName'] ?? '').toString().trim())
              .where((g) => g.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final search = TextEditingController();
      var selectedGroup = '__all__';
      var testingAll = false;
      final testingIds = <String>{};
      final selection = await showPrismDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialog) {
            final query = search.text.trim().toLowerCase();
            final filteredProxies = proxies.where((proxy) {
              if (selectedGroup == '__virtual__') return false;
              if (selectedGroup == '__direct__' &&
                  proxy['proxyConfig'] != 'direct://') {
                return false;
              }
              if (selectedGroup != '__all__' &&
                  selectedGroup != '__direct__' &&
                  (proxy['groupName'] ?? '').toString().trim() !=
                      selectedGroup) {
                return false;
              }
              final text =
                  '${proxy['proxyName'] ?? ''} ${proxy['proxyId'] ?? ''} ${proxy['groupName'] ?? ''} ${proxy['proxyConfig'] ?? ''}'
                      .toLowerCase();
              return query.isEmpty || text.contains(query);
            }).toList();
            final filteredGroups = virtualGroups.where((group) {
              if (selectedGroup != '__all__' &&
                  selectedGroup != '__virtual__') {
                return false;
              }
              final text =
                  '${group['groupName'] ?? ''} ${group['groupId'] ?? ''}'
                      .toLowerCase();
              return query.isEmpty || text.contains(query);
            }).toList();

            Future<void> testOne(String pid) async {
              if (pid.isEmpty || testingIds.contains(pid)) return;
              setDialog(() => testingIds.add(pid));
              try {
                final res = await AppBridge.call('BrowserProxyTestSpeed', [
                  pid,
                ]);
                final ok = res is Map && res['ok'] == true;
                final lat = res is Map ? res['latencyMs'] : null;
                if (ok && lat is num) {
                  _proxyLatencyMs[pid] = lat.toInt();
                  _proxyLatencyError.remove(pid);
                } else {
                  _proxyLatencyMs.remove(pid);
                  _proxyLatencyError[pid] = res is Map
                      ? (res['error'] ?? '失败').toString()
                      : '失败';
                }
              } catch (e) {
                _proxyLatencyError[pid] = e.toString();
              } finally {
                if (context.mounted) {
                  setDialog(() => testingIds.remove(pid));
                }
              }
            }

            Future<void> testAllVisible() async {
              final ids = filteredProxies
                  .map((p) => (p['proxyId'] ?? '').toString())
                  .where((id) => id.isNotEmpty && id != '__direct__')
                  .toList();
              if (ids.isEmpty || testingAll) return;
              setDialog(() => testingAll = true);
              try {
                final res = await AppBridge.call('BrowserProxyBatchTestSpeed', [
                  ids,
                  0,
                ]);
                if (res is List) {
                  for (final row in res.whereType<Map>()) {
                    final pid = (row['proxyId'] ?? '').toString();
                    if (pid.isEmpty) continue;
                    if (row['ok'] == true && row['latencyMs'] is num) {
                      _proxyLatencyMs[pid] = (row['latencyMs'] as num).toInt();
                      _proxyLatencyError.remove(pid);
                    } else {
                      _proxyLatencyMs.remove(pid);
                      _proxyLatencyError[pid] = (row['error'] ?? '失败')
                          .toString();
                    }
                  }
                }
              } catch (_) {
              } finally {
                if (context.mounted) setDialog(() => testingAll = false);
              }
            }

            return PrismDialog(
              title: const Text('切换代理'),
              content: SizedBox(
                width: 600,
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: PrismSearchBar(
                            controller: search,
                            hintText: '搜索代理名称、分组或配置',
                            onChanged: (_) => setDialog(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        prism.OutlinedButton.icon(
                          onPressed: testingAll ? null : testAllVisible,
                          icon: testingAll
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: PrismProgressIndicator(size: 14),
                                )
                              : const PrismGlyph(AntGlyphs.speed, size: 16),
                          label: const Text('全部测速'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        spacing: 6,
                        children: [
                          PrismChip(
                            label: const Text('全部'),
                            selected: selectedGroup == '__all__',
                            onPressed: () =>
                                setDialog(() => selectedGroup = '__all__'),
                          ),
                          PrismChip(
                            label: const Text('直连'),
                            selected: selectedGroup == '__direct__',
                            onPressed: () =>
                                setDialog(() => selectedGroup = '__direct__'),
                          ),
                          if (virtualGroups.isNotEmpty)
                            PrismChip(
                              label: Text('虚拟分组 (${virtualGroups.length})'),
                              selected: selectedGroup == '__virtual__',
                              onPressed: () => setDialog(
                                () => selectedGroup = '__virtual__',
                              ),
                            ),
                          for (final g in entityGroups)
                            PrismChip(
                              label: Text(g),
                              selected: selectedGroup == g,
                              onPressed: () =>
                                  setDialog(() => selectedGroup = g),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final proxy in filteredProxies)
                            Builder(
                              builder: (context) {
                                final pid = (proxy['proxyId'] ?? '').toString();
                                final isDirect =
                                    proxy['proxyConfig'] == 'direct://';
                                final lat = _proxyLatencyMs[pid];
                                final err = _proxyLatencyError[pid];
                                final isFailed = err != null && err.isNotEmpty;
                                final isTesting = testingIds.contains(pid);
                                return PrismListTile(
                                  leading: PrismGlyph(
                                    AntGlyphs.globe,
                                    size: 18,
                                    color: isFailed
                                        ? PrismToneColors.of(
                                            context,
                                            PrismTone.danger,
                                          ).fg
                                        : null,
                                  ),
                                  title: Text(
                                    (proxy['proxyName'] ??
                                            proxy['proxyId'] ??
                                            '直连')
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    (proxy['groupName'] ??
                                            proxy['proxyConfig'] ??
                                            '')
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: (!isDirect && pid.isNotEmpty)
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          spacing: 6,
                                          children: [
                                            if (isTesting)
                                              const PrismProgressIndicator(
                                                size: 14,
                                              )
                                            else if (lat != null)
                                              PrismBadge(
                                                label: '${lat}ms',
                                                tone: lat < 200
                                                    ? PrismTone.success
                                                    : lat < 500
                                                    ? PrismTone.warning
                                                    : PrismTone.danger,
                                              )
                                            else if (isFailed)
                                              const PrismBadge(
                                                label: '不可用',
                                                tone: PrismTone.danger,
                                              )
                                            else
                                              const PrismBadge(
                                                label: '未测速',
                                                tone: PrismTone.neutral,
                                              ),
                                            prism.IconButton(
                                              tooltip: '测速',
                                              onPressed: isTesting
                                                  ? null
                                                  : () => testOne(pid),
                                              icon: const PrismGlyph(
                                                AntGlyphs.speed,
                                                size: 16,
                                              ),
                                            ),
                                          ],
                                        )
                                      : null,
                                  onTap: isFailed
                                      ? () => showPrismNotice(
                                          context,
                                          '该代理测速失败，请先确认可用后再选择：$err',
                                        )
                                      : () =>
                                            Navigator.pop(dialogContext, proxy),
                                );
                              },
                            ),
                          for (final group in filteredGroups)
                            PrismListTile(
                              leading: const PrismGlyph(
                                AntGlyphs.hub,
                                size: 18,
                              ),
                              title: Text(
                                '虚拟分组 · ${group['groupName'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${(group['memberProxyIds'] as List? ?? []).length} 个节点 · ${group['strategy'] == 'sticky' ? '代理保持' : '轮询'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(dialogContext, {
                                ...group,
                                '_kind': 'virtual',
                              }),
                            ),
                          if (filteredProxies.isEmpty && filteredGroups.isEmpty)
                            const PrismEmptyState(
                              title: '没有匹配的代理',
                              glyph: AntGlyphs.globe,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                prism.TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        ),
      );
      search.dispose();
      if (selection == null || !mounted) return;
      final kind = (selection['_kind'] ?? '').toString();
      final isVirtual = kind == 'virtual';
      final proxyConfig = (selection['proxyConfig'] ?? '').toString();
      final proxyId = isVirtual
          ? (selection['groupId'] ?? '').toString()
          : (selection['proxyId'] ?? '').toString();
      final input = <String, dynamic>{
        'profileName': (profile['profileName'] ?? '').toString(),
        'userDataDir': (profile['userDataDir'] ?? '').toString(),
        'coreId': (profile['coreId'] ?? '').toString(),
        'restoreLastSession': profile['restoreLastSession'] ?? '',
        'fingerprintArgs': (profile['fingerprintArgs'] as List? ?? [])
            .map((item) => item.toString())
            .toList(),
        'proxyMode': 'fixed',
        'proxyId': proxyId,
        'proxyConfig': isVirtual
            ? ''
            : proxyId.isEmpty
            ? proxyConfig
            : '',
        'proxyGroupName': '',
        'memoryLimitMb': profile['memoryLimitMb'] ?? 0,
        'launchArgs': (profile['launchArgs'] as List? ?? [])
            .map((item) => item.toString())
            .toList(),
        'tags': (profile['tags'] as List? ?? [])
            .map((item) => item.toString())
            .toList(),
        'keywords': (profile['keywords'] as List? ?? [])
            .map((item) => item.toString())
            .toList(),
        'groupId': (profile['groupId'] ?? '').toString(),
      };
      await AppBridge.call('BrowserProfileUpdate', [profileId, input]);
      await _reload();
      if (mounted) showPrismNotice(context, '代理已切换');
    } catch (error) {
      if (mounted) showPrismNotice(context, '切换代理失败：$error');
    }
  }

  String _profileProxyLabel(Map<String, dynamic> profile) {
    final bindErr = (profile['proxyBindError'] ?? '').toString().trim();
    if (bindErr.isNotEmpty) return '代理已失效（需重选）';
    final mode = (profile['proxyMode'] ?? '').toString();
    if (mode == 'dynamic') {
      final group = (profile['proxyGroupName'] ?? '').toString().trim();
      return '动态分组 · ${group.isEmpty ? '全部代理分组' : group}';
    }
    if (mode == 'local') return '本地代理配置';
    final proxyId = (profile['proxyId'] ?? '').toString().trim();
    if (proxyId.isNotEmpty) {
      final vg = _virtualGroups.where(
        (g) => (g['groupId'] ?? '').toString() == proxyId,
      );
      if (vg.isNotEmpty) {
        return '虚拟分组 · ${(vg.first['groupName'] ?? proxyId).toString()}';
      }
      final found = _proxies.where(
        (p) => (p['proxyId'] ?? '').toString() == proxyId,
      );
      if (found.isNotEmpty) {
        return (found.first['proxyName'] ?? proxyId).toString();
      }
    }
    final config = (profile['proxyConfig'] ?? '').toString();
    if (config == 'direct://' || config.isEmpty) return '直连';
    return (profile['proxyName'] ?? profile['proxyId'] ?? '代理').toString();
  }

  Widget _profileProxyBadgeRow(Map<String, dynamic> profile) {
    final bindErr = (profile['proxyBindError'] ?? '').toString().trim();
    final proxyId = (profile['proxyId'] ?? '').toString().trim();
    final profileId = (profile['profileId'] ?? '').toString().trim();
    final key = proxyId.isNotEmpty ? proxyId : profileId;
    final lat = _proxyLatencyMs[key];
    final err = _proxyLatencyError[key];
    final label = _profileProxyLabel(profile);
    final Widget? badge = bindErr.isNotEmpty
        ? const PrismBadge(label: '需重选', tone: PrismTone.danger)
        : lat != null
        ? PrismBadge(
            label: '${lat}ms',
            tone: lat < 200
                ? PrismTone.success
                : lat < 500
                ? PrismTone.warning
                : PrismTone.danger,
          )
        : (err != null && err.isNotEmpty)
        ? const PrismBadge(label: '测速失败', tone: PrismTone.danger)
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '代理：$label',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: prism.AppTextStyle.caption1
                .of(context)
                .copyWith(
                  color: bindErr.isNotEmpty
                      ? PrismToneColors.of(context, PrismTone.danger).fg
                      : prism.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        if (badge != null) ...[const SizedBox(width: 10), badge],
      ],
    );
  }

  String _profileCoreLabel(Map<String, dynamic> profile) {
    final id = _resolvedCoreId(profile);
    final core = _cores.where((item) => item['coreId']?.toString() == id);
    if (core.isNotEmpty) return (core.first['coreName'] ?? id).toString();
    return id.isEmpty ? '使用默认内核' : id;
  }

  Widget _profileMetadata(Map<String, dynamic> profile) {
    final launchCode = (profile['launchCode'] ?? '').toString().trim();
    final keywords = (profile['keywords'] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList();
    final style = TextStyle(
      fontSize: 11,
      color: prism.Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            '内核：${_profileCoreLabel(profile)}',
            if (launchCode.isNotEmpty) '启动码：$launchCode',
          ].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        if (keywords.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('关键字：', style: style),
              for (final keyword in keywords.take(3))
                PrismChip(
                  label: Text(keyword, style: style),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: keyword));
                    if (mounted) showPrismNotice(context, '关键字已复制');
                  },
                ),
              if (keywords.length > 3)
                Text('+${keywords.length - 3}', style: style),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _copyLaunchCode(Map<String, dynamic> profile) async {
    final code = (profile['launchCode'] ?? '').toString().trim();
    if (code.isEmpty) {
      if (mounted) showPrismNotice(context, '此实例尚未设置启动码');
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showPrismNotice(context, '启动码已复制');
  }

  void _toggleViewMode() {
    setState(() => _viewMode = _viewMode == 'list' ? 'card' : 'list');
    AppBridge.writeStorage('browser:viewMode', _viewMode);
  }

  void _persistFilters() {
    AppBridge.writeStorage(
      'browser:filters',
      jsonEncode({
        'keyword': _query,
        'status': _statusFilter == 'all' ? '' : _statusFilter,
        'proxyId': _proxyFilter,
        'coreId': _coreFilter,
        'tags': _tagFilters.toList(),
        'groupId': _groupFilter,
      }),
    );
  }

  void _toggleFiltersCollapsed() {
    setState(() => _filtersCollapsed = !_filtersCollapsed);
    AppBridge.writeStorage(
      'browser:headerCollapsed',
      _filtersCollapsed.toString(),
    );
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _statusFilter = 'all';
      _coreFilter = '';
      _proxyFilter = '';
      _groupFilter = '';
      _tagFilters.clear();
    });
    _persistFilters();
  }

  String _resolvedCoreId(Map<String, dynamic> profile) {
    final configuredId = (profile['coreId'] ?? '').toString().trim();
    if (configuredId.isNotEmpty && configuredId.toLowerCase() != 'default') {
      return configuredId;
    }
    final defaultCore = _cores.where((core) => core['isDefault'] == true);
    return (defaultCore.isNotEmpty
                ? defaultCore.first
                : (_cores.isEmpty ? null : _cores.first))?['coreId']
            ?.toString() ??
        '';
  }

  String _normalizeSearch(String value) => value.trim().toLowerCase();

  String _normalizeCompactSearch(String value) =>
      _normalizeSearch(value).replaceAll(RegExp(r'[\s_-]+'), '');

  bool _matchesProfileSearch(Map<String, dynamic> profile, String query) {
    final normalized = _normalizeSearch(query);
    if (normalized.isEmpty) return true;
    final compact = _normalizeCompactSearch(normalized);
    final values = [
      profile['profileName'],
      profile['launchCode'],
      profile['profileId'],
      profile['userDataDir'],
      profile['proxyId'],
      profile['proxyBindName'],
      profile['proxyBindSourceUrl'],
      profile['groupId'],
      ...(profile['tags'] as List? ?? const []),
      ...(profile['keywords'] as List? ?? const []),
    ];
    return values.any((value) {
      final text = _normalizeSearch('$value');
      return text.contains(normalized) ||
          _normalizeCompactSearch(text).contains(compact);
    });
  }

  int _naturalCompare(String left, String right) {
    final a = RegExp(r'\d+|\D+').allMatches(left.toLowerCase());
    final b = RegExp(r'\d+|\D+').allMatches(right.toLowerCase());
    final count = a.length < b.length ? a.length : b.length;
    for (var index = 0; index < count; index++) {
      final partA = a.elementAt(index).group(0)!;
      final partB = b.elementAt(index).group(0)!;
      final numberA = int.tryParse(partA);
      final numberB = int.tryParse(partB);
      final comparison = numberA != null && numberB != null
          ? numberA.compareTo(numberB)
          : partA.compareTo(partB);
      if (comparison != 0) return comparison;
    }
    return a.length.compareTo(b.length);
  }

  Widget _profileGridCard(Map<String, dynamic> profile, {int index = 0}) {
    final id = (profile['profileId'] ?? '').toString();
    final name = (profile['profileName'] ?? '未命名实例').toString();
    final running = profile['running'] == true;
    final tags = (profile['tags'] as List? ?? [])
        .map((tag) => tag.toString())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final busy = _busyProfile == id;
    return PrismHoverCard(
      staggerIndex: index.clamp(0, 6),
      staggerDelay: const Duration(milliseconds: 35),
      radius: prism.AppCorner.xl,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              prism.Checkbox(
                value: _selectedProfileIds.contains(id),
                onChanged: (selected) => setState(() {
                  if (selected == true) {
                    _selectedProfileIds.add(id);
                  } else {
                    _selectedProfileIds.remove(id);
                  }
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.headline.of(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PrismPopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (action) {
                  if (action == 'detail') widget.onOpenDetails?.call(id);
                  if (action == 'restart') _restartProfile(profile);
                  if (action == 'edit') _editProfile(profile);
                  if (action == 'copy') _copyProfile(profile);
                  if (action == 'code') _editLaunchCode(profile);
                  if (action == 'copy-code') _copyLaunchCode(profile);
                  if (action == 'keywords') _editProfileKeywords(profile);
                  if (action == 'extensions') {
                    _configureProfileExtensions(profile);
                  }
                  if (action == 'data-dir') _openProfileDataDir(profile);
                  if (action == 'export') _exportProfiles([id]);
                  if (action == 'delete') _deleteProfile(profile);
                  if (action == 'change-proxy') _pickProfileProxy(profile);
                  if (action == 'test-proxy') _testProfileProxy(profile);
                },
                itemBuilder: (_) => [
                  const PrismMenuItem(value: 'detail', child: Text('查看详情')),
                  const PrismMenuItem(
                    value: 'change-proxy',
                    child: Text('切换代理'),
                  ),
                  PrismMenuItem(
                    value: 'test-proxy',
                    child: Text(
                      _testingProxyIds.contains(id) ? '代理测试中…' : '测试代理',
                    ),
                  ),
                  const PrismMenuItem(value: 'restart', child: Text('重启实例')),
                  const PrismMenuItem(value: 'edit', child: Text('编辑实例')),
                  const PrismMenuItem(value: 'copy', child: Text('复制配置')),
                  const PrismMenuItem(value: 'code', child: Text('管理启动码')),
                  const PrismMenuItem(value: 'copy-code', child: Text('复制启动码')),
                  const PrismMenuItem(value: 'keywords', child: Text('管理关键字')),
                  const PrismMenuItem(
                    value: 'extensions',
                    child: Text('配置实例插件'),
                  ),
                  const PrismMenuItem(value: 'data-dir', child: Text('打开数据目录')),
                  const PrismMenuItem(value: 'export', child: Text('导出实例')),
                  const PrismMenuItem(
                    value: 'delete',
                    danger: true,
                    child: Text('移入回收站'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _profileProxyBadgeRow(profile),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        for (final tag in tags.take(4))
                          PrismBadge(label: tag, tone: PrismTone.info),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  _profileMetadata(profile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RunningStatus(
                  running: running,
                  busy: busy,
                  debugReady: profile['debugReady'] != false,
                  lastError: (profile['lastError'] ?? '').toString(),
                  markerCode: (profile['windowMarkerCode'] ?? '').toString(),
                ),
              ),
              const SizedBox(width: 8),
              PrismTonalButton.icon(
                onPressed: busy ? null : () => _toggleProfile(profile),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 15,
                        child: PrismProgressIndicator(size: 15),
                      )
                    : PrismGlyph(
                        running ? AntGlyphs.stop : AntGlyphs.play,
                        size: 16,
                      ),
                child: Text(running ? '关闭' : '启动'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _warmProfileProxy(Map<String, dynamic> profile) async {
    final proxyId = (profile['proxyId'] ?? '').toString();
    final proxyConfig = (profile['proxyConfig'] ?? '').toString();
    if (proxyId.isEmpty && proxyConfig.isEmpty) return;
    try {
      await AppBridge.call('BrowserProxyWarmupBridgeWithConfig', [
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
      final result = await AppBridge.call('BrowserInstanceRestart', [id]);
      await _reload();
      if (result is Map && mounted) {
        final warning = (result['runtimeWarning'] ?? '').toString().trim();
        if (warning.isNotEmpty) {
          showPrismNotice(context, '实例已重启（提示：$warning）');
        }
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, ('重启失败：$error').toString());
      }
    } finally {
      if (mounted) setState(() => _busyProfile = null);
    }
  }

  Future<void> _manageGroups() async {
    final name = TextEditingController();
    var parentId = '';
    try {
      await showPrismDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: const Text('实例分组'),
            content: SizedBox(
              width: 460,
              height: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: PrismTextField(
                          controller: name,
                          decoration: const PrismInputDecoration(
                            labelText: '新分组名称',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 150,
                        child: PrismDropdownField<String>(
                          initialValue: parentId,
                          decoration: const PrismInputDecoration(
                            labelText: '上级分组',
                          ),
                          items: [
                            const PrismDropdownItem(
                              value: '',
                              child: Text('顶层分组'),
                            ),
                            for (final g in _groups)
                              PrismDropdownItem(
                                value: (g['groupId'] ?? '').toString(),
                                child: Text((g['groupName'] ?? '').toString()),
                              ),
                          ],
                          onChanged: (v) => setDialog(() => parentId = v ?? ''),
                        ),
                      ),
                      const SizedBox(width: 6),
                      prism.IconButton(
                        tooltip: '新建分组',
                        onPressed: () async {
                          if (name.text.trim().isEmpty) return;
                          try {
                            await AppBridge.call('CreateGroup', [
                              {
                                'groupName': name.text.trim(),
                                'parentId': parentId,
                                'sortOrder': _groups.length,
                              },
                            ]);
                            name.clear();
                            final groups = await AppBridge.call('ListGroups');
                            _groups = (groups as List? ?? [])
                                .whereType<Map>()
                                .map((row) => Map<String, dynamic>.from(row))
                                .toList();
                            if (!context.mounted) return;
                            setDialog(() {});
                          } catch (error) {
                            if (context.mounted) {
                              showPrismNotice(context, error.toString());
                            }
                          }
                        },
                        icon: const PrismGlyph(AntGlyphs.add, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _groups.isEmpty
                        ? const PrismEmptyState(
                            title: '暂无实例分组',
                            glyph: AntGlyphs.folder,
                          )
                        : ListView(
                            children: [
                              for (final group in _groups)
                                PrismListTile(
                                  leading: const PrismGlyph(
                                    AntGlyphs.folder,
                                    size: 18,
                                  ),
                                  title: Text(
                                    '${(group['parentId'] ?? '').toString().isNotEmpty ? '└ ' : ''}${(group['groupName'] ?? '').toString()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${group['instanceCount'] ?? 0} 个实例',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: PrismPopupMenuButton<String>(
                                    onSelected: (action) async {
                                      final groupId = (group['groupId'] ?? '')
                                          .toString();
                                      var mutated = false;
                                      if (action == 'rename') {
                                        final renameController =
                                            TextEditingController(
                                          text: (group['groupName'] ?? '')
                                              .toString(),
                                        );
                                        String? next;
                                        try {
                                          next = await showPrismDialog<String>(
                                            context: context,
                                            useRootNavigator: false,
                                            builder: (dialogContext) =>
                                                PrismDialog(
                                              title: const Text('重命名分组'),
                                              content: PrismTextField(
                                                controller: renameController,
                                              ),
                                              actions: [
                                                prism.TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        dialogContext,
                                                      ),
                                                  child: const Text('取消'),
                                                ),
                                                prism.FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        dialogContext,
                                                        renameController.text
                                                            .trim(),
                                                      ),
                                                  child: const Text('保存'),
                                                ),
                                              ],
                                            ),
                                          );
                                        } finally {
                                          renameController.dispose();
                                        }
                                        if (next != null && next.isNotEmpty) {
                                          try {
                                            await AppBridge.call(
                                              'UpdateGroup',
                                              [
                                                groupId,
                                                {
                                                  'groupName': next,
                                                  'parentId':
                                                      group['parentId'] ?? '',
                                                  'sortOrder':
                                                      group['sortOrder'] ?? 0,
                                                },
                                              ],
                                            );
                                            mutated = true;
                                          } catch (error) {
                                            if (context.mounted) {
                                              showPrismNotice(
                                                context,
                                                error.toString(),
                                              );
                                            }
                                            return;
                                          }
                                        }
                                      } else {
                                        final yes =
                                            await showPrismConfirmDialog(
                                          context: context,
                                          title: '删除分组？',
                                          message: '分组内的实例会变为未分组。',
                                          confirmLabel: '删除',
                                          destructive: true,
                                        );
                                        if (yes) {
                                          try {
                                            await AppBridge.call(
                                              'DeleteGroup',
                                              [groupId],
                                            );
                                            mutated = true;
                                          } catch (error) {
                                            if (context.mounted) {
                                              showPrismNotice(
                                                context,
                                                error.toString(),
                                              );
                                            }
                                            return;
                                          }
                                        }
                                      }
                                      if (!mutated) return;
                                      try {
                                        final groups = await AppBridge.call(
                                          'ListGroups',
                                        );
                                        _groups = (groups as List? ?? [])
                                            .whereType<Map>()
                                            .map(
                                              (row) => Map<String, dynamic>.from(
                                                row,
                                              ),
                                            )
                                            .toList();
                                        await _reload();
                                        if (!context.mounted) return;
                                        setDialog(() {});
                                      } catch (error) {
                                        if (context.mounted) {
                                          showPrismNotice(
                                            context,
                                            error.toString(),
                                          );
                                        }
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PrismMenuItem(
                                        value: 'rename',
                                        child: Text('重命名'),
                                      ),
                                      PrismMenuItem(
                                        value: 'delete',
                                        danger: true,
                                        child: Text('删除'),
                                      ),
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
              prism.TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
    }
    if (mounted) await _reload();
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
    try {
      List<Map<String, dynamic>> cores = [];
    List<Map<String, dynamic>> proxies = [];
    List<Map<String, dynamic>> virtualGroups = [];
    String? optionsError;
    final navigator = Navigator.of(context, rootNavigator: true);
    final loadingDialog = showPrismDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const PrismDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 22, height: 22, child: PrismProgressIndicator()),
            SizedBox(width: 16),
            Flexible(child: Text('正在加载配置选项…')),
          ],
        ),
      ),
    );
    try {
      final result = await Future.wait([
        AppBridge.call('BrowserCoreList'),
        AppBridge.call('BrowserProxyList'),
        AppBridge.call('BrowserProxyVirtualGroupList'),
        AppBridge.call('GetBrowserSettings'),
      ]).timeout(const Duration(seconds: 5));
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
      optionsError = error.toString();
    } finally {
      if (navigator.mounted && navigator.canPop()) navigator.pop();
      await loadingDialog;
    }
    if (optionsError != null && mounted) {
      showPrismNotice(context, ('部分选项加载失败，仍可打开配置窗口：$optionsError').toString());
    }
    if (!mounted) return;
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
    var resolvedLocationSummary = '';
    List<Object?> formValues() => [
      name.text,
      userDataDir.text,
      memoryLimit.text,
      tags.text,
      keywords.text,
      fingerprintArgs.text,
      launchArgs.text,
      localProxyConfig.text,
      proxyGroupName.text,
      coreId,
      proxyId,
      restoreMode,
      proxyMode,
      groupId,
    ];

    final initialFormValues = jsonEncode(formValues());
    Future<void> cancelEdit(BuildContext dialogContext) async {
      if (jsonEncode(formValues()) == initialFormValues) {
        Navigator.pop(dialogContext, false);
        return;
      }
      final discard = await showPrismDialog<bool>(
        context: dialogContext,
        useRootNavigator: false,
        builder: (confirmContext) => PrismDialog(
          title: const Text('放弃未保存的更改？'),
          content: const Text('离开后，当前修改将不会保存。'),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(confirmContext, false),
              child: const Text('继续编辑'),
            ),
            prism.FilledButton(
              onPressed: () => Navigator.pop(confirmContext, true),
              child: const Text('放弃更改'),
            ),
          ],
        ),
      );
      if (discard == true && dialogContext.mounted) {
        Navigator.pop(dialogContext, false);
      }
    }

    final saved = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: Text(profile == null ? '新建浏览器实例' : '编辑实例'),
          content: SizedBox(
            width: 500,
            height: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                PrismTextField(
                  controller: name,
                  autofocus: true,
                  decoration: const PrismInputDecoration(labelText: '实例名称'),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: PrismTextField(
                        controller: userDataDir,
                        decoration: const PrismInputDecoration(
                          labelText: '用户数据目录（留空自动生成）',
                        ),
                      ),
                    ),
                    if (userDataDir.text.trim().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      prism.IconButton(
                        tooltip: '打开数据目录',
                        onPressed: () async {
                          try {
                            await AppBridge.call('OpenUserDataDir', [
                              userDataDir.text.trim(),
                            ]);
                          } catch (e) {
                            if (context.mounted) {
                              showPrismNotice(context, '打开目录失败：$e');
                            }
                          }
                        },
                        icon: const PrismGlyph(AntGlyphs.folder, size: 18),
                      ),
                    ],
                  ],
                ),
                PrismDropdownField<String>(
                  initialValue: coreId,
                  decoration: const PrismInputDecoration(labelText: '浏览器内核'),
                  items: [
                    for (final core in cores)
                      PrismDropdownItem(
                        value: core['coreId']?.toString(),
                        child: Text(
                          (core['coreName'] ?? core['coreId'] ?? '').toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialog(() => coreId = value),
                ),
                PrismDropdownField<String>(
                  initialValue:
                      _groups.any((group) => group['groupId'] == groupId)
                      ? groupId
                      : '',
                  decoration: const PrismInputDecoration(labelText: '实例分组'),
                  items: [
                    const PrismDropdownItem(value: '', child: Text('未分组')),
                    for (final group in _groups)
                      PrismDropdownItem(
                        value: group['groupId']?.toString(),
                        child: Text((group['groupName'] ?? '').toString()),
                      ),
                  ],
                  onChanged: (value) => setDialog(() => groupId = value ?? ''),
                ),
                PrismDropdownField<String>(
                  initialValue:
                      ['fixed', 'dynamic', 'local'].contains(proxyMode)
                      ? proxyMode
                      : 'fixed',
                  decoration: const PrismInputDecoration(labelText: '代理模式'),
                  items: const [
                    PrismDropdownItem(value: 'fixed', child: Text('固定代理')),
                    PrismDropdownItem(value: 'dynamic', child: Text('动态代理')),
                    PrismDropdownItem(value: 'local', child: Text('本地代理配置')),
                  ],
                  onChanged: (value) =>
                      setDialog(() => proxyMode = value ?? 'fixed'),
                ),
                if (proxyMode == 'fixed') ...[
                  if (proxyId != null &&
                      proxyId!.isNotEmpty &&
                      proxyId != '__direct__' &&
                      !proxies.any((p) => p['proxyId'] == proxyId) &&
                      !virtualGroups.any((g) => g['groupId'] == proxyId))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PrismBanner(
                        tone: PrismTone.danger,
                        message: '原绑定代理已失效（$proxyId），请重新选择。',
                      ),
                    ),
                  PrismDropdownField<String>(
                    initialValue:
                        proxies.any((proxy) => proxy['proxyId'] == proxyId) ||
                            virtualGroups.any(
                              (group) => group['groupId'] == proxyId,
                            )
                        ? proxyId
                        : null,
                    decoration: const PrismInputDecoration(labelText: '代理'),
                    items: [
                      for (final group in virtualGroups)
                        PrismDropdownItem(
                          value: group['groupId']?.toString(),
                          child: Text(
                            '虚拟分组：${group['groupName'] ?? ''}（${group['strategy'] == 'sticky' ? '代理保持' : '轮询'}）',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      for (final proxy in proxies)
                        PrismDropdownItem(
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
                ],
                if (proxyMode == 'dynamic') ...[
                  PrismDropdownField<String>(
                    initialValue: proxyGroupName.text.trim(),
                    decoration: const PrismInputDecoration(labelText: '动态代理分组'),
                    items: [
                      const PrismDropdownItem(value: '', child: Text('全部代理分组')),
                      ...{
                            ...proxies.map(
                              (proxy) => (proxy['groupName'] ?? '').toString(),
                            ),
                            ...virtualGroups.map(
                              (group) => (group['groupName'] ?? '').toString(),
                            ),
                            if (proxyGroupName.text.trim().isNotEmpty)
                              proxyGroupName.text.trim(),
                          }
                          .where((name) => name.trim().isNotEmpty)
                          .map(
                            (name) => PrismDropdownItem(
                              value: name,
                              child: Text(name),
                            ),
                          ),
                    ],
                    onChanged: (value) =>
                        setDialog(() => proxyGroupName.text = value ?? ''),
                  ),
                ],
                if (proxyMode == 'local')
                  PrismTextField(
                    controller: localProxyConfig,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const PrismInputDecoration(
                      labelText: '本地代理配置',
                      hintText: '例如 http://127.0.0.1:7890',
                    ),
                  ),
                PrismDropdownField<String>(
                  initialValue: restoreMode.isEmpty ? '' : restoreMode,
                  decoration: const PrismInputDecoration(
                    labelText: '恢复上次浏览器会话',
                  ),
                  items: const [
                    PrismDropdownItem(value: '', child: Text('使用系统默认')),
                    PrismDropdownItem(value: 'enabled', child: Text('开启')),
                    PrismDropdownItem(value: 'disabled', child: Text('关闭')),
                  ],
                  onChanged: (value) =>
                      setDialog(() => restoreMode = value ?? ''),
                ),
                PrismTextField(
                  controller: memoryLimit,
                  keyboardType: TextInputType.number,
                  decoration: const PrismInputDecoration(
                    labelText: '内存上限（MB，0 表示默认）',
                  ),
                ),
                PrismTextField(
                  controller: tags,
                  decoration: const PrismInputDecoration(labelText: '标签（逗号分隔）'),
                ),
                PrismTextField(
                  controller: keywords,
                  decoration: const PrismInputDecoration(
                    labelText: '搜索关键词（逗号分隔）',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: prism.OutlinedButton.icon(
                    onPressed: () => _editFingerprintArgs(fingerprintArgs),
                    icon: const PrismGlyph(AntGlyphs.tune, size: 16),
                    label: const Text('图形化指纹设置'),
                  ),
                ),
                PrismTextField(
                  controller: fingerprintArgs,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const PrismInputDecoration(
                    labelText: '指纹启动参数（每行一项）',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: prism.TextButton.icon(
                    onPressed:
                        resolvingLocation ||
                            proxyMode != 'fixed' ||
                            proxyId == null ||
                            proxyId!.isEmpty ||
                            proxyId == '__direct__' ||
                            virtualGroups.any((g) => g['groupId'] == proxyId)
                        ? null
                        : () async {
                            setDialog(() => resolvingLocation = true);
                            try {
                              final value = await AppBridge.call(
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
                                final loc =
                                    [
                                          value['country'],
                                          value['region'],
                                          value['city'],
                                        ]
                                        .where(
                                          (i) =>
                                              i != null &&
                                              i.toString().isNotEmpty,
                                        )
                                        .join(' / ');
                                final ip = (value['ip'] ?? '').toString();
                                setDialog(() {
                                  resolvedLocationSummary =
                                      '出口 ${ip.isEmpty ? '' : '$ip · '}$loc → 语言 ${value['lang'] ?? ''} / 时区 ${value['timezone'] ?? ''}';
                                });
                                if (context.mounted) {
                                  showPrismNotice(
                                    context,
                                    '已应用 ${value['lang'] ?? ''} / ${value['timezone'] ?? ''}',
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
                                showPrismNotice(context, error.toString());
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
                            child: PrismProgressIndicator(size: 16),
                          )
                        : const PrismGlyph(AntGlyphs.locationSearch, size: 16),
                    label: const Text('按代理出口设置语言和时区'),
                  ),
                ),
                if (resolvedLocationSummary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  PrismBanner(
                    tone: PrismTone.success,
                    message: resolvedLocationSummary,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    prism.TextButton.icon(
                      onPressed: () {
                        final args = fingerprintArgs.text
                            .split('\n')
                            .map((value) => value.trim())
                            .where((value) => value.isNotEmpty)
                            .toList();
                        _showFingerprintCapabilityAndMatrix(
                          profile?['profileId']?.toString() ?? '',
                          coreId ?? '',
                          args,
                        );
                      },
                      icon: const PrismGlyph(AntGlyphs.gridView, size: 16),
                      label: const Text('查看内核能力表'),
                    ),
                    if (profile != null) ...[
                      prism.TextButton.icon(
                        onPressed: () {
                          if (jsonEncode(formValues()) != initialFormValues) {
                            showPrismNotice(context, '请先保存当前修改后再运行指纹自测');
                            return;
                          }
                          _showFingerprintReport(
                            '指纹自测结果',
                            AppBridge.call('BrowserProfileFingerprintCheck', [
                              profile['profileId'],
                            ]),
                          );
                        },
                        icon: const PrismGlyph(AntGlyphs.factCheck, size: 16),
                        label: const Text('运行指纹自测'),
                      ),
                      prism.TextButton.icon(
                        onPressed: () async {
                          if (jsonEncode(formValues()) != initialFormValues) {
                            showPrismNotice(context, '请先保存当前修改后再打开检测页');
                            return;
                          }
                          try {
                            await AppBridge.call(
                              'BrowserInstanceOpenFingerprintCheck',
                              [profile['profileId']],
                            );
                            if (context.mounted) {
                              showPrismNotice(context, '已在浏览器中打开指纹检测页');
                            }
                          } catch (error) {
                            if (context.mounted) {
                              showPrismNotice(context, '打开检测页失败：$error');
                            }
                          }
                        },
                        icon: const PrismGlyph(AntGlyphs.openInNew, size: 16),
                        label: const Text('在浏览器打开检测页'),
                      ),
                    ],
                  ],
                ),
                PrismTextField(
                  controller: launchArgs,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const PrismInputDecoration(
                    labelText: '浏览器启动参数（每行一项）',
                  ),
                ),
                if (profile != null &&
                    (profile['lastLaunchArgs'] as List? ?? []).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '上次实际启动参数',
                    style: prism.AppTextStyle.footnote.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  PrismCodeSurface(
                    code: (profile['lastLaunchArgs'] as List).join('\n'),
                    maxHeight: 160,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => cancelEdit(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  showPrismNotice(context, '请填写实例名称');
                  return;
                }
                Navigator.pop(context, true);
              },
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
        final selectedVirtualGroup = virtualGroups.where(
          (group) => group['groupId'] == proxyId,
        );
        final fixedProxyId = selectedProxy.isNotEmpty
            ? selectedProxy.first['proxyId']
            : selectedVirtualGroup.isNotEmpty
            ? selectedVirtualGroup.first['groupId']
            : (profile?['proxyId'] ?? '');
        final fixedProxyConfig = selectedProxy.isNotEmpty
            ? selectedProxy.first['proxyConfig']
            : selectedVirtualGroup.isNotEmpty
            ? ''
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
          final validation = await AppBridge.call('ValidateProxyConfig', [
            config,
            proxyIdToValidate,
          ]);
          if (validation is Map && validation['supported'] == false) {
            throw StateError((validation['errorMsg'] ?? '代理配置无效').toString());
          }
        }
        await AppBridge.call(
          profile == null ? 'BrowserProfileCreate' : 'BrowserProfileUpdate',
          profile == null ? [input] : [profile['profileId'], input],
        );
        await _reload();
      } catch (error) {
        if (mounted) showPrismNotice(context, ('保存失败：$error').toString());
      } finally {
        if (mounted) setState(() => _busyProfile = null);
      }
    }
    } finally {
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
  }

  Future<void> _editFingerprintArgs(TextEditingController source) async {
    final args = source.text
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    String value(String prefix) {
      final match = args.where((item) => item.startsWith(prefix));
      return match.isEmpty ? '' : match.last.substring(prefix.length);
    }

    final controllers = <String, TextEditingController>{
      'seed': TextEditingController(text: value('--fingerprint=')),
      'brand': TextEditingController(text: value('--fingerprint-brand=')),
      'brandVersion': TextEditingController(
        text: value('--fingerprint-brand-version='),
      ),
      'platform': TextEditingController(text: value('--fingerprint-platform=')),
      'platformVersion': TextEditingController(
        text: value('--fingerprint-platform-version='),
      ),
      'language': TextEditingController(text: value('--lang=')),
      'acceptLanguage': TextEditingController(text: value('--accept-lang=')),
      'timezone': TextEditingController(text: value('--timezone=')),
      'windowSize': TextEditingController(text: value('--window-size=')),
      'cpu': TextEditingController(
        text: value('--fingerprint-hardware-concurrency='),
      ),
      'webrtc': TextEditingController(
        text: args.contains('--disable-non-proxied-udp')
            ? 'disable_non_proxied_udp'
            : value('--webrtc-ip-handling-policy='),
      ),
    };
    String noiseValue(String canonical, String legacy) {
      if (args.contains(canonical) || args.contains(legacy)) return '1';
      for (final item in args.reversed) {
        if (item.startsWith('$canonical='))
          return item.substring(canonical.length + 1);
        if (item.startsWith('$legacy='))
          return item.substring(legacy.length + 1);
      }
      return '';
    }

    var canvasNoise = noiseValue(
      '--fingerprinting-canvas-image-data-noise',
      '--fingerprint-canvas-noise',
    );
    var rectNoise = noiseValue(
      '--fingerprinting-client-rects-noise',
      '--fingerprint-client-rects-noise',
    );
    final disableSpoofing = <String>{};
    for (final arg in args.where(
      (item) => item.startsWith('--disable-spoofing='),
    )) {
      disableSpoofing.addAll(
        arg.substring('--disable-spoofing='.length).split(','),
      );
    }
    final recognized = [
      '--fingerprint=',
      '--fingerprint-brand=',
      '--fingerprint-brand-version=',
      '--fingerprint-platform=',
      '--fingerprint-platform-version=',
      '--lang=',
      '--accept-lang=',
      '--timezone=',
      '--window-size=',
      '--fingerprint-hardware-concurrency=',
      '--webrtc-ip-handling-policy=',
      '--fingerprinting-canvas-image-data-noise',
      '--fingerprinting-client-rects-noise',
      '--fingerprint-canvas-noise=',
      '--fingerprint-client-rects-noise=',
      '--disable-spoofing=',
    ];
    final unknownArgs = args.where((arg) {
      if (arg == '--disable-non-proxied-udp') return false;
      return !recognized.any((prefix) => arg.startsWith(prefix));
    }).toList();
    final result = await showPrismDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          Widget field(String key, String label, {String? hint}) =>
              PrismTextField(
                controller: controllers[key],
                decoration: PrismInputDecoration(
                  labelText: label,
                  hintText: hint,
                ),
              );
          Widget toggle(String label, String key, Set<String> values) =>
              SizedBox(
                width: 160,
                child: Row(
                  children: [
                    prism.Checkbox(
                      value: values.contains(key),
                      onChanged: (enabled) => setDialog(() {
                        if (enabled == true) {
                          values.add(key);
                        } else {
                          values.remove(key);
                        }
                      }),
                    ),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
          void applyPreset({
            required String brand,
            required String platform,
            required String platformVersion,
            required String language,
            required String timezone,
            required String resolution,
            required String cpu,
          }) {
            controllers['seed']!.text =
                '${DateTime.now().microsecondsSinceEpoch % 2147483647 + 1}';
            controllers['brand']!.text = brand;
            controllers['brandVersion']!.clear();
            controllers['platform']!.text = platform;
            controllers['platformVersion']!.text = platformVersion;
            controllers['language']!.text = language;
            final base = language.split(RegExp('[-_]')).first;
            controllers['acceptLanguage']!.text = language == base
                ? language
                : '$language,$base';
            controllers['timezone']!.text = timezone;
            controllers['windowSize']!.text = resolution;
            controllers['cpu']!.text = cpu;
            controllers['webrtc']!.text = 'disable_non_proxied_udp';
            canvasNoise = '1';
            rectNoise = '1';
          }

          return PrismDialog(
            title: const Text('图形化指纹设置'),
            content: SizedBox(
              width: 540,
              height: 600,
              child: ListView(
                children: [
                  const Text('快速预设'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      prism.TextButton(
                        onPressed: () => setDialog(
                          () => applyPreset(
                            brand: 'Chrome',
                            platform: 'windows',
                            platformVersion: '10.0.0',
                            language: 'en-US',
                            timezone: 'America/New_York',
                            resolution: '1920,1080',
                            cpu: '8',
                          ),
                        ),
                        child: const Text('美国 Windows Chrome'),
                      ),
                      prism.TextButton(
                        onPressed: () => setDialog(
                          () => applyPreset(
                            brand: 'Chrome',
                            platform: 'macos',
                            platformVersion: '15.2.0',
                            language: 'ja-JP',
                            timezone: 'Asia/Tokyo',
                            resolution: '1440,900',
                            cpu: '8',
                          ),
                        ),
                        child: const Text('日本 macOS Chrome'),
                      ),
                      prism.TextButton(
                        onPressed: () => setDialog(
                          () => applyPreset(
                            brand: 'Edge',
                            platform: 'windows',
                            platformVersion: '10.0.0',
                            language: 'en-GB',
                            timezone: 'Europe/London',
                            resolution: '1920,1080',
                            cpu: '8',
                          ),
                        ),
                        child: const Text('英国 Windows Edge'),
                      ),
                      prism.TextButton(
                        onPressed: () => setDialog(
                          () => applyPreset(
                            brand: 'Chrome',
                            platform: 'windows',
                            platformVersion: '10.0.0',
                            language: 'zh-CN',
                            timezone: 'Asia/Shanghai',
                            resolution: '1920,1080',
                            cpu: '8',
                          ),
                        ),
                        child: const Text('Windows Chrome 办公'),
                      ),
                      prism.TextButton(
                        onPressed: () => setDialog(
                          () => applyPreset(
                            brand: 'Chrome',
                            platform: 'windows',
                            platformVersion: '10.0.0',
                            language: 'en-US',
                            timezone: 'America/New_York',
                            resolution: '2560,1440',
                            cpu: '16',
                          ),
                        ),
                        child: const Text('Windows Chrome 游戏主机'),
                      ),
                      prism.TextButton(
                        onPressed: () => setDialog(
                          () => applyPreset(
                            brand: 'Chrome',
                            platform: 'macos',
                            platformVersion: '15.2.0',
                            language: 'zh-CN',
                            timezone: 'Asia/Shanghai',
                            resolution: '2560,1440',
                            cpu: '10',
                          ),
                        ),
                        child: const Text('macOS Chrome 设计师'),
                      ),
                      prism.TextButton(
                        onPressed: () => setDialog(
                          () => applyPreset(
                            brand: 'Chrome',
                            platform: 'windows',
                            platformVersion: '10.0.0',
                            language: 'en-SG',
                            timezone: 'Asia/Singapore',
                            resolution: '1920,1080',
                            cpu: '8',
                          ),
                        ),
                        child: const Text('新加坡 Windows Chrome'),
                      ),
                      prism.TextButton(
                        onPressed: () => setDialog(
                          () => applyPreset(
                            brand: 'Chrome',
                            platform: 'linux',
                            platformVersion: '',
                            language: 'de-DE',
                            timezone: 'Europe/Berlin',
                            resolution: '1920,1080',
                            cpu: '12',
                          ),
                        ),
                        child: const Text('德国 Linux Chrome'),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: field('seed', '指纹种子', hint: '留空则按实例自动生成'),
                      ),
                      const SizedBox(width: 8),
                      prism.TextButton.icon(
                        onPressed: () async {
                          final yes = await showPrismDialog<bool>(
                            context: context,
                            useRootNavigator: false,
                            builder: (c) => PrismDialog(
                              title: const Text('重新生成指纹种子？'),
                              content: const Text('修改种子会改变该实例的浏览器指纹标识。'),
                              actions: [
                                prism.TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('取消'),
                                ),
                                prism.FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('重新生成'),
                                ),
                              ],
                            ),
                          );
                          if (yes == true) {
                            setDialog(
                              () => controllers['seed']!.text =
                                  '${DateTime.now().microsecondsSinceEpoch % 2147483647 + 1}',
                            );
                          }
                        },
                        icon: const PrismGlyph(AntGlyphs.refresh, size: 16),
                        label: const Text('重新生成'),
                      ),
                    ],
                  ),
                  field(
                    'brand',
                    '浏览器品牌',
                    hint: 'Chrome / Edge / Opera / Vivaldi',
                  ),
                  field('brandVersion', '浏览器版本'),
                  field('platform', '系统平台', hint: 'windows / macos / linux'),
                  field('platformVersion', '系统版本'),
                  field('language', '语言', hint: 'zh-CN / en-US / ja-JP'),
                  field('acceptLanguage', '语言列表', hint: 'en-US,en'),
                  field('timezone', '时区', hint: 'Asia/Shanghai'),
                  field('windowSize', '窗口大小', hint: '1920,1080'),
                  field('cpu', 'CPU 核心数', hint: '1 到 128'),
                  field(
                    'webrtc',
                    'WebRTC 策略',
                    hint: 'disable_non_proxied_udp / default_public_interface_only',
                  ),
                  const SizedBox(height: 8),
                  const Text('噪声开关（留空使用内核默认）'),
                  PrismDropdownField<String>(
                    initialValue: canvasNoise,
                    decoration: const PrismInputDecoration(
                      labelText: 'Canvas 噪声',
                    ),
                    items: const [
                      PrismDropdownItem(value: '', child: Text('默认')),
                      PrismDropdownItem(value: '1', child: Text('开启')),
                      PrismDropdownItem(value: '0', child: Text('关闭')),
                    ],
                    onChanged: (value) =>
                        setDialog(() => canvasNoise = value ?? ''),
                  ),
                  PrismDropdownField<String>(
                    initialValue: rectNoise,
                    decoration: const PrismInputDecoration(
                      labelText: 'ClientRects 噪声',
                    ),
                    items: const [
                      PrismDropdownItem(value: '', child: Text('默认')),
                      PrismDropdownItem(value: '1', child: Text('开启')),
                      PrismDropdownItem(value: '0', child: Text('关闭')),
                    ],
                    onChanged: (value) =>
                        setDialog(() => rectNoise = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  const Text('排除伪装项'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      toggle('字体', 'font', disableSpoofing),
                      toggle('音频', 'audio', disableSpoofing),
                      toggle('Canvas', 'canvas', disableSpoofing),
                      toggle('ClientRects', 'clientrects', disableSpoofing),
                      toggle('GPU', 'gpu', disableSpoofing),
                    ],
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
                onPressed: () {
                  final next = <String>[];
                  void add(String key, String flag) {
                    final text = controllers[key]!.text.trim();
                    if (text.isNotEmpty) next.add('$flag$text');
                  }

                  add('seed', '--fingerprint=');
                  add('brand', '--fingerprint-brand=');
                  add('brandVersion', '--fingerprint-brand-version=');
                  add('platform', '--fingerprint-platform=');
                  add('platformVersion', '--fingerprint-platform-version=');
                  final language = controllers['language']!.text.trim();
                  final acceptLanguage = controllers['acceptLanguage']!.text
                      .trim();
                  if (language.isNotEmpty) {
                    next.add('--lang=$language');
                    final base = language.split(RegExp('[-_]')).first;
                    next.add(
                      '--accept-lang=${acceptLanguage.isNotEmpty
                          ? acceptLanguage
                          : language == base
                          ? language
                          : '$language,$base'}',
                    );
                  } else if (acceptLanguage.isNotEmpty) {
                    next.add('--accept-lang=$acceptLanguage');
                  }
                  add('timezone', '--timezone=');
                  add('windowSize', '--window-size=');
                  add('cpu', '--fingerprint-hardware-concurrency=');
                  final webrtc = controllers['webrtc']!.text.trim();
                  if (webrtc == 'disable_non_proxied_udp') {
                    next.add('--disable-non-proxied-udp');
                  } else if (webrtc.isNotEmpty) {
                    next.add('--webrtc-ip-handling-policy=$webrtc');
                  }
                  if (canvasNoise.isNotEmpty) {
                    next.add(
                      '--fingerprinting-canvas-image-data-noise${canvasNoise == '0' ? '=0' : ''}',
                    );
                  }
                  if (rectNoise.isNotEmpty) {
                    next.add(
                      '--fingerprinting-client-rects-noise${rectNoise == '0' ? '=0' : ''}',
                    );
                  }
                  if (disableSpoofing.isNotEmpty) {
                    next.add('--disable-spoofing=${disableSpoofing.join(',')}');
                  }
                  Navigator.pop(context, [...next, ...unknownArgs]);
                },
                child: const Text('应用'),
              ),
            ],
          );
        },
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (result != null) source.text = result.join('\n');
  }

  Future<void> _showFingerprintCapabilityAndMatrix(
    String profileId,
    String coreId,
    List<String> args,
  ) async {
    try {
      final results = await Future.wait<dynamic>([
        AppBridge.call('BrowserProfileFingerprintCapabilityTable', [
          profileId,
          coreId,
        ]),
        AppBridge.call('BrowserProfileFingerprintMatrix', [
          profileId,
          coreId,
          args,
        ]),
      ]);
      if (!mounted) return;
      final table = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : <String, dynamic>{};
      final matrix = results[1] is Map
          ? Map<String, dynamic>.from(results[1] as Map)
          : <String, dynamic>{};
      final matrixItems =
          ((matrix['items'] ?? matrix['rows'] ?? matrix['checks']) as List? ??
                  const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

      await showFingerprintCapabilityDialog(
        context: context,
        title: '内核能力表与参数适配矩阵',
        kernelBadgePrefix: '当前内核',
        table: table,
        extraSections: [
          if (matrixItems.isNotEmpty)
            PrismSectionCard(
              title: '当前配置参数检测结论',
              glyph: AntGlyphs.factCheck,
              child: Column(
                children: [
                  for (var i = 0; i < matrixItems.length; i++) ...[
                    if (i > 0) const prism.Divider(height: 1),
                    Builder(
                      builder: (context) {
                        final row = matrixItems[i];
                        final status = (row['status'] ?? '').toString();
                        final tone = status == 'match' || status == 'ok'
                            ? PrismTone.success
                            : status == 'compatible' || status == 'warn'
                            ? PrismTone.warning
                            : PrismTone.danger;
                        return PrismListTile(
                          dense: true,
                          title: Text(
                            (row['label'] ??
                                    row['key'] ??
                                    row['name'] ??
                                    '')
                                .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '配置：${row['configured'] ?? row['expected'] ?? '—'}  →  实际：${row['actual'] ?? row['value'] ?? '—'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: PrismBadge(
                            label: status.isEmpty ? '已检' : status,
                            tone: tone,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    }
  }

  Future<void> _showFingerprintReport(
    String title,
    Future<dynamic> request,
  ) async {
    try {
      final value = await request;
      if (!mounted) return;
      final items = value is Map
          ? ((value['items'] ?? value['rows'] ?? value['checks']) as List? ??
                const [])
          : const [];
      final text = const JsonEncoder.withIndent('  ').convert(value);
      await showPrismDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => PrismDialog(
          title: Text(title),
          content: SizedBox(
            width: 680,
            height: 520,
            child: items.isNotEmpty
                ? ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const prism.Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = items[index] is Map
                          ? Map<String, dynamic>.from(items[index] as Map)
                          : <String, dynamic>{};
                      final status = (row['status'] ?? '').toString();
                      final tone = status == 'match' || status == 'ok'
                          ? PrismTone.success
                          : status == 'compatible' || status == 'warn'
                          ? PrismTone.warning
                          : PrismTone.danger;
                      return PrismListTile(
                        dense: true,
                        title: Text(
                          (row['label'] ?? row['key'] ?? row['name'] ?? '')
                              .toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '配置：${row['configured'] ?? row['expected'] ?? '—'}  →  实际：${row['actual'] ?? row['value'] ?? '—'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PrismBadge(
                          label: status.isEmpty ? '已检' : status,
                          tone: tone,
                        ),
                      );
                    },
                  )
                : PrismCodeSurface(code: text, language: 'json'),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, error.toString());
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
    final result = await showPrismDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('复制实例配置'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrismTextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const PrismInputDecoration(labelText: '新实例名称'),
                ),
                PrismDropdownField<String>(
                  initialValue: mode,
                  decoration: const PrismInputDecoration(labelText: '复制方式'),
                  items: const [
                    PrismDropdownItem(value: 'regular', child: Text('直接复制')),
                    PrismDropdownItem(
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
                    PrismCheckboxTile(
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
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
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
        await AppBridge.call('BrowserProfileCopyWithOptions', [
          profile['profileId'],
          controller.text.trim(),
          result,
        ]);
        await _reload();
      } catch (error) {
        if (mounted) showPrismNotice(context, (error.toString()).toString());
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
    var regenerated = false;
    try {
      final value = await AppBridge.call('BrowserProfileGetCode', [id]);
      if (value is String && value.isNotEmpty) code.text = value;
    } catch (_) {}
    final nextCode = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('管理启动码'),
          content: PrismTextField(
            controller: code,
            decoration: const PrismInputDecoration(
              labelText: '启动码',
              helperText: '启动码用于通过接口查找并启动此实例。',
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () async {
                try {
                  final value = await AppBridge.call(
                    'BrowserProfileRegenerateCode',
                    [id],
                  );
                  setDialog(() {
                    code.text = (value ?? '').toString();
                    regenerated = true;
                  });
                } catch (error) {
                  if (context.mounted) {
                    showPrismNotice(context, (error.toString()).toString());
                  }
                }
              },
              child: const Text('重新生成'),
            ),
            prism.TextButton(
              onPressed: () async {
                if (code.text.trim().isEmpty) return;
                await Clipboard.setData(ClipboardData(text: code.text.trim()));
                if (context.mounted) showPrismNotice(context, '启动码已复制');
              },
              child: const Text('复制'),
            ),
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () {
                final trimmed = code.text.trim();
                if (trimmed.isEmpty ||
                    trimmed.length < 4 ||
                    trimmed.length > 32 ||
                    !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(trimmed)) {
                  showPrismNotice(context, '启动码需为 4–32 位字母、数字、下划线或短横线');
                  return;
                }
                Navigator.pop(context, trimmed);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (nextCode == null) {
      code.dispose();
      if (regenerated) await _reload();
      return;
    }
    try {
      await AppBridge.call('BrowserProfileSetCode', [id, nextCode]);
      await _reload();
      if (mounted) {
        showPrismNotice(context, ('启动码已保存').toString());
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    } finally {
      code.dispose();
    }
  }

  Future<void> _editProfileKeywords(Map<String, dynamic> profile) async {
    final id = (profile['profileId'] ?? '').toString();
    if (id.isEmpty) return;
    final controllers = (profile['keywords'] as List? ?? [])
        .map((value) => TextEditingController(text: value.toString()))
        .toList();
    if (controllers.isEmpty) controllers.add(TextEditingController());
    final saved = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: Text('关键字 · ${profile['profileName'] ?? '实例'}'),
          content: SizedBox(
            width: 460,
            height: 390,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('关键字用于备注账号等信息，也可以在实例列表中搜索。'),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: controllers.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: controllers[index],
                              decoration: PrismInputDecoration(
                                labelText: '关键字 ${index + 1}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          prism.IconButton(
                            tooltip: '移除关键字',
                            onPressed: () => setDialog(() {
                              if (controllers.length == 1) {
                                controllers[index].clear();
                              } else {
                                controllers.removeAt(index).dispose();
                              }
                            }),
                            icon: const PrismGlyph(
                              AntGlyphs.removeCircle,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                prism.TextButton.icon(
                  onPressed: () =>
                      setDialog(() => controllers.add(TextEditingController())),
                  icon: const PrismGlyph(AntGlyphs.add, size: 16),
                  label: const Text('添加关键字'),
                ),
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final keywords = controllers
          .map((controller) => controller.text.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      try {
        await AppBridge.call('BrowserProfileSetKeywords', [id, keywords]);
        if (mounted) {
          setState(() {
            _profiles = _profiles
                .map(
                  (item) => item['profileId'] == id
                      ? {...item, 'keywords': keywords}
                      : item,
                )
                .toList();
          });
          showPrismNotice(context, '关键字已保存');
        }
      } catch (error) {
        if (mounted) showPrismNotice(context, '保存关键字失败：$error');
      }
    }
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  Future<void> _configureProfileExtensions(Map<String, dynamic> profile) async {
    final id = (profile['profileId'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final values = await Future.wait([
        AppBridge.call('BrowserExtensionList'),
        AppBridge.call('BrowserProfileExtensionGet', [id]),
      ]);
      final extensions = (values[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final settings = Map<String, dynamic>.from(values[1] as Map);
      var configured = settings['configured'] == true;
      final selectedIds = (settings['extensionIds'] as List? ?? [])
          .map((value) => value.toString())
          .toSet();
      final defaultCount = extensions
          .where(
            (item) => item['enabled'] == true && item['defaultInstall'] == true,
          )
          .length;
      if (!mounted) return;
      final result = await showPrismDialog<String>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: Text('插件配置 · ${profile['profileName'] ?? '实例'}'),
            content: SizedBox(
              width: 620,
              height: 500,
              child: Column(
                children: [
                  PrismSwitchTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('手动设置本实例'),
                    value: configured,
                    onChanged: (value) => setDialog(() => configured = value),
                  ),
                  if (!configured)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '当前继承默认安装的插件（共 $defaultCount 个）。开启手动设置后，可单独选择本实例使用的插件。',
                        ),
                      ),
                    ),
                  const prism.Divider(),
                  Expanded(
                    child: extensions.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('还没有安装任何插件包。'),
                                const SizedBox(height: 8),
                                prism.TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, 'manage'),
                                  child: const Text('去插件包管理安装'),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            children: [
                              for (final extension in extensions)
                                PrismCheckboxTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    (extension['name'] ??
                                            extension['extensionId'] ??
                                            '')
                                        .toString(),
                                  ),
                                  subtitle: Text(
                                    '${extension['extensionId'] ?? ''}${extension['version'] == null ? '' : ' · v${extension['version']}'}${extension['enabled'] == true ? '' : ' · 全局停用'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  value: selectedIds.contains(
                                    extension['extensionId'],
                                  ),
                                  onChanged: !configured
                                      ? null
                                      : (value) => setDialog(() {
                                          final extensionId =
                                              (extension['extensionId'] ?? '')
                                                  .toString();
                                          if (value == true) {
                                            selectedIds.add(extensionId);
                                          } else {
                                            selectedIds.remove(extensionId);
                                          }
                                        }),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('取消'),
              ),
              prism.FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      if (result == 'manage') {
        widget.onOpenExtensionManagement?.call();
      } else if (result == 'save') {
        await AppBridge.call('BrowserProfileExtensionSave', [
          id,
          selectedIds.toList(),
          configured,
        ]);
        if (mounted) showPrismNotice(context, '实例插件配置已保存；运行中的实例下次启动生效');
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '加载或保存实例插件配置失败：$error');
    }
  }

  Future<void> _openProfileDataDir(Map<String, dynamic> profile) async {
    final path = (profile['userDataDir'] ?? '').toString().trim();
    if (path.isEmpty) {
      showPrismNotice(context, '该实例没有用户数据目录');
      return;
    }
    try {
      await AppBridge.call('OpenUserDataDir', [path]);
    } catch (error) {
      if (mounted) showPrismNotice(context, '打开数据目录失败：$error');
    }
  }

  Future<void> _deleteProfile(Map<String, dynamic> profile) async {
    if (profile['running'] == true) {
      showPrismNotice(context, '请先关闭运行中的实例再移入回收站');
      return;
    }
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('移入回收站？'),
        destructive: true,
        content: Text((profile['profileName'] ?? '').toString()),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await AppBridge.call('BrowserProfileDelete', [profile['profileId']]);
        await _reload();
      } catch (error) {
        if (mounted) showPrismNotice(context, (error.toString()).toString());
      }
    }
  }

  Future<void> _importProfiles() async {
    try {
      final previewResult = await AppBridge.call(
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
      final confirmedActions = await showPrismDialog<List<Map<String, dynamic>>>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: Text('导入 ${preview['profileCount'] ?? profiles.length} 个实例'),
            content: SizedBox(
              width: 620,
              height: 460,
              child: profiles.isEmpty
                  ? const Center(child: Text('压缩包里没有实例'))
                  : ListView.separated(
                      itemCount: profiles.length,
                      separatorBuilder: (_, __) =>
                          const prism.Divider(height: 1),
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
                              PrismDropdownField<String>(
                                value: choices.contains(action['mode'])
                                    ? action['mode'] as String
                                    : 'new',
                                items: [
                                  const PrismDropdownItem(
                                    value: 'new',
                                    child: Text('新建为一个实例'),
                                  ),
                                  if (canOverwrite)
                                    const PrismDropdownItem(
                                      value: 'overwrite',
                                      child: Text('覆盖匹配到的实例'),
                                    ),
                                  const PrismDropdownItem(
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
                                PrismTextFormField(
                                  key: ValueKey('rename-$index'),
                                  initialValue: (action['profileName'] ?? '')
                                      .toString(),
                                  decoration: const PrismInputDecoration(
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
              prism.TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              prism.FilledButton(
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
          showPrismNotice(context, ('请填写重命名后的实例名称').toString());
        }
        return;
      }
      var password = '';
      if (preview['portableSessionAvailable'] == true) {
        final value = await _askPortableSessionPassword();
        if (value == null) return;
        password = value;
      }
      final result = await AppBridge.call(
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
        showPrismNotice(context, (message.toString()).toString());
      }
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    }
  }

  Future<String?> _askPortableSessionPassword() async {
    final password = TextEditingController();
    var errorText = '';
    final value = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('迁移登录态'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('输入导出时设置的密码；留空可跳过登录态迁移。'),
              PrismTextField(
                controller: password,
                obscureText: true,
                decoration: PrismInputDecoration(
                  labelText: '迁移密码（至少 8 个字符）',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
              ),
            ],
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('跳过'),
            ),
            prism.FilledButton(
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
      showPrismNotice(
        context,
        ('请先关闭运行中的实例再导出：${running.take(3).join('、')}').toString(),
      );
      return;
    }
    final password = TextEditingController();
    var passwordError = '';
    final exportPassword = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('导出实例'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('可设置密码，一并迁移实例的登录态 Cookie。'),
              PrismTextField(
                controller: password,
                obscureText: true,
                decoration: PrismInputDecoration(
                  labelText: '登录态迁移密码（至少 8 个字符）',
                  errorText: passwordError.isEmpty ? null : passwordError,
                ),
              ),
            ],
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('仅导出配置'),
            ),
            prism.FilledButton(
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
      final result = await AppBridge.call(
        'BrowserProfilePackageExportWithOptions',
        [
          ids,
          {'portableSessionPassword': exportPassword},
        ],
      );
      final value = Map<String, dynamic>.from(result as Map);
      if (mounted)
        showPrismNotice(
          context,
          ((value['portableSessionWarning'] ?? value['message'] ?? '实例导出已完成')
                  .toString())
              .toString(),
        );
      if (mounted) setState(() => _selectedProfileIds.clear());
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
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
      showPrismNotice(context, ('请先关闭运行中的实例再删除').toString());
      return;
    }
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('批量移入回收站？'),
        content: Text('将移入 ${ids.length} 个实例。'),
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
    if (confirmed != true) return;
    try {
      for (final id in ids) {
        await AppBridge.call('BrowserProfileDelete', [id]);
      }
      setState(() => _selectedProfileIds.clear());
      await _reload();
    } catch (error) {
      if (mounted) {
        showPrismNotice(context, (error.toString()).toString());
      }
    }
  }

  Future<void> _batchToggleProfiles(bool start) async {
    final rows = _profiles
        .where(
          (profile) =>
              _selectedProfileIds.contains(profile['profileId']) &&
              (profile['running'] == true) != start,
        )
        .toList();
    if (rows.isEmpty) return;
    setState(() => _busyProfile = '__batch__');
    var success = 0;
    var pending = 0;
    final errors = <String>[];
    try {
      for (final profile in rows) {
        final id = (profile['profileId'] ?? '').toString();
        final name = (profile['profileName'] ?? id).toString();
        try {
          if (start) await _warmProfileProxy(profile);
          final res = await AppBridge.call(
            start ? 'BrowserInstanceStart' : 'BrowserInstanceStop',
            [id],
          );
          if (res is! Map) {
            errors.add('$name：未返回实例状态');
          } else if (start && res['running'] != true) {
            errors.add('$name：实例未进入运行状态');
          } else if (start && res['debugReady'] == false) {
            pending++;
          } else if (start &&
              (res['debugPort'] is! num ||
                  (res['debugPort'] as num).toInt() <= 0)) {
            errors.add('$name：调试端口无效');
          } else if (!start && res['running'] != false) {
            errors.add('$name：实例仍在运行');
          } else {
            success++;
          }
        } catch (error) {
          errors.add('$name：$error');
        }
      }
      await _reload();
      if (mounted) {
        final parts = <String>[
          '成功 $success',
          if (pending > 0) '待就绪 $pending',
          if (errors.isNotEmpty) '失败 ${errors.length}',
        ];
        showPrismNotice(
          context,
          '${start ? '批量启动' : '批量关闭'}完成（${parts.join(' / ')}）${errors.isNotEmpty ? '：${errors.first}' : ''}',
        );
      }
    } finally {
      if (mounted) setState(() => _busyProfile = null);
    }
  }

  Future<void> _showTrash() async {
    List<Map<String, dynamic>> rows = [];
    try {
      final result = await AppBridge.call('BrowserProfileTrashList');
      rows = (result as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (error) {
      if (mounted) showPrismNotice(context, (error.toString()).toString());
      return;
    }
    if (!mounted) return;
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => PrismDialog(
          title: const Text('实例回收站'),
          content: SizedBox(
            width: 560,
            height: 420,
            child: rows.isEmpty
                ? const PrismEmptyState(
                    title: '回收站是空的',
                    glyph: AntGlyphs.delete,
                  )
                : ListView(
                    children: [
                      for (final row in rows)
                        Builder(
                          builder: (context) {
                            final rawDeleted = (row['deletedAt'] ?? '')
                                .toString();
                            final dt = DateTime.tryParse(rawDeleted)?.toLocal();
                            String fmt(DateTime d) =>
                                '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                            final sub = dt == null
                                ? rawDeleted
                                : '删除于 ${fmt(dt)} · 自动清理 ${fmt(dt.add(const Duration(days: 3)))}';
                            return PrismListTile(
                              title: Text(
                                (row['profileName'] ?? '未命名实例').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: prism.TonalButtonGroup(
                                size: prism.TonalButtonSize.section,
                                children: [
                                  prism.IconButton(
                                    tooltip: '恢复',
                                    onPressed: () async {
                                      try {
                                        await AppBridge.call(
                                          'BrowserProfileRestore',
                                          [row['profileId']],
                                        );
                                        rows.remove(row);
                                        if (dialogContext.mounted) {
                                          setDialog(() {});
                                        }
                                        await _reload();
                                      } catch (error) {
                                        if (dialogContext.mounted) {
                                          showPrismNotice(
                                            dialogContext,
                                            error.toString(),
                                          );
                                        }
                                      }
                                    },
                                    icon: const PrismGlyph(
                                      AntGlyphs.restore,
                                      size: 18,
                                    ),
                                  ),
                                  prism.IconButton(
                                    tooltip: '彻底删除',
                                    onPressed: () async {
                                      final yes = await showPrismConfirmDialog(
                                        context: dialogContext,
                                        title: '彻底删除实例？',
                                        message:
                                            '将永久删除该实例的配置、用户数据目录、快照、启动码与插件绑定，此操作无法撤销。',
                                        confirmLabel: '彻底删除',
                                        destructive: true,
                                      );
                                      if (!yes) return;
                                      try {
                                        await AppBridge.call(
                                          'BrowserProfilePermanentlyDelete',
                                          [row['profileId']],
                                        );
                                        rows.remove(row);
                                        if (!dialogContext.mounted) return;
                                        setDialog(() {});
                                      } catch (error) {
                                        if (dialogContext.mounted) {
                                          showPrismNotice(
                                            dialogContext,
                                            error.toString(),
                                          );
                                        }
                                      }
                                    },
                                    icon: const PrismGlyph(
                                      AntGlyphs.delete,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
            if (rows.isNotEmpty)
              prism.TextButton(
                onPressed: () async {
                  final yes = await showPrismConfirmDialog(
                    context: dialogContext,
                    title: '清理过期实例？',
                    message: '只会永久删除已超过保留期的实例。',
                    confirmLabel: '清理',
                  );
                  if (yes) {
                    try {
                      await AppBridge.call('BrowserProfileTrashCleanup');
                      final refreshed = await AppBridge.call(
                        'BrowserProfileTrashList',
                      );
                      rows = (refreshed as List? ?? [])
                          .whereType<Map>()
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList();
                      if (!dialogContext.mounted) return;
                      setDialog(() {});
                    } catch (error) {
                      if (dialogContext.mounted) {
                        showPrismNotice(dialogContext, error.toString());
                      }
                    }
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
    final runningCount = _profiles
        .where((profile) => profile['running'] == true)
        .length;
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
    final coreOptions = _cores
        .map((core) => (core['coreId'] ?? '').toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final proxyOptions = {
      ..._proxies.map((proxy) => (proxy['proxyId'] ?? '').toString()),
      ..._profiles.map((profile) => (profile['proxyId'] ?? '').toString()),
    }.where((value) => value.isNotEmpty).toSet().toList();
    final visible =
        _profiles.where((profile) {
          if (!_matchesProfileSearch(profile, _query)) return false;
          if (_statusFilter == 'running' && profile['running'] != true)
            return false;
          if (_statusFilter == 'stopped' && profile['running'] == true)
            return false;
          if (_tagFilters.isNotEmpty &&
              !(profile['tags'] as List? ?? []).any(
                (tag) => _tagFilters.contains(tag.toString()),
              ))
            return false;
          if (_coreFilter.isNotEmpty && _resolvedCoreId(profile) != _coreFilter)
            return false;
          final profileProxyId = (profile['proxyId'] ?? '').toString();
          final profileProxyConfig = (profile['proxyConfig'] ?? '').toString();
          if (_proxyFilter == '__none__' &&
              ((profile['proxyMode'] ?? '').toString() == 'dynamic' ||
                  profileProxyId.isNotEmpty ||
                  (profileProxyConfig.isNotEmpty &&
                      profileProxyConfig != 'direct://'))) {
            return false;
          }
          if (_proxyFilter.isNotEmpty &&
              _proxyFilter != '__none__' &&
              profileProxyId != _proxyFilter)
            return false;
          if (_groupFilter.isNotEmpty &&
              (_groupFilter == '__ungrouped__'
                  ? (profile['groupId'] ?? '').toString().isNotEmpty
                  : profile['groupId']?.toString() != _groupFilter))
            return false;
          return true;
        }).toList()..sort(
          (a, b) => _naturalCompare(
            (a['profileName'] ?? '').toString(),
            (b['profileName'] ?? '').toString(),
          ),
        );
    final visibleIds = visible
        .map((profile) => profile['profileId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final allVisibleSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selectedProfileIds.contains);
    final proxyBoundCount = _profiles
        .where(
          (p) =>
              '${p['proxyId'] ?? ''}'.trim().isNotEmpty ||
              '${p['proxyConfig'] ?? ''}'.trim().isNotEmpty,
        )
        .length;
    final activeFilterCount =
        (_statusFilter != 'all' ? 1 : 0) +
        (_coreFilter.isNotEmpty ? 1 : 0) +
        (_proxyFilter.isNotEmpty ? 1 : 0) +
        (_groupFilter.isNotEmpty ? 1 : 0) +
        _tagFilters.length;
    final hasActiveFilters = _query.isNotEmpty || activeFilterCount > 0;

    final kpiTiles = [
      PrismMetricTile(
        label: '全部实例',
        value: '${_profiles.length}',
        glyph: AntGlyphs.browser,
        tone: PrismTone.primary,
        onPressed: () {
          setState(() => _statusFilter = 'all');
          _persistFilters();
        },
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '运行中',
        value: '$runningCount',
        subtitle: _statusFilter == 'running' ? '已筛选' : null,
        glyph: AntGlyphs.play,
        tone: PrismTone.success,
        onPressed: () {
          setState(
            () =>
                _statusFilter = _statusFilter == 'running' ? 'all' : 'running',
          );
          _persistFilters();
        },
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '已停止',
        value: '${_profiles.length - runningCount}',
        subtitle: _statusFilter == 'stopped' ? '已筛选' : null,
        glyph: AntGlyphs.stop,
        tone: PrismTone.neutral,
        onPressed: () {
          setState(
            () =>
                _statusFilter = _statusFilter == 'stopped' ? 'all' : 'stopped',
          );
          _persistFilters();
        },
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '当前显示',
        value: '${visible.length}',
        subtitle: proxyBoundCount > 0 ? '已绑定代理 $proxyBoundCount' : null,
        glyph: hasActiveFilters ? AntGlyphs.search : AntGlyphs.globe,
        tone: PrismTone.info,
        staggerIndex: 3,
        staggerDelay: const Duration(milliseconds: 45),
      ),
    ];

    final dropdownFields = [
      PrismDropdownField<String>(
        initialValue: _statusFilter,
        decoration: const PrismInputDecoration(labelText: '状态'),
        items: const [
          PrismDropdownItem(value: 'all', child: Text('全部状态')),
          PrismDropdownItem(value: 'running', child: Text('运行中')),
          PrismDropdownItem(value: 'stopped', child: Text('已停止')),
        ],
        onChanged: (value) {
          setState(() => _statusFilter = value ?? 'all');
          _persistFilters();
        },
      ),
      PrismDropdownField<String>(
        initialValue: coreOptions.contains(_coreFilter) ? _coreFilter : '',
        decoration: const PrismInputDecoration(labelText: '内核'),
        items: [
          const PrismDropdownItem(value: '', child: Text('全部内核')),
          for (final coreId in coreOptions)
            PrismDropdownItem(
              value: coreId,
              child: Text(
                (_cores.firstWhere(
                          (core) => core['coreId']?.toString() == coreId,
                          orElse: () => <String, dynamic>{},
                        )['coreName'] ??
                        coreId)
                    .toString(),
              ),
            ),
        ],
        onChanged: (value) {
          setState(() => _coreFilter = value ?? '');
          _persistFilters();
        },
      ),
      PrismDropdownField<String>(
        initialValue:
            _proxyFilter == '__none__' || proxyOptions.contains(_proxyFilter)
            ? _proxyFilter
            : '',
        decoration: const PrismInputDecoration(labelText: '代理'),
        items: [
          const PrismDropdownItem(value: '', child: Text('全部代理')),
          const PrismDropdownItem(value: '__none__', child: Text('无代理 / 直连')),
          for (final proxyId in proxyOptions)
            PrismDropdownItem(
              value: proxyId,
              child: Text(
                (_proxies.firstWhere(
                          (proxy) => proxy['proxyId']?.toString() == proxyId,
                          orElse: () => <String, dynamic>{},
                        )['proxyName'] ??
                        proxyId)
                    .toString(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          setState(() => _proxyFilter = value ?? '');
          _persistFilters();
        },
      ),
      PrismDropdownField<String>(
        initialValue:
            _groupFilter == '__ungrouped__' ||
                _groups.any((group) => group['groupId'] == _groupFilter)
            ? _groupFilter
            : '',
        decoration: const PrismInputDecoration(labelText: '分组'),
        items: [
          const PrismDropdownItem(value: '', child: Text('全部分组')),
          const PrismDropdownItem(value: '__ungrouped__', child: Text('未分组')),
          for (final group in _groups)
            PrismDropdownItem(
              value: group['groupId']?.toString(),
              child: Text((group['groupName'] ?? '').toString()),
            ),
        ],
        onChanged: (value) {
          setState(() => _groupFilter = value ?? '');
          _persistFilters();
        },
      ),
    ];

    final toolbarActions = <Widget>[
      SizedBox(
        width: 120,
        child: prism.SegmentedControl<String>(
          segments: const [('list', '列表'), ('card', '卡片')],
          value: _viewMode,
          onChanged: (mode) {
            if (mode != _viewMode) _toggleViewMode();
          },
        ),
      ),
      PrismTonalButton.icon(
        onPressed: _toggleFiltersCollapsed,
        icon: PrismGlyph(
          _filtersCollapsed ? AntGlyphs.chevronDown : AntGlyphs.chevronUp,
          size: 15,
        ),
        child: Text(activeFilterCount > 0 ? '筛选 ($activeFilterCount)' : '筛选'),
      ),
      PrismHoverMotion(
        child: prism.FilledButton.icon(
          onPressed: () => _editProfile(),
          icon: const PrismGlyph(AntGlyphs.add, size: 15),
          label: const Text('新建配置'),
        ),
      ),
      prism.IconButton(
        tooltip: '刷新列表',
        onPressed: _loading ? null : _reload,
        icon: const PrismGlyph(AntGlyphs.refresh, size: 17),
      ),
      PrismPopupMenuButton<String>(
        tooltip: '更多工具',
        onSelected: (action) async {
          if (action == 'backup') {
            widget.onOpenBackup?.call();
          } else if (action == 'import') {
            _importProfiles();
          } else if (action == 'export') {
            _exportProfiles();
          } else if (action == 'groups') {
            _manageGroups();
          } else if (action == 'trash') {
            _showTrash();
          } else if (action == 'data-root') {
            try {
              await AppBridge.call('OpenUserDataRoot');
            } catch (error) {
              if (mounted) {
                showPrismNotice(context, '打开用户数据根目录失败：$error');
              }
            }
          }
        },
        itemBuilder: (_) => [
          if (widget.onOpenBackup != null)
            const PrismMenuItem(value: 'backup', child: Text('全局备份')),
          const PrismMenuItem(value: 'import', child: Text('导入实例')),
          if (_profiles.isNotEmpty)
            const PrismMenuItem(value: 'export', child: Text('导出实例')),
          const PrismMenuItem(value: 'groups', child: Text('实例分组管理')),
          const PrismMenuItem(value: 'trash', child: Text('回收站')),
          const PrismMenuItem(value: 'data-root', child: Text('打开用户数据目录')),
        ],
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrismMetricGrid(tiles: kpiTiles),
          const SizedBox(height: 16),
          PrismHoverCard(
            staggerIndex: 4,
            staggerDelay: const Duration(milliseconds: 45),
            radius: prism.AppCorner.xl,
            lift: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 860;
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(
                            child: PrismSearchBar(
                              controller: _searchController,
                              hintText: '搜索名称、启动码、关键字或数据目录…',
                              height: 36,
                              onChanged: (value) {
                                setState(() => _query = value);
                                _persistFilters();
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: toolbarActions,
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PrismSearchBar(
                          controller: _searchController,
                          hintText: '搜索名称、启动码、关键字或数据目录…',
                          height: 36,
                          onChanged: (value) {
                            setState(() => _query = value);
                            _persistFilters();
                          },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: toolbarActions,
                        ),
                      ],
                    );
                  },
                ),
                PrismCollapsible(
                  expanded: !_filtersCollapsed,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      const prism.Divider(height: 1),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 760) {
                            return Row(
                              children: [
                                for (
                                  var i = 0;
                                  i < dropdownFields.length;
                                  i++
                                ) ...[
                                  if (i > 0) const SizedBox(width: 12),
                                  Expanded(child: dropdownFields[i]),
                                ],
                              ],
                            );
                          }
                          return Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              for (final field in dropdownFields)
                                SizedBox(width: 180, child: field),
                            ],
                          );
                        },
                      ),
                      if (tagOptions.isNotEmpty || hasActiveFilters) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (tagOptions.isNotEmpty) ...[
                                    Text(
                                      '标签：',
                                      style: prism.AppTextStyle.footnote
                                          .of(context)
                                          .copyWith(
                                            color: prism.Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    PrismChip(
                                      label: const Text('全部'),
                                      selected: _tagFilters.isEmpty,
                                      onPressed: () {
                                        setState(_tagFilters.clear);
                                        _persistFilters();
                                      },
                                    ),
                                    for (final tag in tagOptions)
                                      PrismChip(
                                        label: Text(tag),
                                        selected: _tagFilters.contains(tag),
                                        onPressed: () {
                                          setState(() {
                                            if (!_tagFilters.add(tag)) {
                                              _tagFilters.remove(tag);
                                            }
                                          });
                                          _persistFilters();
                                        },
                                      ),
                                  ],
                                ],
                              ),
                            ),
                            if (hasActiveFilters) ...[
                              const SizedBox(width: 8),
                              prism.TextButton.icon(
                                onPressed: _clearFilters,
                                icon: const PrismGlyph(
                                  AntGlyphs.clearAll,
                                  size: 16,
                                ),
                                label: const Text('清除筛选'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              prism.TextButton.icon(
                onPressed: visibleIds.isEmpty
                    ? null
                    : () => setState(() {
                        if (allVisibleSelected) {
                          _selectedProfileIds.removeAll(visibleIds);
                        } else {
                          _selectedProfileIds.addAll(visibleIds);
                        }
                      }),
                icon: PrismGlyph(
                  allVisibleSelected ? AntGlyphs.deselect : AntGlyphs.selectAll,
                  size: 16,
                ),
                label: Text(allVisibleSelected ? '取消全选' : '全选当前结果'),
              ),
            ],
          ),
          PrismCollapsible(
            expanded: _selectedProfileIds.isNotEmpty,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 14),
              child: prism.Surface(
                color: prism.Theme.of(context).colorScheme.surfaceContainerLow,
                shape: prism.AppShape.lg,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PrismBadge(
                        label: '已选 ${_selectedProfileIds.length} 个实例',
                        tone: PrismTone.primary,
                      ),
                      prism.OutlinedButton.icon(
                        onPressed: _busyProfile == null
                            ? () => _batchToggleProfiles(true)
                            : null,
                        icon: const PrismGlyph(AntGlyphs.play, size: 16),
                        label: const Text('批量启动'),
                      ),
                      prism.OutlinedButton.icon(
                        onPressed: _busyProfile == null
                            ? () => _batchToggleProfiles(false)
                            : null,
                        icon: const PrismGlyph(AntGlyphs.stop, size: 16),
                        label: const Text('批量关闭'),
                      ),
                      prism.OutlinedButton.icon(
                        onPressed: _busyProfile == null
                            ? () =>
                                  _exportProfiles(_selectedProfileIds.toList())
                            : null,
                        icon: const PrismGlyph(AntGlyphs.download, size: 16),
                        label: const Text('导出'),
                      ),
                      prism.TextButton.icon(
                        onPressed: _busyProfile == null
                            ? _batchDeleteProfiles
                            : null,
                        icon: const PrismGlyph(AntGlyphs.delete, size: 16),
                        label: const Text('移入回收站'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading && _profiles.isEmpty
                ? const Center(child: PrismProgressIndicator())
                : _error != null
                ? _ErrorPanel(message: _error!, onRetry: _reload)
                : visible.isEmpty
                ? _EmptyProfiles(hasProfiles: _profiles.isNotEmpty)
                : prism.PageTransitionSwitcher(
                    duration: PrismMotionSpec.current.pageDuration,
                    transitionBuilder: PrismSlideThroughTransition.builder,
                    child: KeyedSubtree(
                      key: ValueKey(_viewMode),
                      child: _viewMode == 'card'
                          ? GridView.builder(
                              padding: kPrismListPadding,
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 480,
                                    mainAxisExtent: 336,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                              itemCount: visible.length,
                              itemBuilder: (context, index) => _profileGridCard(
                                visible[index],
                                index: index,
                              ),
                            )
                          : ListView.separated(
                              padding: kPrismListPadding,
                              itemCount: visible.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final profile = visible[index];
                                final running = profile['running'] == true;
                                final id =
                                    profile['profileId']?.toString() ?? '';
                                final name = profile['profileName']
                                    ?.toString()
                                    .trim();
                                final busy = _busyProfile == id;
                                final tags =
                                    (profile['tags'] as List?)
                                        ?.map((tag) => tag.toString())
                                        .where((tag) => tag.isNotEmpty)
                                        .toList() ??
                                    const <String>[];
                                return PrismHoverCard(
                                  staggerIndex: index.clamp(0, 6),
                                  staggerDelay: const Duration(
                                    milliseconds: 35,
                                  ),
                                  radius: prism.AppCorner.xl,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      prism.Checkbox(
                                        value: _selectedProfileIds.contains(id),
                                        onChanged: (selected) => setState(() {
                                          if (selected == true) {
                                            _selectedProfileIds.add(id);
                                          } else {
                                            _selectedProfileIds.remove(id);
                                          }
                                        }),
                                      ),
                                      const SizedBox(width: 12),
                                      prism.Surface(
                                        color: running
                                            ? PrismToneColors.of(
                                                context,
                                                PrismTone.success,
                                              ).bg
                                            : prism.Theme.of(context)
                                                  .colorScheme
                                                  .secondaryContainer,
                                        shape: prism.AppShape.md,
                                        child: SizedBox(
                                          width: 42,
                                          height: 42,
                                          child: Center(
                                            child: PrismGlyph(
                                              AntGlyphs.globe,
                                              size: 20,
                                              color: running
                                                  ? PrismToneColors.of(
                                                      context,
                                                      PrismTone.success,
                                                    ).fg
                                                  : prism.Theme.of(context)
                                                        .colorScheme
                                                        .onSecondaryContainer,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name == null || name.isEmpty
                                                  ? '未命名实例'
                                                  : name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: prism.AppTextStyle.headline
                                                  .of(context),
                                            ),
                                            const SizedBox(height: 6),
                                            _profileProxyBadgeRow(profile),
                                            const SizedBox(height: 6),
                                            _profileMetadata(profile),
                                          ],
                                        ),
                                      ),
                                      if (tags.isNotEmpty) ...[
                                        const SizedBox(width: 12),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 220,
                                          ),
                                          child: Wrap(
                                            alignment: WrapAlignment.end,
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: tags
                                                .take(3)
                                                .map(
                                                  (tag) => PrismBadge(
                                                    label: tag,
                                                    tone: PrismTone.info,
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 16),
                                      _RunningStatus(
                                        running: running,
                                        busy: busy,
                                        debugReady:
                                            profile['debugReady'] != false,
                                        lastError: (profile['lastError'] ?? '')
                                            .toString(),
                                        markerCode:
                                            (profile['windowMarkerCode'] ?? '')
                                                .toString(),
                                      ),
                                      const SizedBox(width: 12),
                                      PrismTonalButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => _toggleProfile(profile),
                                        icon: busy
                                            ? const SizedBox.square(
                                                dimension: 15,
                                                child: PrismProgressIndicator(
                                                  size: 15,
                                                ),
                                              )
                                            : PrismGlyph(
                                                running
                                                    ? AntGlyphs.stop
                                                    : AntGlyphs.play,
                                                size: 16,
                                              ),
                                        child: Text(running ? '关闭' : '启动'),
                                      ),
                                      const SizedBox(width: 12),
                                      PrismPopupMenuButton<String>(
                                        tooltip: '更多操作',
                                        onSelected: (action) {
                                          if (action == 'edit') {
                                            _editProfile(profile);
                                          }
                                          if (action == 'copy') {
                                            _copyProfile(profile);
                                          }
                                          if (action == 'delete') {
                                            _deleteProfile(profile);
                                          }
                                          if (action == 'detail') {
                                            widget.onOpenDetails?.call(id);
                                          }
                                          if (action == 'restart') {
                                            _restartProfile(profile);
                                          }
                                          if (action == 'change-proxy') {
                                            _pickProfileProxy(profile);
                                          }
                                          if (action == 'test-proxy') {
                                            _testProfileProxy(profile);
                                          }
                                          if (action == 'export') {
                                            _exportProfiles([id]);
                                          }
                                          if (action == 'code') {
                                            _editLaunchCode(profile);
                                          }
                                          if (action == 'copy-code') {
                                            _copyLaunchCode(profile);
                                          }
                                          if (action == 'keywords') {
                                            _editProfileKeywords(profile);
                                          }
                                          if (action == 'extensions') {
                                            _configureProfileExtensions(
                                              profile,
                                            );
                                          }
                                          if (action == 'data-dir') {
                                            _openProfileDataDir(profile);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PrismMenuItem(
                                            value: 'detail',
                                            child: Text('查看详情'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'change-proxy',
                                            child: Text('切换代理'),
                                          ),
                                          PrismMenuItem(
                                            value: 'test-proxy',
                                            child: Text(
                                              _testingProxyIds.contains(id)
                                                  ? '代理测试中…'
                                                  : '测试代理',
                                            ),
                                          ),
                                          const PrismMenuItem(
                                            value: 'restart',
                                            child: Text('重启实例'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'edit',
                                            child: Text('编辑实例'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'copy',
                                            child: Text('复制配置'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'code',
                                            child: Text('管理启动码'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'copy-code',
                                            child: Text('复制启动码'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'keywords',
                                            child: Text('管理关键字'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'extensions',
                                            child: Text('配置实例插件'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'data-dir',
                                            child: Text('打开数据目录'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'export',
                                            child: Text('导出实例'),
                                          ),
                                          const PrismMenuItem(
                                            value: 'delete',
                                            danger: true,
                                            child: Text('移入回收站'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RunningStatus extends StatelessWidget {
  const _RunningStatus({
    required this.running,
    this.busy = false,
    this.debugReady = true,
    this.lastError = '',
    this.markerCode = '',
  });

  final bool running;
  final bool busy;
  final bool debugReady;
  final String lastError;
  final String markerCode;

  @override
  Widget build(BuildContext context) {
    final (String label, PrismTone tone) = busy
        ? (running ? '停止中' : '启动中', PrismTone.info)
        : running && !debugReady
        ? ('运行中（待就绪）', PrismTone.warning)
        : running
        ? ('运行中', PrismTone.success)
        : lastError.trim().isNotEmpty
        ? ('异常', PrismTone.danger)
        : ('已停止', PrismTone.neutral);
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PrismBadge(label: label, tone: tone, dot: true),
        if (running && markerCode.trim().isNotEmpty)
          PrismBadge(
            label: markerCode.trim().toUpperCase(),
            tone: PrismTone.primary,
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
    return PrismEmptyState(
      title: hasProfiles ? '没有匹配的实例' : '还没有浏览器实例',
      glyph: AntGlyphs.browserOff,
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return PrismEmptyState(
      title: '无法连接到应用服务',
      subtitle: message,
      glyph: AntGlyphs.cloudOff,
      action: PrismHoverMotion(
        child: prism.FilledButton(onPressed: onRetry, child: const Text('重试')),
      ),
    );
  }
}
