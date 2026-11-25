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

  bool? get _selectAllCheckboxValue =>
      _allVisibleSelected ? true : (_selectedIds.isEmpty ? false : null);

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
    } catch (error) {
      _message('操作失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final tags = _allTags;
    final counts = _tagCounts;
    final profiles = _visibleProfiles;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 248,
            child: prism.Card(
              radius: prism.AppCorner.xl,
              inert: true,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  prism.InfoHeader(
                    info: const prism.Info(label: '标签', glyph: AntGlyphs.tag),
                    actions: [
                      prism.IconButton(
                        tooltip: '新建标签',
                        onPressed: _createTag,
                        icon: const PrismGlyph(AntGlyphs.add, size: 18),
                      ),
                    ],
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
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
                        const SizedBox(width: 6),
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
                        _TagButton(
                          label: '全部实例',
                          count: _profiles.length,
                          selected: _selectedTag == null,
                          onTap: () => setState(() {
                            _selectedTag = null;
                            _selectedIds.clear();
                          }),
                        ),
                        for (final tag in tags)
                          _TagButton(
                            label: tag,
                            count: counts[tag] ?? 0,
                            selected: _selectedTag == tag,
                            onTap: () => setState(() {
                              _selectedTag = tag;
                              _selectedIds.clear();
                            }),
                            onRename: () => _renameTag(tag),
                          ),
                        if (tags.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              '暂无标签，输入名称回车或点击 + 创建',
                              style: prism.AppTextStyle.caption1
                                  .of(context)
                                  .copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrismSectionCard(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PrismBadge(
                        label: '${_selectedIds.length} 个已选',
                        tone: _selectedIds.isEmpty
                            ? PrismTone.neutral
                            : PrismTone.primary,
                      ),
                      PrismTonalButton.icon(
                        onPressed: _saving ? null : _addTags,
                        icon: const PrismGlyph(AntGlyphs.add, size: 17),
                        child: const Text('添加标签'),
                      ),
                      if (tags.isNotEmpty)
                        SizedBox(
                          width: 180,
                          child: PrismDropdownField<String>(
                            value: _removeTagValue.isEmpty
                                ? null
                                : _removeTagValue,
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
                            onChanged: (value) =>
                                setState(() => _removeTagValue = value ?? ''),
                          ),
                        ),
                      prism.OutlinedButton.icon(
                        onPressed: _saving || _removeTagValue.isEmpty
                            ? null
                            : _removeSelectedTag,
                        icon: const PrismGlyph(
                          AntGlyphs.removeCircle,
                          size: 17,
                        ),
                        label: const Text('移除'),
                      ),
                      prism.TextButton.icon(
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : () => setState(_selectedIds.clear),
                        icon: const PrismGlyph(AntGlyphs.close, size: 16),
                        label: const Text('清除选择'),
                      ),
                      prism.IconButton(
                        tooltip: '刷新',
                        onPressed: _saving ? null : _load,
                        icon: const PrismGlyph(AntGlyphs.refresh, size: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: prism.Card(
                    radius: prism.AppCorner.xl,
                    inert: true,
                    padding: EdgeInsets.zero,
                    child: _loading
                        ? const Center(child: PrismProgressIndicator())
                        : profiles.isEmpty
                        ? PrismEmptyState(
                            glyph: AntGlyphs.tag,
                            title: _selectedTag == null
                                ? '暂无实例'
                                : '标签“$_selectedTag”下暂无实例',
                            subtitle: '在实例列表或批量操作中为实例添加标签后即可在此筛选。',
                          )
                        : Column(
                            children: [
                              prism.Surface(
                                color: colors.surfaceContainerLow,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 48,
                                        child: prism.Checkbox(
                                          value: _selectAllCheckboxValue,
                                          onChanged: (_) => _toggleAll(),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 5,
                                        child: Text(
                                          '实例名称',
                                          style: prism.AppTextStyle.footnote
                                              .of(context, emphasized: true),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 5,
                                        child: Text(
                                          '当前标签',
                                          style: prism.AppTextStyle.footnote
                                              .of(context, emphasized: true),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 90,
                                        child: Text(
                                          '状态',
                                          style: prism.AppTextStyle.footnote
                                              .of(context, emphasized: true),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const prism.Divider(height: 1),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: profiles.length,
                                  separatorBuilder: (context, index) =>
                                      const prism.Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final profile = profiles[index];
                                    final id = '${profile['profileId'] ?? ''}';
                                    final selected = _selectedIds.contains(id);
                                    final running = profile['running'] == true;
                                    final profileTags = _tags(profile);
                                    return prism.PressRegion(
                                      onTap: () => _toggle(id),
                                      child: ColoredBox(
                                        color: selected
                                            ? colors.secondaryContainer
                                                  .withValues(alpha: 0.45)
                                            : const Color(0x00000000),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 48,
                                                child: prism.Checkbox(
                                                  value: selected,
                                                  onChanged: (_) => _toggle(id),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 5,
                                                child: Text(
                                                  '${profile['profileName'] ?? '未命名实例'}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: prism
                                                      .AppTextStyle
                                                      .subheadline
                                                      .of(context),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 5,
                                                child: Wrap(
                                                  spacing: 5,
                                                  runSpacing: 4,
                                                  children: profileTags.isEmpty
                                                      ? [
                                                          Text(
                                                            '无标签',
                                                            style: prism
                                                                .AppTextStyle
                                                                .caption1
                                                                .of(context)
                                                                .copyWith(
                                                                  color: colors
                                                                      .onSurfaceVariant,
                                                                ),
                                                          ),
                                                        ]
                                                      : profileTags
                                                            .map(
                                                              (tag) =>
                                                                  PrismBadge(
                                                                    label: tag,
                                                                    tone: PrismTone
                                                                        .neutral,
                                                                  ),
                                                            )
                                                            .toList(),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 90,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: PrismBadge(
                                                    label: running
                                                        ? '运行中'
                                                        : '已停止',
                                                    tone: running
                                                        ? PrismTone.success
                                                        : PrismTone.neutral,
                                                    dot: true,
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
                if (_saving) const prism.LinearProgressIndicator(minHeight: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeSelectedTag() => _removeTag();
}

class _TagButton extends StatelessWidget {
  const _TagButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onRename,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: prism.Surface(
        color: selected ? colors.secondaryContainer : const Color(0x00000000),
        shape: prism.AppShape.full,
        child: Row(
          children: [
            Expanded(
              child: prism.TextButton(
                onPressed: onTap,
                style: prism.ButtonStyle.from(
                  foregroundColor: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                  minimumSize: const Size(0, 42),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Text(
              '$count',
              style: prism.AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
            if (onRename != null)
              prism.IconButton(
                tooltip: '重命名',
                onPressed: onRename,
                icon: const PrismGlyph(AntGlyphs.edit, size: 15),
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
