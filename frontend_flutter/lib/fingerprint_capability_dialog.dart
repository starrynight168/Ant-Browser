import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import 'prism_components.dart';
import 'prism_glyphs.dart';

Future<void> showFingerprintCapabilityDialog({
  required BuildContext context,
  required String title,
  required String kernelBadgePrefix,
  required Map<String, dynamic> table,
  List<Widget> extraSections = const [],
}) async {
  final versions = (table['versions'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  final groups = (table['groups'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  final currentKey = (table['currentVersionKey'] ?? '').toString();
  final notes = (table['notes'] as List? ?? const [])
      .map((e) => e.toString())
      .where((e) => e.trim().isNotEmpty)
      .toList();
  final warnings = (table['warnings'] as List? ?? const [])
      .map((e) => e.toString())
      .where((e) => e.trim().isNotEmpty)
      .toList();
  final currentLabel = versions
      .where((v) => v['key'] == currentKey)
      .map((v) => (v['label'] ?? '').toString())
      .firstOrNull;

  await showPrismDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (context) => PrismDialog(
      title: Text(title),
      content: SizedBox(
        width: 820,
        height: 600,
        child: ListView(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PrismBadge(
                  label: currentLabel != null && currentLabel.isNotEmpty
                      ? '$kernelBadgePrefix：$currentLabel'
                      : '$kernelBadgePrefix：未识别',
                  tone: currentLabel != null
                      ? PrismTone.primary
                      : PrismTone.neutral,
                ),
                PrismBadge(
                  label: '能力表更新：${table['updatedAt'] ?? '-'}',
                  tone: PrismTone.neutral,
                ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              PrismBanner(
                tone: PrismTone.warning,
                message: warnings.join(' '),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              PrismBanner(tone: PrismTone.info, message: notes.join(' ')),
            ],
            const SizedBox(height: 16),
            for (final group in groups) ...[
              Builder(
                builder: (context) {
                  final items = (group['items'] as List? ?? const [])
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList();
                  return PrismSectionCard(
                    title: (group['label'] ?? group['key'] ?? '').toString(),
                    glyph: AntGlyphs.tune,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) ...[
                            const SizedBox(height: 10),
                            const prism.Divider(height: 1),
                            const SizedBox(height: 10),
                          ],
                          _buildCapabilityRow(
                            context,
                            items[i],
                            versions,
                            currentKey,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
            ],
            ...extraSections,
          ],
        ),
      ),
      actions: [
        prism.TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Widget _buildCapabilityRow(
  BuildContext context,
  Map<String, dynamic> item,
  List<Map<String, dynamic>> versions,
  String currentKey,
) {
  final colors = prism.Theme.of(context).colorScheme;
  final support = item['support'] is Map
      ? Map<String, dynamic>.from(item['support'] as Map)
      : const <String, dynamic>{};
  final note = (item['note'] ?? '').toString().trim();
  final runtimeArg = (item['runtimeArg'] ?? '').toString().trim();
  final hasConverted = support.values.any((value) => value == 'converted');
  String versionLabel(Map<String, dynamic> version) {
    final key = version['key'];
    final source = '${version['source'] ?? ''}'.trim();
    return '${key == currentKey ? '★ ' : ''}${version['label'] ?? key ?? ''}${source.isEmpty ? '' : ' · $source'}: ${_capabilityMark((support[key] ?? 'unknown').toString())}';
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${item['label'] ?? ''} · ${item['arg'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: prism.AppTextStyle.subheadline.of(context, emphasized: true),
      ),
      if (note.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          note,
          style: prism.AppTextStyle.caption1
              .of(context)
              .copyWith(color: colors.onSurfaceVariant),
        ),
      ],
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in versions)
            PrismBadge(
              label: versionLabel(v),
              tone: _capabilityTone(
                (support[v['key']] ?? 'unknown').toString(),
              ),
            ),
        ],
      ),
      if (hasConverted && runtimeArg.isNotEmpty) ...[
        const SizedBox(height: 6),
        prism.SelectableText(
          '转换后的运行参数：$runtimeArg',
          style: prism.AppTextStyle.caption1
              .of(context)
              .copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    ],
  );
}

String _capabilityMark(String status) => switch (status) {
  'supported' || 'supported_measured' => '✓ 实测',
  'supported_documented' => '✓ 文档',
  'supported_policy' => '✓ 策略',
  'unsupported' || 'unsupported_measured' => '✗ 实测',
  'unsupported_documented' => '✗ 文档',
  'unsupported_policy' => '✗ 策略',
  'converted' => '转 兼容',
  _ => '? 未验',
};

PrismTone _capabilityTone(String status) => switch (status) {
  'supported' || 'supported_measured' => PrismTone.success,
  'supported_documented' => PrismTone.info,
  'unsupported' || 'unsupported_measured' => PrismTone.danger,
  'unsupported_documented' || 'converted' => PrismTone.warning,
  _ => PrismTone.neutral,
};
