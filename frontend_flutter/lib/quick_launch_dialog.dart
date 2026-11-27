import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

/// 快速启动对话框（Ctrl+K），对应旧版 React 的 QuickLaunchModal：
/// 按名称/启动码/标签/关键词搜索实例，Enter 直接按输入启动，
/// 支持单击选中、双击启动及行内启动按钮，统一走 BrowserInstanceStartByCode。
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
  String _startingProfileId = '';
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
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = '';
      });
    }
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
            if ('${row['groupId'] ?? ''}'.trim().isNotEmpty)
              '${row['groupId']}'.trim(): '${row['groupName'] ?? '分组'}'.trim(),
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
    final id = '${profile['groupId'] ?? ''}'.trim();
    if (id.isEmpty) return '未分组';
    return _groupNames[id] ?? '分组 $id';
  }

  List<String> _profileTags(Map<String, dynamic> profile) =>
      (profile['tags'] as List? ?? const [])
          .map((tag) => '$tag'.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();

  /// 包含所有分组（含空分组）及未分组项，便于按分组筛选。
  List<Map<String, dynamic>> get _groupOptions {
    final counts = <String, int>{};
    for (final profile in _profiles) {
      final id = '${profile['groupId'] ?? ''}'.trim();
      final key = id.isEmpty ? _ungrouped : id;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final options = <Map<String, dynamic>>[
      for (final entry in _groupNames.entries)
        {'id': entry.key, 'name': entry.value, 'count': counts[entry.key] ?? 0},
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
      final tags = _profileTags(profile);
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

  void _selectProfile(int index, List<Map<String, dynamic>> ordered) {
    setState(() => _selectedIndex = index);
    if (index < 0 || index >= ordered.length) return;
    final key = _profileKey(ordered[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = key.currentContext;
      if (target != null) {
        final spec = PrismMotionSpec.current;
        final motionOn =
            spec.enabled && !MediaQuery.disableAnimationsOf(context);
        Scrollable.ensureVisible(
          target,
          alignment: 0.35,
          duration: motionOn
              ? const Duration(milliseconds: 180)
              : Duration.zero,
          curve: motionOn ? spec.smoothCurve : Curves.linear,
        );
      }
    });
  }

  void _jumpToTag(String tag) {
    setState(() => _activeTag = tag);
    final target = _sectionKey(tag).currentContext;
    if (target != null) {
      final spec = PrismMotionSpec.current;
      final motionOn = spec.enabled && !MediaQuery.disableAnimationsOf(context);
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: motionOn ? const Duration(milliseconds: 220) : Duration.zero,
        curve: motionOn ? spec.smoothCurve : Curves.linear,
      );
    }
  }

  Future<bool> _startByCode(
    String rawCode, {
    bool showFailure = true,
    String profileId = '',
  }) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty || _starting) return false;
    setState(() {
      _starting = true;
      _startingProfileId = profileId;
    });
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
        setState(() {
          _starting = false;
          _startingProfileId = '';
        });
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
    await _startByCode(code, profileId: _profileIdentity(profile));
  }

  Future<void> _onSubmit(List<Map<String, dynamic>> ordered) async {
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
    if (ordered.isNotEmpty) {
      await _startProfile(
        ordered[_selectedIndex.clamp(0, ordered.length - 1)],
      );
    } else {
      showPrismNotice(context, query.isEmpty ? '暂无可启动的实例' : '没有匹配“$query”的实例');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = prism.Theme.of(context).colorScheme;
    final filtered = _filtered;
    final sections = _tagSections(filtered);
    final ordered = [for (final s in sections) ...s.value];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (ordered.isNotEmpty) {
            _selectProfile((_selectedIndex + 1) % ordered.length, ordered);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (ordered.isNotEmpty) {
            _selectProfile(
              (_selectedIndex - 1 + ordered.length) % ordered.length,
              ordered,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            _onSubmit(ordered),
      },
      child: Focus(
        autofocus: true,
        child: PrismDialog(
          title: const Text('快速启动'),
          content: SizedBox(
            width: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrismSearchBar(
                  controller: _query,
                  focusNode: _focusNode,
                  autofocus: true,
                  hintText: '搜索名称、启动码、标签或关键词…',
                  onChanged: (_) => setState(() => _selectedIndex = 0),
                  onSubmitted: () => _onSubmit(ordered),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 36,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
                const SizedBox(height: 10),
                if (sections.isNotEmpty)
                  SizedBox(
                    height: 32,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final section in sections)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: PrismBadge(
                              label: '${section.key} (${section.value.length})',
                              glyph: AntGlyphs.tag,
                              tone: _activeTag == section.key
                                  ? PrismTone.primary
                                  : PrismTone.neutral,
                              onPressed: () => _jumpToTag(section.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: _loading
                        ? const Center(child: PrismProgressIndicator())
                        : _loadError.isNotEmpty
                        ? Center(
                            child: PrismBanner(
                              tone: PrismTone.danger,
                              title: '加载实例失败',
                              message: _loadError,
                              trailing: prism.OutlinedButton.icon(
                                onPressed: _load,
                                icon: const PrismGlyph(
                                  AntGlyphs.refresh,
                                  size: 15,
                                ),
                                label: const Text('重试'),
                              ),
                            ),
                          )
                        : ordered.isEmpty
                        ? PrismEmptyState(
                            glyph: AntGlyphs.browser,
                            title: _profiles.isEmpty ? '暂无实例' : '没有匹配的实例',
                          )
                        : ListView(
                            controller: _listController,
                            padding: kPrismListPadding,
                            children: [
                              for (final section in sections) ...[
                                Padding(
                                  key: _sectionKey(section.key),
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    14,
                                    4,
                                    8,
                                  ),
                                  child: Text(
                                    '${section.key}',
                                    style: prism.AppTextStyle.footnote
                                        .of(context, emphasized: true)
                                        .copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                for (final profile in section.value)
                                  _buildProfileCard(context, profile, ordered),
                              ],
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '↑↓ 选择 · Enter 启动 · 双击快速启动 · Esc 关闭',
                  style: prism.AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
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
            PrismHoverMotion(
              enabled: !(_starting || ordered.isEmpty),
              child: prism.FilledButton.icon(
                onPressed: _starting || ordered.isEmpty
                    ? null
                    : () => _startProfile(
                        ordered[_selectedIndex.clamp(0, ordered.length - 1)],
                      ),
                icon: const PrismGlyph(AntGlyphs.play, size: 15),
                label: const Text('启动选中实例'),
              ),
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

  Widget _buildProfileCard(
    BuildContext context,
    Map<String, dynamic> profile,
    List<Map<String, dynamic>> ordered,
  ) {
    final colors = prism.Theme.of(context).colorScheme;
    final successTone = PrismToneColors.of(context, PrismTone.success);
    final primaryTone = PrismToneColors.of(context, PrismTone.primary);
    final index = ordered.indexOf(profile);
    final selected = index == _selectedIndex;
    final running = profile['running'] == true;
    final tags = _profileTags(profile);
    final launchCode = '${profile['launchCode'] ?? ''}'.trim();
    final identity = _profileIdentity(profile);
    final isStartingThis = _starting && _startingProfileId == identity;

    final spec = PrismMotionSpec.current;
    final motionOn = spec.enabled && !MediaQuery.disableAnimationsOf(context);

    return Padding(
      key: _profileKey(profile),
      padding: const EdgeInsets.only(bottom: 14),
      child: PrismHoverGlow(
        radius: prism.AppCorner.lg,
        child: GestureDetector(
          onDoubleTap: _starting ? null : () => _startProfile(profile),
          child: AnimatedContainer(
            duration: motionOn ? spec.hoverDuration : Duration.zero,
            curve: motionOn ? spec.smoothCurve : Curves.linear,
            decoration: ShapeDecoration(
              color: selected
                  ? colors.secondaryContainer
                  : colors.surfaceContainerLow,
              shape: RoundedSuperellipseBorder(
                borderRadius: prism.AppRadius.lg,
                side: selected
                    ? BorderSide(
                        color: colors.primary.withValues(alpha: 0.45),
                        width: 1.4,
                      )
                    : BorderSide.none,
              ),
            ),
            child: prism.PressRegion(
              onTap: _starting ? null : () => _selectProfile(index, ordered),
              shape: prism.AppShape.lg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    prism.Surface(
                      color: running ? successTone.bg : primaryTone.bg,
                      shape: prism.AppShape.md,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: PrismGlyph(
                          running ? AntGlyphs.play : AntGlyphs.bolt,
                          size: 16,
                          color: running ? successTone.fg : primaryTone.fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${profile['profileName'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: prism.AppTextStyle.subheadline.of(
                                    context,
                                    emphasized: true,
                                  ),
                                ),
                              ),
                              if (running) ...[
                                const SizedBox(width: 10),
                                const PrismBadge(
                                  label: '运行中',
                                  tone: PrismTone.success,
                                  dot: true,
                                ),
                              ],
                            ],
                          ),
                          if (launchCode.isNotEmpty ||
                              (_groupLabel(profile).isNotEmpty &&
                                  _groupLabel(profile) != '未分组')) ...[
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (launchCode.isNotEmpty) '启动码 $launchCode',
                                if (_groupLabel(profile).isNotEmpty &&
                                    _groupLabel(profile) != '未分组')
                                  _groupLabel(profile),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: prism.AppTextStyle.caption1
                                  .of(context)
                                  .copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                for (final tag in tags.take(4))
                                  PrismBadge(
                                    label: tag,
                                    tone: PrismTone.info,
                                    glyph: AntGlyphs.tag,
                                  ),
                                if (tags.length > 4)
                                  PrismBadge(
                                    label: '+${tags.length - 4}',
                                    tone: PrismTone.neutral,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (isStartingThis)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: PrismProgressIndicator(size: 18),
                      )
                    else
                      prism.OutlinedButton.icon(
                        onPressed: _starting || launchCode.isEmpty
                            ? null
                            : () => _startProfile(profile),
                        icon: const PrismGlyph(AntGlyphs.play, size: 14),
                        label: const Text('启动'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterButton(String label, String filter) {
    final selected = _groupFilter == filter;
    final colors = prism.Theme.of(context).colorScheme;
    final spec = PrismMotionSpec.current;
    final motionOn = spec.enabled && !MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: PrismHoverMotion(
        hoverScale: 1.04,
        pressScale: 0.95,
        child: prism.PressRegion(
          onTap: () => setState(() {
            _groupFilter = filter;
            _selectedIndex = 0;
            _activeTag = '';
          }),
          shape: prism.AppShape.full,
          child: AnimatedContainer(
            duration: motionOn ? spec.hoverDuration : Duration.zero,
            curve: motionOn ? spec.smoothCurve : Curves.linear,
            decoration: ShapeDecoration(
              color: selected
                  ? colors.primaryContainer
                  : colors.surfaceContainerLow,
              shape: prism.AppShape.full,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: prism.AppTextStyle.footnote
                  .of(context, emphasized: selected)
                  .copyWith(
                    color: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
