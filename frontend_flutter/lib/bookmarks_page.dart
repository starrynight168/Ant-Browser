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
  final _searchController = TextEditingController();
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
    _searchController.dispose();
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
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
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
    EdgeInsetsGeometry margin = const EdgeInsets.only(bottom: 8),
  }) {
    final colors = prism.Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('bookmark-entry-${entry.id}'),
      padding: margin,
      child: prism.Surface(
        color: colors.surfaceContainerLow,
        shape: prism.AppShape.lg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
              else if (dragIndex != null) ...[
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
                const SizedBox(width: 6),
              ],
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
              if (!protected) ...[
                const SizedBox(width: 6),
                prism.IconButton(
                  tooltip: '删除',
                  onPressed: () => _removeEntry(entry),
                  icon: const PrismGlyph(AntGlyphs.delete, size: 18),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _matchesQuery(_BookmarkEntry entry, String query) {
    if (query.isEmpty) return true;
    return entry.nameController.text.toLowerCase().contains(query) ||
        entry.urlController.text.toLowerCase().contains(query);
  }

  Widget _buildOverviewStrip(
    List<_BookmarkEntry> protectedEntries,
    List<_BookmarkEntry> regularEntries,
    bool isFiltering,
  ) {
    final openOnStartCount = regularEntries.where((e) => e.openOnStart).length;
    final tiles = [
      PrismMetricTile(
        label: '书签总数',
        value: '${_entries.length}',
        subtitle:
            '内置 ${protectedEntries.length} · 自定义 ${regularEntries.length}',
        glyph: AntGlyphs.bookmark,
        tone: PrismTone.primary,
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '自定义书签',
        value: '${regularEntries.length}',
        subtitle: '启动时打开 $openOnStartCount 项',
        glyph: AntGlyphs.link,
        tone: PrismTone.info,
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '内置检测',
        value: '${protectedEntries.length}',
        subtitle: protectedEntries.any((e) => e.openOnStart)
            ? '已开启启动检测'
            : '默认指纹检测项',
        glyph: AntGlyphs.shield,
        tone: PrismTone.success,
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '拖拽排序',
        value: isFiltering ? '已暂停' : '已就绪',
        subtitle: isFiltering ? '清空搜索后可拖拽排序' : '拖动把手调整顺序',
        glyph: AntGlyphs.sort,
        tone: isFiltering ? PrismTone.warning : PrismTone.neutral,
        onPressed: isFiltering
            ? () => setState(() => _searchController.clear())
            : null,
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
                if (i > 0) const SizedBox(width: 12),
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
                const SizedBox(width: 10),
                Expanded(child: tiles[1]),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: tiles[2]),
                const SizedBox(width: 10),
                Expanded(child: tiles[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar() {
    final actionWidgets = <Widget>[
      PrismHoverMotion(
        enabled: !_loading,
        child: prism.FilledButton.icon(
          onPressed: _loading ? null : _add,
          icon: const PrismGlyph(AntGlyphs.add, size: 15),
          label: const Text('添加书签'),
        ),
      ),
      PrismHoverMotion(
        enabled: !_saving && !_loading,
        child: PrismTonalButton.icon(
          onPressed: _saving || _loading ? null : _save,
          icon: const PrismGlyph(AntGlyphs.save, size: 15),
          child: Text(_saving ? '保存中' : '保存'),
        ),
      ),
      prism.IconButton(
        tooltip: '刷新',
        onPressed: _loading ? null : _load,
        icon: const PrismGlyph(AntGlyphs.refresh, size: 17),
      ),
      PrismPopupMenuButton<String>(
        tooltip: '更多操作',
        enabled: !_loading,
        onSelected: (action) {
          switch (action) {
            case 'sync':
              _sync();
            case 'reset':
              _reset();
          }
        },
        itemBuilder: (_) => [
          PrismMenuItem(
            value: 'sync',
            enabled: !_syncing,
            child: Text(_syncing ? '同步中…' : '手动同步'),
          ),
          const PrismMenuItem(value: 'reset', child: Text('恢复默认')),
        ],
      ),
    ];

    return PrismHoverCard(
      staggerIndex: 4,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          if (wide) {
            return Row(
              children: [
                Expanded(
                  child: PrismSearchBar(
                    controller: _searchController,
                    hintText: '搜索书签名称或网址…',
                    height: 36,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
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
                hintText: '搜索书签名称或网址…',
                height: 36,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
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

  @override
  Widget build(BuildContext context) {
    final protectedEntries = _protectedEntries;
    final regularEntries = _regularEntries;
    final query = _searchController.text.trim().toLowerCase();
    final isFiltering = query.isNotEmpty;
    final filteredProtected = protectedEntries
        .where((e) => _matchesQuery(e, query))
        .toList();
    final filteredRegular = regularEntries
        .where((e) => _matchesQuery(e, query))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewStrip(protectedEntries, regularEntries, isFiltering),
          const SizedBox(height: 12),
          _buildToolbar(),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (filteredProtected.isNotEmpty) ...[
                        PrismSectionCard(
                          title: '内置检测',
                          glyph: AntGlyphs.shield,
                          staggerIndex: 5,
                          staggerDelay: const Duration(milliseconds: 45),
                          actions: const [
                            PrismBadge(label: '内置', tone: PrismTone.info),
                          ],
                          child: Column(
                            children: [
                              for (var i = 0; i < filteredProtected.length; i++)
                                _buildBookmarkRow(
                                  filteredProtected[i],
                                  protected: true,
                                  margin: i == filteredProtected.length - 1
                                      ? EdgeInsets.zero
                                      : const EdgeInsets.only(bottom: 8),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: PrismHoverCard(
                          staggerIndex: 6,
                          staggerDelay: const Duration(milliseconds: 45),
                          radius: prism.AppCorner.xl,
                          padding: EdgeInsets.zero,
                          hoverGlow: true,
                          lift: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              prism.InfoHeader(
                                info: const prism.Info(
                                  label: '书签列表',
                                  glyph: AntGlyphs.bookmark,
                                ),
                                actions: [
                                  if (isFiltering) ...[
                                    const PrismBadge(
                                      label: '筛选中 · 拖拽已暂停',
                                      tone: PrismTone.warning,
                                    ),
                                    prism.TextButton(
                                      onPressed: () =>
                                          setState(() => _searchController.clear()),
                                      child: const Text('清空筛选'),
                                    ),
                                  ],
                                  PrismBadge(
                                    label: '${filteredRegular.length} 项',
                                    tone: filteredRegular.isEmpty
                                        ? PrismTone.neutral
                                        : PrismTone.primary,
                                  ),
                                ],
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  14,
                                  10,
                                ),
                              ),
                              const prism.Divider(height: 1),
                              Expanded(
                                child: prism.PageTransitionSwitcher(
                                  duration: PrismMotionSpec.current.pageDuration,
                                  transitionBuilder:
                                      PrismSlideThroughTransition.builder,
                                  child: KeyedSubtree(
                                    key: ValueKey(
                                      '$isFiltering-${filteredRegular.isEmpty}',
                                    ),
                                    child: filteredRegular.isEmpty
                                        ? (regularEntries.isEmpty
                                              ? PrismEmptyState(
                                                  glyph: AntGlyphs.bookmark,
                                                  title: '暂无自定义书签',
                                                  subtitle:
                                                      '点击上方“添加书签”创建常用网址。',
                                                  action: PrismHoverMotion(
                                                    child:
                                                        prism.OutlinedButton.icon(
                                                          onPressed: _add,
                                                          icon: const PrismGlyph(
                                                            AntGlyphs.add,
                                                            size: 16,
                                                          ),
                                                          label: const Text(
                                                            '添加书签',
                                                          ),
                                                        ),
                                                  ),
                                                )
                                              : PrismEmptyState(
                                                  glyph: AntGlyphs.search,
                                                  title: '没有匹配的书签',
                                                  subtitle:
                                                      '尝试更换关键词，或清空搜索查看全部书签并启用拖拽排序。',
                                                  action: prism.OutlinedButton(
                                                    onPressed: () => setState(
                                                      () => _searchController
                                                          .clear(),
                                                    ),
                                                    child: const Text('清空搜索'),
                                                  ),
                                                ))
                                        : Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            child: isFiltering
                                                ? ListView.builder(
                                                    padding: kPrismListPadding,
                                                    itemCount:
                                                        filteredRegular.length,
                                                    itemBuilder:
                                                        (context, index) =>
                                                            _buildBookmarkRow(
                                                              filteredRegular[index],
                                                              protected: false,
                                                            ),
                                                  )
                                                : prism.PrismReorderableListView(
                                                    padding: kPrismListPadding,
                                                    proxyDecorator:
                                                        (
                                                          child,
                                                          index,
                                                          animation,
                                                        ) => child,
                                                    itemCount:
                                                        regularEntries.length,
                                                    onReorderItem:
                                                        _reorderRegular,
                                                    itemBuilder:
                                                        (context, index) =>
                                                            _buildBookmarkRow(
                                                              regularEntries[index],
                                                              protected: false,
                                                              dragIndex: index,
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
          ),
        ],
      ),
    );
  }
}
