import 'prism_widgets.dart';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  static const _protectedUrl = 'ant://fingerprint-check';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _saving = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isProtected(Map<String, dynamic> item) =>
      '${item['url'] ?? ''}'.trim().toLowerCase() == _protectedUrl;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await AppBridge.call('BookmarkList');
      if (!mounted) return;
      setState(() {
        _items = (result is List ? result : const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (error) {
      if (mounted) _message('读取书签失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateItem(int index, String field, dynamic value) {
    setState(() => _items[index] = {..._items[index], field: value});
  }

  void _add() {
    setState(() => _items.add({'name': '', 'url': '', 'openOnStart': false}));
  }

  Future<void> _save() async {
    if (_items.any(
      (item) =>
          '${item['name'] ?? ''}'.trim().isEmpty ||
          '${item['url'] ?? ''}'.trim().isEmpty,
    )) {
      _message('请填写每个书签的名称和网址');
      return;
    }
    setState(() => _saving = true);
    try {
      await AppBridge.call('BookmarkSave', [_items]);
      final sync = await AppBridge.call('BookmarkSyncToProfiles');
      _message(_syncMessage(sync, prefix: '书签已保存'));
    } catch (error) {
      _message('保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (!await _confirm('恢复默认书签', '自定义书签将被默认书签替换。')) return;
    try {
      await AppBridge.call('BookmarkReset');
      await _load();
      _message('已恢复默认书签');
    } catch (error) {
      _message('恢复失败：$error');
    }
  }

  Future<void> _sync() async {
    if (!await _confirm('同步到现有实例', '把当前书签同步到已停止的浏览器实例。')) return;
    setState(() => _syncing = true);
    try {
      final result = await AppBridge.call('BookmarkSyncToProfiles');
      _message(_syncMessage(result, prefix: '书签同步完成'));
    } catch (error) {
      _message('同步失败：$error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showPrismDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => PrismDialog(
          title: Text(title),
          content: Text(message),
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
      ) ==
      true;

  String _syncMessage(dynamic result, {required String prefix}) {
    if (result is! Map) return prefix;
    final synced = result['synced'] ?? 0;
    final skipped = result['skipped'] ?? 0;
    final failed = result['failed'] ?? 0;
    return '$prefix：已同步 $synced 个实例，跳过 $skipped 个，失败 $failed 个';
  }

  void _message(String value) {
    if (!mounted) return;
    showPrismNotice(context, (value).toString());
  }

  @override
  Widget build(BuildContext context) {
    final protectedCount = _items.where(_isProtected).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('管理默认书签，并同步到浏览器实例。')),
              prism.OutlinedButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: const Icon(Icons.sync, size: 18),
                label: Text(_syncing ? '同步中' : '手动同步'),
              ),
              const SizedBox(width: 8),
              prism.OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('恢复默认'),
              ),
              const SizedBox(width: 8),
              prism.FilledButton(
                onPressed: _saving || _loading ? null : _save,
                child: Text(_saving ? '保存中' : '保存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '内置检测（$protectedCount 项）',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: prism.PrismReorderableListView(
                          proxyDecorator: (child, index, animation) => child,
                          itemCount: _items.length,
                          onReorderItem: (oldIndex, newIndex) {
                            if (oldIndex < 0 || oldIndex >= _items.length)
                              return;
                            final movingProtected = _isProtected(
                              _items[oldIndex],
                            );
                            final target = newIndex;
                            if (movingProtected ||
                                (target >= 0 &&
                                    target < _items.length &&
                                    _isProtected(_items[target])))
                              return;
                            setState(() {
                              final item = _items.removeAt(oldIndex);
                              _items.insert(
                                target.clamp(0, _items.length).toInt(),
                                item,
                              );
                            });
                          },
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final protected = _isProtected(item);
                            return PrismCard(
                              key: ValueKey('${item['url'] ?? ''}-$index'),
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: prism.Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    prism.ReorderDragStartListener(
                                      index: index,
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 5,
                                        ),
                                        child: Icon(
                                          Icons.drag_indicator,
                                          color: prism.Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: PrismTextFormField(
                                        key: ValueKey(
                                          'bookmark-name-$index-${item['name']}',
                                        ),
                                        initialValue: '${item['name'] ?? ''}',
                                        readOnly: protected,
                                        decoration: const PrismInputDecoration(
                                          labelText: '名称',
                                          isDense: true,
                                        ),
                                        onChanged: (value) =>
                                            _updateItem(index, 'name', value),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 4,
                                      child: PrismTextFormField(
                                        key: ValueKey(
                                          'bookmark-url-$index-${item['url']}',
                                        ),
                                        initialValue: '${item['url'] ?? ''}',
                                        readOnly: protected,
                                        decoration: const PrismInputDecoration(
                                          labelText: '网址',
                                          isDense: true,
                                        ),
                                        onChanged: (value) =>
                                            _updateItem(index, 'url', value),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        prism.Checkbox(
                                          value: item['openOnStart'] == true,
                                          onChanged: (value) => _updateItem(
                                            index,
                                            'openOnStart',
                                            value == true,
                                          ),
                                        ),
                                        const Text(
                                          '启动时打开',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    prism.IconButton(
                                      tooltip: '删除',
                                      onPressed: protected
                                          ? null
                                          : () => setState(
                                              () => _items.removeAt(index),
                                            ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: prism.OutlinedButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加书签'),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
