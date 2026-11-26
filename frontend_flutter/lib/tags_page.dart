import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

class TagsPage extends StatefulWidget {
  const TagsPage({super.key});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  final _quickTagController = TextEditingController();
  List<Map<String, dynamic>> _profiles = [];
  final Set<String> _selectedIds = {};
  final List<String> _pendingTags = [];
  String? _selectedTag;
  String _removeTagValue = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quickTagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await AppBridge.call('BrowserProfileList');
      final profiles = (result is List ? result : const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final used = profiles.expand((profile) => _tags(profile)).toSet();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _pendingTags.removeWhere(used.contains);
      });
    } catch (error) {
      if (mounted) _message('读取实例失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _tags(Map<String, dynamic> profile) =>
      (profile['tags'] as List?)
          ?.map((tag) => '$tag')
          .where((tag) => tag.trim().isNotEmpty)
          .toList() ??
      const [];

  List<String> get _allTags =>
      {..._profiles.expand(_tags), ..._pendingTags}.toList()..sort();

  List<Map<String, dynamic>> get _visibleProfiles => _selectedTag == null
      ? _profiles
      : _profiles
            .where((profile) => _tags(profile).contains(_selectedTag))
            .toList();

  Map<String, int> get _tagCounts {
    final counts = <String, int>{};
    for (final profile in _profiles) {
      for (final tag in _tags(profile)) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts;
  }

  bool get _allVisibleSelected =>
      _visibleProfiles.isNotEmpty &&
      _visibleProfiles.every(
        (profile) => _selectedIds.contains('${profile['profileId'] ?? ''}'),
      );

  bool? get _selectAllCheckboxValue {
    if (_allVisibleSelected) return true;
    final hasVisibleSelection = _visibleProfiles.any(
      (profile) => _selectedIds.contains('${profile['profileId'] ?? ''}'),
    );
    return hasVisibleSelection ? null : false;
  }

  void _message(String message) {
    if (mounted) showPrismNotice(context, message);
  }

  void _toggle(String id) => setState(() {
    if (!_selectedIds.add(id)) _selectedIds.remove(id);
  });

  void _toggleAll() => setState(() {
    if (_allVisibleSelected) {
      _selectedIds.clear();
    } else {
      _selectedIds.addAll(
        _visibleProfiles.map((profile) => '${profile['profileId'] ?? ''}'),
      );
    }
  });

  void _registerNewTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) return;
    if (_allTags.contains(tag)) {
      _message('标签已存在');
      setState(() {
        _selectedTag = tag;
        _selectedIds.clear();
      });
      return;
    }
    setState(() {
      _pendingTags.add(tag);
      _selectedTag = tag;
      _selectedIds.clear();
    });
  }

  void _quickAddTag(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _quickTagController.clear();
    _registerNewTag(trimmed);
  }

  Future<void> _createTag() async {
    final controller = TextEditingController();
    final value = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('新建标签'),
        content: PrismTextField(
          controller: controller,
          autofocus: true,
          decoration: const PrismInputDecoration(labelText: '标签名称'),
          onSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) _registerNewTag(value);
  }

  Future<void> _renameTag(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final value = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('重命名标签'),
        content: PrismTextField(
          controller: controller,
          autofocus: true,
          decoration: const PrismInputDecoration(labelText: '新名称'),
          onSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    final newName = value?.trim() ?? '';
    if (newName.isEmpty || newName == oldName) return;
    if (_allTags.contains(newName)) {
      _message('标签名称已存在');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_pendingTags.contains(oldName)) {
        setState(() {
          _pendingTags.remove(oldName);
          _pendingTags.add(newName);
        });
      } else {
        await AppBridge.call('BrowserRenameTag', [oldName, newName]);
        await _load();
      }
      if (_selectedTag == oldName) setState(() => _selectedTag = newName);
    } catch (error) {
      _message('重命名失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTags() async {
    if (_selectedIds.isEmpty) {
      _message('先选择要操作的实例');
      return;
    }
    final controller = TextEditingController();
    final value = await showPrismDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('批量添加标签'),
        content: PrismTextField(
          controller: controller,
          autofocus: true,
          decoration: const PrismInputDecoration(hintText: '多个标签用逗号或空格分隔'),
          onSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    final tags = (value ?? '')
        .split(RegExp(r'[,，\s]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    if (tags.isEmpty) return;
    await _runBatch('BrowserProfileBatchSetTags', [
      _selectedIds.toList(),
      tags,
      false,
    ], '已添加标签');
  }

  Future<void> _removeTag() async {
    if (_selectedIds.isEmpty) {
      _message('先选择要操作的实例');
      return;
    }
    if (_removeTagValue.isEmpty) return;
    await _runBatch('BrowserProfileBatchRemoveTags', [
      _selectedIds.toList(),
      [_removeTagValue],
    ], '已移除标签');
    setState(() => _removeTagValue = '');
  }

  Future<void> _runBatch(
    String method,
    List<Object?> args,
    String success,
  ) async {
    setState(() => _saving = true);
    try {
      await AppBridge.call(method, args);
      _message('$success（${_selectedIds.length} 个实例）');
      await _load();
      final visibleIds = _visibleProfiles
          .map((profile) => '${profile['profileId'] ?? ''}')
          .toSet();
      if (mounted) setState(() => _selectedIds.retainAll(visibleIds));
    } catch (error) {
      _message('操作失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildOverviewStrip(
    List<String> tags,
    Map<String, int> counts,
    List<Map<String, dynamic>> profiles,
  ) {
    final runningCount = _profiles.where((p) => p['running'] == true).length;
    final tiles = [
      PrismMetricTile(
        label: '标签总数',
        value: '${tags.length}',
        subtitle: tags.isNotEmpty && counts.length != tags.length
            ? '已使用 ${counts.length} 个'
            : null,
        glyph: AntGlyphs.tag,
        tone: PrismTone.primary,
        onPressed: _selectedTag == null
            ? null
            : () => setState(() {
                _selectedTag = null;
                _selectedIds.clear();
              }),
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '实例总数',
        value: '${_profiles.length}',
        subtitle: runningCount > 0 ? '运行中 $runningCount 个' : null,
        glyph: AntGlyphs.browser,
        tone: PrismTone.info,
        onPressed: _selectedTag == null
            ? null
            : () => setState(() {
                _selectedTag = null;
                _selectedIds.clear();
              }),
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '当前筛选实例',
        value: '${profiles.length}',
        subtitle: _selectedTag,
        glyph: AntGlyphs.search,
        tone: PrismTone.success,
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '已选实例',
        value: '${_selectedIds.length}',
        glyph: AntGlyphs.factCheck,
        tone: _selectedIds.isEmpty ? PrismTone.neutral : PrismTone.warning,
        onPressed: _selectedIds.isEmpty
            ? null
            : () => setState(_selectedIds.clear),
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

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final tags = _allTags;
    final counts = _tagCounts;
    final profiles = _visibleProfiles;
    final activeRemoveTag =
        _removeTagValue.isNotEmpty && tags.contains(_removeTagValue)
        ? _removeTagValue
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewStrip(tags, counts, profiles),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 248,
                  child: PrismHoverCard(
                    staggerIndex: 4,
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
                            label: '标签',
                            glyph: AntGlyphs.tag,
                          ),
                          actions: [
                            prism.IconButton(
                              tooltip: '新建标签',
                              onPressed: _createTag,
                              icon: const PrismGlyph(AntGlyphs.add, size: 18),
                            ),
                          ],
                          padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
                        ),
                        const prism.Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: PrismTextField(
                                  controller: _quickTagController,
                                  decoration: const PrismInputDecoration(
                                    hintText: '快速添加标签（回车）',
                                    isDense: true,
                                  ),
                                  onSubmitted: _quickAddTag,
                                ),
                              ),
                              const SizedBox(width: 12),
                              prism.IconButton(
                                tooltip: '添加',
                                onPressed: () =>
                                    _quickAddTag(_quickTagController.text),
                                icon: const PrismGlyph(AntGlyphs.add, size: 17),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(8),
                            children: [
                              PrismSlidingRail<String>(
                                itemHeight: 44,
                                gap: 2,
                                showDividers: true,
                                selectedValue: _selectedTag ?? '',
                                onSelected: (value) => setState(() {
                                  _selectedTag = value.isEmpty ? null : value;
                                  _selectedIds.clear();
                                }),
                                items: [
                                  PrismSlidingRailItem<String>(
                                    value: '',
                                    title: '全部实例',
                                    glyph: AntGlyphs.browser,
                                    trailing: PrismBadge(
                                      label: '${_profiles.length}',
                                      tone: _selectedTag == null
                                          ? PrismTone.primary
                                          : PrismTone.neutral,
                                    ),
                                  ),
                                  for (var i = 0; i < tags.length; i++)
                                    PrismSlidingRailItem<String>(
                                      value: tags[i],
                                      title: tags[i],
                                      glyph: AntGlyphs.tag,
                                      sectionHeader: i == 0 ? '标签分组' : null,
                                      sectionTrailing: i == 0
                                          ? '${tags.length}'
                                          : null,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          PrismBadge(
                                            label: '${counts[tags[i]] ?? 0}',
                                            tone: _selectedTag == tags[i]
                                                ? PrismTone.primary
                                                : PrismTone.neutral,
                                          ),
                                          const SizedBox(width: 6),
                                          prism.IconButton(
                                            tooltip: '重命名',
                                            style: prism.ButtonStyle(
                                              minimumSize: const Size.square(
                                                28,
                                              ),
                                              maximumSize: const Size.square(
                                                28,
                                              ),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize: prism
                                                  .TapTargetSize
                                                  .shrinkWrap,
                                              side:
                                                  const WidgetStatePropertyAll(
                                                    BorderSide.none,
                                                  ),
                                              backgroundColor:
                                                  WidgetStateProperty.fromMap({
                                                    WidgetState.hovered: colors
                                                        .onSurface
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    WidgetState.any:
                                                        const Color(0x00000000),
                                                  }),
                                            ),
                                            onPressed: () =>
                                                _renameTag(tags[i]),
                                            icon: const PrismGlyph(
                                              AntGlyphs.edit,
                                              size: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              if (tags.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Text(
                                    '暂无标签',
                                    style: prism.AppTextStyle.caption1
                                        .of(context)
                                        .copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrismHoverCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        radius: prism.AppCorner.xl,
                        staggerIndex: 5,
                        staggerDelay: const Duration(milliseconds: 45),
                        hoverGlow: true,
                        lift: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  PrismBadge(
                                    label: '${_selectedIds.length} 个已选',
                                    tone: _selectedIds.isEmpty
                                        ? PrismTone.neutral
                                        : PrismTone.primary,
                                  ),
                                  PrismHoverMotion(
                                    enabled: !_saving,
                                    child: prism.FilledButton.icon(
                                      onPressed: _saving ? null : _addTags,
                                      icon: const PrismGlyph(
                                        AntGlyphs.add,
                                        size: 16,
                                      ),
                                      label: const Text('添加标签'),
                                    ),
                                  ),
                                  if (tags.isNotEmpty)
                                    SizedBox(
                                      width: 180,
                                      child: PrismDropdownField<String>(
                                        value: activeRemoveTag,
                                        decoration: const PrismInputDecoration(
                                          hintText: '选择要移除的标签',
                                          isDense: true,
                                        ),
                                        items: tags
                                            .map(
                                              (tag) => PrismDropdownItem(
                                                value: tag,
                                                child: Text(tag),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (value) => setState(
                                          () => _removeTagValue = value ?? '',
                                        ),
                                      ),
                                    ),
                                  PrismHoverMotion(
                                    enabled:
                                        !_saving && activeRemoveTag != null,
                                    child: prism.OutlinedButton.icon(
                                      onPressed:
                                          _saving || activeRemoveTag == null
                                          ? null
                                          : _removeSelectedTag,
                                      icon: const PrismGlyph(
                                        AntGlyphs.removeCircle,
                                        size: 16,
                                      ),
                                      label: const Text('移除'),
                                    ),
                                  ),
                                  prism.TextButton.icon(
                                    onPressed: _selectedIds.isEmpty
                                        ? null
                                        : () => setState(_selectedIds.clear),
                                    icon: const PrismGlyph(
                                      AntGlyphs.close,
                                      size: 16,
                                    ),
                                    label: const Text('清除选择'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            prism.IconButton(
                              tooltip: '刷新',
                              onPressed: _saving ? null : _load,
                              icon: const PrismGlyph(
                                AntGlyphs.refresh,
                                size: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: PrismHoverCard(
                          staggerIndex: 6,
                          staggerDelay: const Duration(milliseconds: 45),
                          radius: prism.AppCorner.xl,
                          padding: EdgeInsets.zero,
                          hoverGlow: true,
                          lift: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              prism.InfoHeader(
                                info: prism.Info(
                                  label: _selectedTag == null
                                      ? '全部实例'
                                      : '标签：$_selectedTag',
                                  glyph: AntGlyphs.browser,
                                ),
                                actions: [
                                  PrismBadge(
                                    label: '${profiles.length} 个',
                                    tone: profiles.isEmpty
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
                              if (_saving)
                                const prism.LinearProgressIndicator(
                                  minHeight: 2,
                                ),
                              Expanded(
                                child: _loading
                                    ? const Center(
                                        child: PrismProgressIndicator(),
                                      )
                                    : prism.PageTransitionSwitcher(
                                        duration: PrismMotionSpec
                                            .current
                                            .pageDuration,
                                        transitionBuilder:
                                            PrismSlideThroughTransition.builder,
                                        child: KeyedSubtree(
                                          key: ValueKey(
                                            '$_selectedTag-${profiles.isEmpty}',
                                          ),
                                          child: profiles.isEmpty
                                              ? PrismEmptyState(
                                                  glyph: AntGlyphs.tag,
                                                  title: _selectedTag == null
                                                      ? '暂无实例'
                                                      : '标签“$_selectedTag”下暂无实例',
                                                )
                                              : Column(
                                                  children: [
                                                    prism.Surface(
                                                      color: colors
                                                          .surfaceContainerLow,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 16,
                                                              vertical: 8,
                                                            ),
                                                        child: Row(
                                                          children: [
                                                            SizedBox(
                                                              width: 48,
                                                              child: prism.Checkbox(
                                                                value:
                                                                    _selectAllCheckboxValue,
                                                                onChanged: (_) =>
                                                                    _toggleAll(),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Expanded(
                                                              flex: 5,
                                                              child: Text(
                                                                '实例名称',
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: prism
                                                                    .AppTextStyle
                                                                    .footnote
                                                                    .of(
                                                                      context,
                                                                      emphasized:
                                                                          true,
                                                                    ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            Expanded(
                                                              flex: 5,
                                                              child: Text(
                                                                '当前标签',
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: prism
                                                                    .AppTextStyle
                                                                    .footnote
                                                                    .of(
                                                                      context,
                                                                      emphasized:
                                                                          true,
                                                                    ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            SizedBox(
                                                              width: 96,
                                                              child: Text(
                                                                '状态',
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: prism
                                                                    .AppTextStyle
                                                                    .footnote
                                                                    .of(
                                                                      context,
                                                                      emphasized:
                                                                          true,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const prism.Divider(
                                                      height: 1,
                                                    ),
                                                    Expanded(
                                                      child: ListView.separated(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              bottom: 8,
                                                            ),
                                                        itemCount:
                                                            profiles.length,
                                                        separatorBuilder:
                                                            (context, index) =>
                                                                const prism.Divider(
                                                                  height: 1,
                                                                ),
                                                        itemBuilder: (context, index) {
                                                          final profile =
                                                              profiles[index];
                                                          final id =
                                                              '${profile['profileId'] ?? ''}';
                                                          final selected =
                                                              _selectedIds
                                                                  .contains(id);
                                                          final running =
                                                              profile['running'] ==
                                                              true;
                                                          final profileTags =
                                                              _tags(profile);
                                                          return prism.PressRegion(
                                                            onTap: () =>
                                                                _toggle(id),
                                                            child: ColoredBox(
                                                              color: selected
                                                                  ? colors
                                                                        .secondaryContainer
                                                                        .withValues(
                                                                          alpha:
                                                                              0.45,
                                                                        )
                                                                  : const Color(
                                                                      0x00000000,
                                                                    ),
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          16,
                                                                      vertical:
                                                                          10,
                                                                    ),
                                                                child: Row(
                                                                  children: [
                                                                    SizedBox(
                                                                      width: 48,
                                                                      child: prism.Checkbox(
                                                                        value:
                                                                            selected,
                                                                        onChanged:
                                                                            (
                                                                              _,
                                                                            ) => _toggle(
                                                                              id,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 8,
                                                                    ),
                                                                    Expanded(
                                                                      flex: 5,
                                                                      child: Text(
                                                                        '${profile['profileName'] ?? '未命名实例'}',
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style: prism
                                                                            .AppTextStyle
                                                                            .subheadline
                                                                            .of(
                                                                              context,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 12,
                                                                    ),
                                                                    Expanded(
                                                                      flex: 5,
                                                                      child: Wrap(
                                                                        spacing:
                                                                            8,
                                                                        runSpacing:
                                                                            6,
                                                                        children:
                                                                            profileTags.isEmpty
                                                                            ? const []
                                                                            : profileTags.map((tag) => PrismBadge(label: tag, tone: PrismTone.neutral)).toList(),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 12,
                                                                    ),
                                                                    SizedBox(
                                                                      width: 96,
                                                                      child: Align(
                                                                        alignment:
                                                                            Alignment.centerLeft,
                                                                        child: PrismBadge(
                                                                          label:
                                                                              running
                                                                              ? '运行中'
                                                                              : '已停止',
                                                                          tone:
                                                                              running
                                                                              ? PrismTone.success
                                                                              : PrismTone.neutral,
                                                                          dot:
                                                                              true,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        },
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
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeSelectedTag() => _removeTag();
}
