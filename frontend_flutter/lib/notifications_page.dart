import 'package:prism_ui/prism_ui.dart' as prism;

import 'notification_store.dart';
import 'prism_widgets.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    required this.store,
    required this.onNavigate,
    super.key,
  });

  final NotificationStore store;
  final ValueChanged<String> onNavigate;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _searchController = TextEditingController();
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.store.markAllRead();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('清空通知？'),
        content: const Text('清空后无法恢复。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.store.clear();
  }

  String _sourceLabel(dynamic rawSource) =>
      switch ('${rawSource ?? 'system'}') {
        'operation' => '操作',
        'runtime' => '运行状态',
        'frontend' => '前端',
        _ => '系统',
      };

  Widget _buildOverviewStrip({
    required int total,
    required int unread,
    required int errorCount,
    required int warningCount,
  }) {
    final tiles = [
      PrismMetricTile(
        label: '全部通知',
        value: '$total',
        glyph: AntGlyphs.bell,
        tone: PrismTone.primary,
        onPressed: () => setState(() => _filter = 'all'),
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '未读',
        value: '$unread',
        glyph: AntGlyphs.mail,
        tone: unread > 0 ? PrismTone.info : PrismTone.neutral,
        onPressed: () =>
            setState(() => _filter = _filter == 'unread' ? 'all' : 'unread'),
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '错误',
        value: '$errorCount',
        glyph: AntGlyphs.error,
        tone: errorCount > 0 ? PrismTone.danger : PrismTone.neutral,
        onPressed: () =>
            setState(() => _filter = _filter == 'error' ? 'all' : 'error'),
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '警告',
        value: '$warningCount',
        glyph: AntGlyphs.warning,
        tone: warningCount > 0 ? PrismTone.warning : PrismTone.neutral,
        onPressed: () =>
            setState(() => _filter = _filter == 'warning' ? 'all' : 'warning'),
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
                if (i > 0) const SizedBox(width: 16),
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
                const SizedBox(width: 16),
                Expanded(child: tiles[1]),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: tiles[2]),
                const SizedBox(width: 16),
                Expanded(child: tiles[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar({
    required int total,
    required int unread,
    required int errorCount,
    required int warningCount,
  }) {
    final filterControl = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: prism.SegmentedControl<String>(
        value: _filter,
        onChanged: (value) => setState(() => _filter = value),
        segments: [
          ('all', '全部 ($total)'),
          ('unread', '未读 ($unread)'),
          ('error', '错误 ($errorCount)'),
          ('warning', '警告 ($warningCount)'),
        ],
      ),
    );
    final actionWidgets = <Widget>[
      PrismHoverMotion(
        enabled: unread > 0,
        child: PrismTonalButton.icon(
          onPressed: unread > 0 ? widget.store.markAllRead : null,
          icon: const PrismGlyph(AntGlyphs.doneAll, size: 16),
          child: const Text('全部已读'),
        ),
      ),
      PrismHoverMotion(
        enabled: total > 0,
        child: prism.OutlinedButton.icon(
          onPressed: total > 0 ? _clear : null,
          icon: const PrismGlyph(AntGlyphs.delete, size: 16),
          label: const Text('清空通知'),
        ),
      ),
    ];

    return PrismHoverCard(
      staggerIndex: 4,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          if (wide) {
            return Row(
              children: [
                Expanded(
                  child: PrismSearchBar(
                    controller: _searchController,
                    hintText: '搜索通知标题、内容或来源…',
                    height: 36,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                filterControl,
                const SizedBox(width: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actionWidgets,
                ),
              ],
            );
          }
          if (constraints.maxWidth >= 580) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PrismSearchBar(
                        controller: _searchController,
                        hintText: '搜索通知标题、内容或来源…',
                        height: 36,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 14),
                    filterControl,
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actionWidgets,
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismSearchBar(
                controller: _searchController,
                hintText: '搜索通知标题、内容或来源…',
                height: 36,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              prism.SegmentedControl<String>(
                value: _filter,
                onChanged: (value) => setState(() => _filter = value),
                segments: [
                  ('all', '全部 ($total)'),
                  ('unread', '未读 ($unread)'),
                  ('error', '错误 ($errorCount)'),
                  ('warning', '警告 ($warningCount)'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
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

  Widget _buildNotificationCard(
    BuildContext context,
    Map<String, dynamic> item,
    int index,
  ) {
    final colors = prism.Theme.of(context).colorScheme;
    final id = '${item['id'] ?? ''}';
    final type = '${item['type'] ?? 'info'}';
    final isRead = item['read'] == true;
    final tone = switch (type) {
      'error' => PrismTone.danger,
      'warning' => PrismTone.warning,
      'success' => PrismTone.success,
      _ => PrismTone.info,
    };
    final palette = PrismToneColors.of(context, tone);
    final glyph = switch (type) {
      'error' => AntGlyphs.error,
      'warning' => AntGlyphs.warning,
      'success' => AntGlyphs.checkCircle,
      _ => AntGlyphs.info,
    };
    final action = item['action'] is Map
        ? Map<String, dynamic>.from(item['action'] as Map)
        : null;
    final source = _sourceLabel(item['source']);

    return PrismHoverCard(
      staggerIndex: index.clamp(0, 6),
      staggerDelay: const Duration(milliseconds: 40),
      radius: prism.AppCorner.xl,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          prism.Surface(
            color: palette.bg,
            shape: prism.AppShape.md,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: PrismGlyph(glyph, color: palette.fg, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!isRead) ...[
                      const PrismBadge(
                        label: '未读',
                        tone: PrismTone.primary,
                        dot: true,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        '${item['title'] ?? '通知'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.subheadline.of(
                          context,
                          emphasized: !isRead,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$source · ${item['time'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: prism.AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                prism.SelectableText(
                  '${item['message'] ?? ''}',
                  style: prism.AppTextStyle.body
                      .of(context)
                      .copyWith(color: colors.onSurface, height: 1.5),
                ),
                if (action != null && action['path'] is String) ...[
                  const SizedBox(height: 10),
                  prism.TextButton.icon(
                    onPressed: () {
                      widget.store.markRead(id);
                      widget.onNavigate(action['path'] as String);
                    },
                    icon: const PrismGlyph(AntGlyphs.arrowForward, size: 16),
                    label: Text('${action['label'] ?? '查看'}'),
                  ),
                ],
              ],
            ),
          ),
          if (!isRead) ...[
            const SizedBox(width: 12),
            prism.IconButton(
              tooltip: '标记为已读',
              onPressed: () => widget.store.markRead(id),
              style: const prism.ButtonStyle(
                fixedSize: Size.square(36),
                minimumSize: Size.square(36),
                padding: EdgeInsets.zero,
              ),
              icon: const PrismGlyph(AntGlyphs.check, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, child) {
        final all = widget.store.notifications;
        final unread = widget.store.unreadCount;
        final errorCount = all.where((item) => item['type'] == 'error').length;
        final warningCount = all
            .where((item) => item['type'] == 'warning')
            .length;
        final query = _searchController.text.trim().toLowerCase();

        final filtered = all.where((item) {
          final matchesType = switch (_filter) {
            'unread' => item['read'] != true,
            'error' || 'warning' => item['type'] == _filter,
            _ => true,
          };
          if (!matchesType) return false;
          if (query.isEmpty) return true;
          final title = '${item['title'] ?? ''}'.toLowerCase();
          final message = '${item['message'] ?? ''}'.toLowerCase();
          final source = _sourceLabel(item['source']).toLowerCase();
          final time = '${item['time'] ?? ''}'.toLowerCase();
          return title.contains(query) ||
              message.contains(query) ||
              source.contains(query) ||
              time.contains(query);
        }).toList();

        final hasActiveFilter = _filter != 'all' || query.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOverviewStrip(
                total: all.length,
                unread: unread,
                errorCount: errorCount,
                warningCount: warningCount,
              ),
              const SizedBox(height: 16),
              _buildToolbar(
                total: all.length,
                unread: unread,
                errorCount: errorCount,
                warningCount: warningCount,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: PrismHoverCard(
                  staggerIndex: 5,
                  staggerDelay: const Duration(milliseconds: 45),
                  radius: prism.AppCorner.xl,
                  padding: EdgeInsets.zero,
                  hoverGlow: true,
                  lift: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      prism.InfoHeader(
                        info: const prism.Info(
                          label: '通知列表',
                          glyph: AntGlyphs.bell,
                        ),
                        actions: [
                          if (unread > 0)
                            PrismBadge(
                              label: '$unread 条未读',
                              tone: PrismTone.primary,
                              dot: true,
                            ),
                          PrismBadge(
                            label: '${filtered.length} 条',
                            tone: filtered.isEmpty
                                ? PrismTone.neutral
                                : PrismTone.info,
                          ),
                        ],
                        padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
                      ),
                      const prism.Divider(height: 1),
                      Expanded(
                        child: prism.PageTransitionSwitcher(
                          duration: PrismMotionSpec.current.pageDuration,
                          transitionBuilder:
                              PrismSlideThroughTransition.builder,
                          child: KeyedSubtree(
                            key: ValueKey(
                              '$_filter-$query-${filtered.isEmpty}',
                            ),
                            child: filtered.isEmpty
                                ? PrismEmptyState(
                                    glyph: AntGlyphs.bell,
                                    title: all.isEmpty ? '暂无通知' : '当前筛选没有通知',
                                    action: all.isNotEmpty && hasActiveFilter
                                        ? prism.OutlinedButton(
                                            onPressed: () => setState(() {
                                              _filter = 'all';
                                              _searchController.clear();
                                            }),
                                            child: const Text('查看全部通知'),
                                          )
                                        : null,
                                  )
                                : Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: ListView.separated(
                                      padding: kPrismListPadding,
                                      itemCount: filtered.length,
                                      separatorBuilder: (context, index) =>
                                          const SizedBox(height: 14),
                                      itemBuilder: (context, index) =>
                                          _buildNotificationCard(
                                            context,
                                            filtered[index],
                                            index,
                                          ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
