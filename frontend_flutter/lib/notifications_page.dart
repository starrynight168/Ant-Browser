import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'notification_store.dart';

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
    widget.store.markAllRead();
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
        const filters = [
          ('all', '全部'),
          ('unread', '未读'),
          ('error', '错误'),
          ('warning', '警告'),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(unread > 0 ? '通知中心 · $unread 条未读' : '通知中心'),
                  ),
                  if (unread > 0)
                    prism.TextButton.icon(
                      onPressed: widget.store.markAllRead,
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('全部标为已读'),
                    ),
                  if (all.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    prism.OutlinedButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('清空通知'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final (value, label) in filters)
                    PrismChip(
                      label: Text('$label (${counts[value]})'),
                      selected: _filter == value,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('暂无通知'))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final id = '${item['id'] ?? ''}';
                          final type = '${item['type'] ?? 'info'}';
                          final isRead = item['read'] == true;
                          final colors = prism.Theme.of(context).colorScheme;
                          final color = switch (type) {
                            'error' => colors.error,
                            'warning' => colors.tertiary,
                            'success' => colors.primary,
                            _ => colors.secondary,
                          };
                          final icon = switch (type) {
                            'error' => Icons.error_outline,
                            'warning' => Icons.warning_amber_outlined,
                            'success' => Icons.check_circle_outline,
                            _ => Icons.info_outline,
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
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            decoration: BoxDecoration(
                              color: prism.Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: prism.Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(icon, color: color, size: 21),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (!isRead) ...[
                                              Container(
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 7),
                                            ],
                                            Expanded(
                                              child: Text(
                                                '${item['title'] ?? '通知'}',
                                                style: TextStyle(
                                                  fontWeight: isRead
                                                      ? FontWeight.w500
                                                      : FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '$source · ${item['time'] ?? ''}',
                                          style: TextStyle(
                                            color: colors.onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        prism.SelectableText(
                                          '${item['message'] ?? ''}',
                                          style: TextStyle(
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
                                            icon: const Icon(
                                              Icons.arrow_forward,
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
                                      onPressed: () =>
                                          widget.store.markRead(id),
                                      icon: const Icon(Icons.done, size: 19),
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
      },
    );
  }
}
