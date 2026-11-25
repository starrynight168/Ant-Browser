import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

/// 快速启动对话框（Ctrl+K），对应旧版 React 的 QuickLaunchModal：
/// 按名称/启动码/标签/关键词搜索实例，Enter 直接按输入启动，
/// 点击实例按其启动码启动，统一走 BrowserInstanceStartByCode。
class QuickLaunchDialog extends StatefulWidget {
  const QuickLaunchDialog({super.key});

  @override
  State<QuickLaunchDialog> createState() => _QuickLaunchDialogState();
}

class _QuickLaunchDialogState extends State<QuickLaunchDialog> {
  static const _allGroups = '__all__';
  static const _ungrouped = '__ungrouped__';

  final _query = TextEditingController();
  final _focusNode = FocusNode();
  final _listController = ScrollController();
  List<Map<String, dynamic>> _profiles = [];
  Map<String, String> _groupNames = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  final Map<String, GlobalKey> _profileKeys = {};
  bool _loading = true;
  bool _starting = false;
  String _groupFilter = _allGroups;
  String _activeTag = '';
  int _selectedIndex = 0;
  String _loadError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _focusNode.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profiles = await AppBridge.call('BrowserProfileList');
      final groups = await AppBridge.call('ListGroups');
      if (!mounted) return;
      final loadedProfiles =
          (profiles as List? ?? [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
            ..sort((a, b) {
              final running =
                  (b['running'] == true ? 1 : 0) -
                  (a['running'] == true ? 1 : 0);
              if (running != 0) return running;
              return '${a['profileName'] ?? ''}'.toLowerCase().compareTo(
                '${b['profileName'] ?? ''}'.toLowerCase(),
              );
            });
      setState(() {
        _profiles = loadedProfiles;
        _groupNames = {
          for (final row in (groups as List? ?? []).whereType<Map>())
            '${row['groupId']}': '${row['groupName'] ?? '分组'}',
        };
        _loading = false;
        _loadError = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  String _groupLabel(Map<String, dynamic> profile) {
    final id = '${profile['groupId'] ?? ''}';
    if (id.isEmpty) return '未分组';
    return _groupNames[id] ?? '分组 $id';
  }

  List<Map<String, dynamic>> get _groupOptions {
    final counts = <String, int>{};
    for (final profile in _profiles) {
      final id = '${profile['groupId'] ?? ''}'.trim();
      final key = id.isEmpty ? _ungrouped : id;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final options = <Map<String, dynamic>>[
      for (final entry in _groupNames.entries)
        if ((counts[entry.key] ?? 0) > 0)
          {'id': entry.key, 'name': entry.value, 'count': counts[entry.key]},
      for (final entry in counts.entries)
        if (entry.key != _ungrouped && !_groupNames.containsKey(entry.key))
          {'id': entry.key, 'name': '分组 ${entry.key}', 'count': entry.value},
      if ((counts[_ungrouped] ?? 0) > 0)
        {'id': _ungrouped, 'name': '未分组', 'count': counts[_ungrouped]},
    ];
    options.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return options;
  }

  List<Map<String, dynamic>> get _groupFiltered {
    if (_groupFilter == _allGroups) return _profiles;
    if (_groupFilter == _ungrouped) {
      return _profiles
          .where((profile) => '${profile['groupId'] ?? ''}'.trim().isEmpty)
          .toList();
    }
    return _profiles
        .where(
          (profile) => '${profile['groupId'] ?? ''}'.trim() == _groupFilter,
        )
        .toList();
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _groupFiltered;
    return _groupFiltered.where((profile) {
      final searchable = [
        profile['profileName'],
        profile['launchCode'],
        ...(profile['tags'] as List? ?? const []),
        ...(profile['keywords'] as List? ?? const []),
      ].map((item) => item?.toString() ?? '').join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _tagSections(
    List<Map<String, dynamic>> profiles,
  ) {
    final buckets = <String, List<Map<String, dynamic>>>{};
    for (final profile in profiles) {
      final tags = (profile['tags'] as List? ?? const [])
          .map((tag) => '$tag'.trim())
          .where((tag) => tag.isNotEmpty);
      final tag = tags.isEmpty ? '未打标签' : tags.first;
      buckets.putIfAbsent(tag, () => []).add(profile);
    }
    final tags = buckets.keys.toList()
      ..sort((a, b) {
        if (a == '未打标签') return 1;
        if (b == '未打标签') return -1;
        return a.compareTo(b);
      });
    return [for (final tag in tags) MapEntry(tag, buckets[tag]!)];
  }

  String _profileIdentity(Map<String, dynamic> profile) =>
      '${profile['profileId'] ?? profile['launchCode'] ?? profile['profileName'] ?? ''}';

  GlobalKey _sectionKey(String tag) =>
      _sectionKeys.putIfAbsent(tag, GlobalKey.new);

  GlobalKey _profileKey(Map<String, dynamic> profile) =>
      _profileKeys.putIfAbsent(_profileIdentity(profile), GlobalKey.new);

  void _selectProfile(int index, List<Map<String, dynamic>> filtered) {
    setState(() => _selectedIndex = index);
    if (index < 0 || index >= filtered.length) return;
    final key = _profileKey(filtered[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.35,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  void _jumpToTag(String tag) {
    setState(() => _activeTag = tag);
    final target = _sectionKey(tag).currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: const Duration(milliseconds: 220),
      );
    }
  }

  Future<bool> _startByCode(String rawCode, {bool showFailure = true}) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty || _starting) return false;
    setState(() => _starting = true);
    try {
      final result = await AppBridge.call('BrowserInstanceStartByCode', [code]);
      if (!mounted) return true;
      final warning = result is Map
          ? '${result['runtimeWarning'] ?? ''}'.trim()
          : '';
      if (warning.isNotEmpty) {
        final name = result is Map ? '${result['profileName'] ?? code}' : code;
        showPrismNotice(context, '实例「$name」已启动：$warning');
      }
      Navigator.of(context).pop(true);
      return true;
    } catch (error) {
      if (mounted) {
        if (showFailure) showPrismNotice(context, '按启动码启动失败：$error');
        setState(() => _starting = false);
      }
      return false;
    }
  }

  Future<void> _startProfile(Map<String, dynamic> profile) async {
    final code = '${profile['launchCode'] ?? ''}'.trim();
    if (code.isEmpty) {
      showPrismNotice(context, '该实例尚未分配启动码，请先在实例列表设置');
      return;
    }
    await _startByCode(code);
  }

  Future<void> _onSubmit(List<Map<String, dynamic>> filtered) async {
    final query = _query.text.trim();
    if (query.isNotEmpty) {
      final exactName = _profiles.any(
        (profile) =>
            '${profile['profileName'] ?? ''}'.trim().toLowerCase() ==
            query.toLowerCase(),
      );
      if (!exactName && await _startByCode(query, showFailure: false)) {
        return;
      }
    }
    if (filtered.isNotEmpty) {
      await _startProfile(
        filtered[_selectedIndex.clamp(0, filtered.length - 1)],
      );
    } else {
      showPrismNotice(context, query.isEmpty ? '暂无可启动的实例' : '没有匹配“$query”的实例');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final sections = _tagSections(filtered);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (filtered.isNotEmpty) {
            _selectProfile((_selectedIndex + 1) % filtered.length, filtered);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (filtered.isNotEmpty) {
            _selectProfile(
              (_selectedIndex - 1 + filtered.length) % filtered.length,
              filtered,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            _onSubmit(filtered),
      },
      child: Focus(
        autofocus: true,
        child: PrismDialog(
          title: const Text('快速启动'),
          content: SizedBox(
            width: 680,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrismTextField(
                  controller: _query,
                  focusNode: _focusNode,
                  autofocus: true,
                  enabled: !_starting,
                  onChanged: (_) => setState(() => _selectedIndex = 0),
                  onSubmitted: (_) => _onSubmit(filtered),
                  decoration: const PrismInputDecoration(
                    labelText: '输入启动码或搜索实例',
                    hintText: '名称 / 启动码 / 标签 / 关键词，Enter 启动',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _filterButton('全部分组（${_profiles.length}）', _allGroups),
                      for (final group in _groupOptions)
                        _filterButton(
                          '${group['name']}（${group['count']}）',
                          '${group['id']}',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                if (sections.isNotEmpty)
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final section in sections)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: prism.TextButton(
                              onPressed: () => _jumpToTag(section.key),
                              child: Text(
                                '${section.key} (${section.value.length})',
                                style: TextStyle(
                                  fontWeight: _activeTag == section.key
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 320,
                  child: _loading
                      ? const Center(child: PrismProgressIndicator())
                      : _loadError.isNotEmpty
                      ? Center(
                          child: prism.TextButton(
                            onPressed: _load,
                            child: Text('加载失败，点击重试：$_loadError'),
                          ),
                        )
                      : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _profiles.isEmpty ? '暂无实例，请先创建' : '没有匹配的实例',
                          ),
                        )
                      : ListView(
                          controller: _listController,
                          children: [
                            for (final section in sections) ...[
                              Padding(
                                key: _sectionKey(section.key),
                                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                                child: Text(
                                  '${section.key} · ${section.value.length} 个实例',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: prism.Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                              for (final profile in section.value)
                                Builder(
                                  builder: (context) {
                                    final index = filtered.indexOf(profile);
                                    final selected = index == _selectedIndex;
                                    final running = profile['running'] == true;
                                    return PrismCard(
                                      key: _profileKey(profile),
                                      margin: const EdgeInsets.only(bottom: 6),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? prism.Theme.of(context)
                                                    .colorScheme
                                                    .secondaryContainer
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: PrismListTile(
                                          leading: Icon(
                                            running
                                                ? Icons.play_circle_outline
                                                : Icons.bolt_outlined,
                                            color: running
                                                ? prism.Theme.of(context)
                                                      .colorScheme
                                                      .tertiary
                                                : null,
                                          ),
                                          title: Text(
                                            '${profile['profileName'] ?? ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            '启动码 ${profile['launchCode'] ?? '未分配'} · '
                                            '${_groupLabel(profile)}'
                                            '${running ? ' · 运行中' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          onTap: _starting
                                              ? null
                                              : () => _selectProfile(
                                                  index,
                                                  filtered,
                                                ),
                                          trailing: _starting && selected
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      PrismProgressIndicator(),
                                                )
                                              : Icon(
                                                  selected
                                                      ? Icons
                                                            .check_circle_outline
                                                      : Icons.chevron_right,
                                                ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  '↑↓选择实例 · Enter 启动 · 点击实例后使用下方按钮启动',
                  style: TextStyle(
                    fontSize: 12,
                    color: prism.Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: _starting || _query.text.trim().isEmpty
                  ? null
                  : () => _startByCode(_query.text),
              child: const Text('按启动码启动'),
            ),
            prism.TextButton(
              onPressed: _starting || filtered.isEmpty
                  ? null
                  : () => _startProfile(
                      filtered[_selectedIndex.clamp(0, filtered.length - 1)],
                    ),
              child: const Text('启动选中实例'),
            ),
            prism.TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterButton(String label, String filter) {
    final selected = _groupFilter == filter;
    final colors = prism.Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() {
          _groupFilter = filter;
          _selectedIndex = 0;
          _activeTag = '';
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : colors.surface,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(label, style: TextStyle(color: colors.onSurface)),
        ),
      ),
    );
  }
}
