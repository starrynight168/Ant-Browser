import 'package:material_ui/material_ui.dart';

import 'prism_components.dart';

import 'wails_bridge.dart';

class TagsPage extends StatefulWidget {
  const TagsPage({super.key});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await WailsBridge.call('BrowserProfileList');
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

  void _message(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _createTag() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标签名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    final tag = value?.trim() ?? '';
    if (tag.isEmpty) return;
    if (_allTags.contains(tag)) {
      _message('标签已存在');
      return;
    }
    setState(() => _pendingTags.add(tag));
  }

  Future<void> _renameTag(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final value = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
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
        await WailsBridge.call('BrowserRenameTag', [oldName, newName]);
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
    final value = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('批量添加标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '多个标签用逗号分隔'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    final tags = (value ?? '')
        .split(RegExp('[,，]'))
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
      await WailsBridge.call(method, args);
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
    final tags = _allTags;
    final counts = _tagCounts;
    final profiles = _visibleProfiles;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 220,
            child: PrismCard(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '标签',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: '新建标签',
                          onPressed: _createTag,
                          icon: const Icon(Icons.add, size: 19),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
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
                              '暂无标签，点击 + 创建',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
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
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrismCard(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${_selectedIds.length} 个已选'),
                        FilledButton.tonalIcon(
                          onPressed: _saving ? null : _addTags,
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('添加标签'),
                        ),
                        if (tags.isNotEmpty)
                          SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String>(
                              initialValue: _removeTagValue.isEmpty
                                  ? null
                                  : _removeTagValue,
                              decoration: const InputDecoration(
                                hintText: '选择要移除的标签',
                                isDense: true,
                              ),
                              items: tags
                                  .map(
                                    (tag) => DropdownMenuItem(
                                      value: tag,
                                      child: Text(tag),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _removeTagValue = value ?? ''),
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: _saving || _removeTagValue.isEmpty
                              ? null
                              : _removeSelectedTag,
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 17,
                          ),
                          label: const Text('移除'),
                        ),
                        TextButton.icon(
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : () => setState(_selectedIds.clear),
                          icon: const Icon(Icons.close, size: 17),
                          label: const Text('清除选择'),
                        ),
                        IconButton(
                          tooltip: '刷新',
                          onPressed: _saving ? null : _load,
                          icon: const Icon(Icons.refresh, size: 19),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: PrismCard(
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : profiles.isEmpty
                        ? const Center(child: Text('暂无实例'))
                        : Column(
                            children: [
                              Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      child: Checkbox(
                                        value: _allVisibleSelected,
                                        onChanged: (_) => _toggleAll(),
                                      ),
                                    ),
                                    const Expanded(
                                      flex: 5,
                                      child: Text(
                                        '实例名称',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Expanded(
                                      flex: 5,
                                      child: Text(
                                        '当前标签',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 84,
                                      child: Text(
                                        '状态',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: profiles.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final profile = profiles[index];
                                    final id = '${profile['profileId'] ?? ''}';
                                    final selected = _selectedIds.contains(id);
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      color: selected
                                          ? Theme.of(context)
                                                .colorScheme
                                                .secondaryContainer
                                          : Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerLowest,
                                      child: InkWell(
                                        onTap: () => _toggle(id),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 40,
                                                child: Checkbox(
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
                                                ),
                                              ),
                                              Expanded(
                                                flex: 5,
                                                child: Wrap(
                                                  spacing: 5,
                                                  children:
                                                      _tags(profile).isEmpty
                                                      ? [
                                                          Text(
                                                            '无标签',
                                                            style: TextStyle(
                                                              color: Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ]
                                                      : _tags(profile)
                                                            .map(
                                                              (tag) => Chip(
                                                                label: Text(
                                                                  tag,
                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                      ),
                                                                ),
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                              ),
                                                            )
                                                            .toList(),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 84,
                                                child: Text(
                                                  profile['running'] == true
                                                      ? '运行中'
                                                      : '已停止',
                                                  style: TextStyle(
                                                    color:
                                                        profile['running'] ==
                                                            true
                                                        ? Theme.of(context)
                                                              .colorScheme
                                                              .tertiary
                                                        : Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                    fontSize: 12,
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
                if (_saving) const LinearProgressIndicator(minHeight: 2),
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (onRename != null)
              IconButton(
                tooltip: '重命名',
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined, size: 16),
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
