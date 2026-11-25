import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

class _BookmarkEntry {
  _BookmarkEntry({
    required this.id,
    required String name,
    required String url,
    required this.openOnStart,
  }) : nameController = TextEditingController(text: name),
       urlController = TextEditingController(text: url);

  final int id;
  final TextEditingController nameController;
  final TextEditingController urlController;
  bool openOnStart;

  bool get isProtected =>
      urlController.text.trim().toLowerCase() == _BookmarksPageState._protectedUrl;

  Map<String, dynamic> toJson() => {
    'name': nameController.text,
    'url': urlController.text,
    'openOnStart': openOnStart,
  };

  void dispose() {
    nameController.dispose();
    urlController.dispose();
  }
}

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  static const _protectedUrl = 'ant://fingerprint-check';
  final List<_BookmarkEntry> _entries = [];
  int _nextId = 1;
  bool _loading = true;
  bool _saving = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  List<_BookmarkEntry> get _protectedEntries =>
      _entries.where((e) => e.isProtected).toList();

  List<_BookmarkEntry> get _regularEntries =>
      _entries.where((e) => !e.isProtected).toList();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await AppBridge.call('BookmarkList');
      if (!mounted) return;
      final rawList = (result is List ? result : const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final nextEntries = [
        for (final item in rawList)
          _BookmarkEntry(
            id: _nextId++,
            name: '${item['name'] ?? ''}',
            url: '${item['url'] ?? ''}',
            openOnStart: item['openOnStart'] == true,
          ),
      ];
      final old = List<_BookmarkEntry>.of(_entries);
      setState(() {
        _entries
          ..clear()
          ..addAll(nextEntries);
      });
      for (final item in old) {
        item.dispose();
      }
    } catch (error) {
      if (mounted) _message('读取书签失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _add() {
    setState(() {
      _entries.add(
        _BookmarkEntry(id: _nextId++, name: '', url: '', openOnStart: false),
      );
    });
  }

  void _removeEntry(_BookmarkEntry entry) {
    if (entry.isProtected) return;
    setState(() => _entries.remove(entry));
    entry.dispose();
  }

  void _reorderRegular(int oldIndex, int newIndex) {
    final protected = _protectedEntries;
    final regular = _regularEntries;
    if (oldIndex < 0 || oldIndex >= regular.length) return;
    final target = newIndex.clamp(0, regular.length - 1).toInt();
    setState(() {
      final moved = regular.removeAt(oldIndex);
      regular.insert(target, moved);
      _entries
        ..clear()
        ..addAll(protected)
        ..addAll(regular);
    });
  }

  Future<void> _save() async {
    final payload = _entries.map((entry) => entry.toJson()).toList();
    if (payload.any(
      (item) =>
          '${item['name'] ?? ''}'.trim().isEmpty ||
          '${item['url'] ?? ''}'.trim().isEmpty,
    )) {
      _message('请填写每个书签的名称和网址');
      return;
    }
    setState(() => _saving = true);
    try {
      await AppBridge.call('BookmarkSave', [payload]);
      try {
        final result = await AppBridge.call('BookmarkSyncToProfiles');
        _message(_syncMessage(result, prefix: '书签已保存'));
      } catch (error) {
        _message('书签已保存，但同步失败：$error');
      }
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
    showPrismNotice(context, value);
  }

  Widget _buildBookmarkRow(
    _BookmarkEntry entry, {
    required bool protected,
    int? dragIndex,
  }) {
    final colors = prism.Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('bookmark-entry-${entry.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: prism.Surface(
        color: colors.surfaceContainerLow,
        shape: prism.AppShape.lg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (protected)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: PrismBadge(
                    label: '内置',
                    tone: PrismTone.info,
                    glyph: AntGlyphs.shield,
                  ),
                )
              else if (dragIndex != null)
                prism.ReorderDragStartListener(
                  index: dragIndex,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: PrismGlyph(
                      AntGlyphs.dragHandle,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              Expanded(
                flex: 2,
                child: PrismTextField(
                  controller: entry.nameController,
                  readOnly: protected,
                  decoration: const PrismInputDecoration(
                    labelText: '名称',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: PrismTextField(
                  controller: entry.urlController,
                  readOnly: protected,
                  decoration: const PrismInputDecoration(
                    labelText: '网址',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  prism.Checkbox(
                    value: entry.openOnStart,
                    onChanged: (value) =>
                        setState(() => entry.openOnStart = value == true),
                  ),
                  Text(
                    '启动时打开',
                    style: prism.AppTextStyle.caption1.of(context),
                  ),
                ],
              ),
              if (!protected)
                prism.IconButton(
                  tooltip: '删除',
                  onPressed: () => _removeEntry(entry),
                  icon: const PrismGlyph(AntGlyphs.delete, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final protectedEntries = _protectedEntries;
    final regularEntries = _regularEntries;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '管理默认书签，并同步到浏览器实例。',
            style: prism.AppTextStyle.footnote
                .of(context)
                .copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              prism.OutlinedButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: const PrismGlyph(AntGlyphs.sync, size: 17),
                label: Text(_syncing ? '同步中' : '手动同步'),
              ),
              prism.OutlinedButton.icon(
                onPressed: _reset,
                icon: const PrismGlyph(AntGlyphs.restore, size: 17),
                label: const Text('恢复默认'),
              ),
              prism.FilledButton.icon(
                onPressed: _saving || _loading ? null : _save,
                icon: const PrismGlyph(AntGlyphs.save, size: 17),
                label: Text(_saving ? '保存中' : '保存'),
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
                      if (protectedEntries.isNotEmpty) ...[
                        PrismSectionCard(
                          title: '内置检测',
                          glyph: AntGlyphs.shield,
                          actions: const [
                            PrismBadge(label: '内置', tone: PrismTone.info),
                          ],
                          child: Column(
                            children: [
                              for (final entry in protectedEntries)
                                _buildBookmarkRow(entry, protected: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: prism.Card(
                          radius: prism.AppCorner.xl,
                          inert: true,
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              prism.InfoHeader(
                                info: prism.Info(
                                  label: '书签列表（${regularEntries.length} 项）',
                                  glyph: AntGlyphs.bookmark,
                                ),
                                actions: [
                                  prism.OutlinedButton.icon(
                                    onPressed: _add,
                                    icon: const PrismGlyph(
                                      AntGlyphs.add,
                                      size: 16,
                                    ),
                                    label: const Text('添加书签'),
                                  ),
                                ],
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  14,
                                  10,
                                ),
                              ),
                              const prism.Divider(height: 1),
                              Expanded(
                                child: regularEntries.isEmpty
                                    ? PrismEmptyState(
                                        glyph: AntGlyphs.bookmark,
                                        title: '暂无自定义书签',
                                        subtitle: '点击右上角“添加书签”创建常用网址。',
                                        action: prism.OutlinedButton.icon(
                                          onPressed: _add,
                                          icon: const PrismGlyph(
                                            AntGlyphs.add,
                                            size: 16,
                                          ),
                                          label: const Text('添加书签'),
                                        ),
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: prism.PrismReorderableListView(
                                          proxyDecorator:
                                              (child, index, animation) =>
                                                  child,
                                          itemCount: regularEntries.length,
                                          onReorderItem: _reorderRegular,
                                          itemBuilder: (context, index) =>
                                              _buildBookmarkRow(
                                                regularEntries[index],
                                                protected: false,
                                                dragIndex: index,
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
          ),
        ],
      ),
    );
  }
}
