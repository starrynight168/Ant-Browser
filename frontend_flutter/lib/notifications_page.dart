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
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.store.markAllRead();
    });
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

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, child) {
        final all = widget.store.notifications;
        final unread = widget.store.unreadCount;
        final filtered = all.where((item) {
          switch (_filter) {
            case 'unread':
              return item['read'] != true;
            case 'error':
            case 'warning':
              return item['type'] == _filter;
            default:
              return true;
          }
        }).toList();
        final counts = {
          'all': all.length,
          'unread': unread,
          'error': all.where((item) => item['type'] == 'error').length,
          'warning': all.where((item) => item['type'] == 'warning').length,
        };

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '通知中心',
                    style: prism.AppTextStyle.headline.of(context),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(width: 10),
                    PrismBadge(
                      label: '$unread 条未读',
                      tone: PrismTone.primary,
                      dot: true,
                    ),
                  ],
                  const Spacer(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (unread > 0)
                        prism.TextButton.icon(
                          onPressed: widget.store.markAllRead,
                          icon: const PrismGlyph(AntGlyphs.doneAll, size: 17),
                          label: const Text('全部标为已读'),
                        ),
                      if (all.isNotEmpty)
                        prism.OutlinedButton.icon(
                          onPressed: _clear,
                          icon: const PrismGlyph(AntGlyphs.delete, size: 17),
                          label: const Text('清空通知'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: prism.SegmentedControl<String>(
                  value: _filter,
                  onChanged: (value) => setState(() => _filter = value),
                  segments: [
                    ('all', '全部 (${counts['all']})'),
                    ('unread', '未读 (${counts['unread']})'),
                    ('error', '错误 (${counts['error']})'),
                    ('warning', '警告 (${counts['warning']})'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: filtered.isEmpty
                    ? PrismEmptyState(
                        glyph: AntGlyphs.bell,
                        title: all.isEmpty ? '暂无通知' : '当前筛选没有通知',
                        subtitle: all.isEmpty
                            ? '系统提醒、运行状态与错误消息会显示在这里。'
                            : '切换到“全部”查看所有历史通知。',
                        action: all.isNotEmpty && _filter != 'all'
                            ? prism.OutlinedButton(
                                onPressed: () =>
                                    setState(() => _filter = 'all'),
                                child: const Text('查看全部通知'),
                              )
                            : null,
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
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
                          final source =
                              switch ('${item['source'] ?? 'system'}') {
                                'operation' => '操作',
                                'runtime' => '运行状态',
                                'frontend' => '前端',
                                _ => '系统',
                              };
                          return prism.Card(
                            radius: prism.AppCorner.xl,
                            inert: true,
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                prism.Surface(
                                  color: palette.bg,
                                  shape: prism.AppShape.md,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: PrismGlyph(
                                      glyph,
                                      color: palette.fg,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              style: prism
                                                  .AppTextStyle
                                                  .subheadline
                                                  .of(
                                                    context,
                                                    emphasized: !isRead,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$source · ${item['time'] ?? ''}',
                                        style: prism.AppTextStyle.caption1
                                            .of(context)
                                            .copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      prism.SelectableText(
                                        '${item['message'] ?? ''}',
                                        style: prism.AppTextStyle.body
                                            .of(context)
                                            .copyWith(
                                              color: colors.onSurface,
                                              height: 1.5,
                                            ),
                                      ),
                                      if (action != null &&
                                          action['path'] is String) ...[
                                        const SizedBox(height: 8),
                                        prism.TextButton.icon(
                                          onPressed: () {
                                            widget.store.markRead(id);
                                            widget.onNavigate(
                                              action['path'] as String,
                                            );
                                          },
                                          icon: const PrismGlyph(
                                            AntGlyphs.arrowForward,
                                            size: 16,
                                          ),
                                          label: Text(
                                            '${action['label'] ?? '查看'}',
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (!isRead)
                                  prism.IconButton(
                                    tooltip: '标记为已读',
                                    onPressed: () => widget.store.markRead(id),
                                    icon: const PrismGlyph(
                                      AntGlyphs.check,
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
