import 'dart:convert';

import 'package:prism_ui/prism_ui.dart' as prism;

import 'app_bridge.dart';
import 'prism_widgets.dart';

Future<void> showFingerprintCapabilityAndMatrix({
  required BuildContext context,
  required String profileId,
  required String coreId,
  required List<String> args,
}) async {
  try {
    final results = await Future.wait<dynamic>([
      AppBridge.call('BrowserProfileFingerprintCapabilityTable', [
        profileId,
        coreId,
      ]),
      AppBridge.call('BrowserProfileFingerprintMatrix', [
        profileId,
        coreId,
        args,
      ]),
    ]);
    if (!context.mounted) return;
    final table = results[0] is Map
        ? Map<String, dynamic>.from(results[0] as Map)
        : <String, dynamic>{};
    final matrix = results[1] is Map
        ? Map<String, dynamic>.from(results[1] as Map)
        : <String, dynamic>{};
    final matrixItems =
        ((matrix['items'] ?? matrix['rows'] ?? matrix['checks']) as List? ??
                const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    await showFingerprintCapabilityDialog(
      context: context,
      title: '内核能力表与参数适配矩阵',
      kernelBadgePrefix: '当前内核',
      table: table,
      extraSections: [
        if (matrixItems.isNotEmpty)
          PrismSectionCard(
            title: '当前配置参数检测结论',
            glyph: AntGlyphs.factCheck,
            child: Column(
              children: [
                for (var i = 0; i < matrixItems.length; i++) ...[
                  if (i > 0) const prism.Divider(height: 1),
                  Builder(
                    builder: (context) {
                      final row = matrixItems[i];
                      final status = (row['status'] ?? '').toString();
                      final label = (row['capability'] ?? '').toString();
                      final inputArg = (row['inputArg'] ?? '').toString();
                      final runtimeArg = (row['runtimeArg'] ?? '').toString();
                      final action = (row['action'] ?? '').toString();
                      final note = (row['note'] ?? '').toString();
                      final statusLabels = const {
                        'kept': '保留',
                        'injected': '补齐',
                        'inferred': '补齐',
                        'converted': '转换',
                        'removed': '清理',
                        'disabled': '关闭',
                        'overridden': '已覆盖',
                        'not_effective': '实测无效',
                        'pending': '待启动',
                        'kept_legacy': '旧版保留',
                        'kept_unconfirmed': '保守保留',
                        'kept_unknown': '原样保留',
                      };
                      final tone = switch (status) {
                        'removed' || 'not_effective' => PrismTone.danger,
                        'disabled' || 'overridden' => PrismTone.neutral,
                        'converted' ||
                        'injected' ||
                        'inferred' => PrismTone.info,
                        'kept_unconfirmed' ||
                        'kept_unknown' ||
                        'pending' => PrismTone.warning,
                        _ => PrismTone.success,
                      };
                      final details = [
                        if (action.isNotEmpty) action,
                        if (inputArg.isNotEmpty) '输入：$inputArg',
                        if (runtimeArg.isNotEmpty && runtimeArg != inputArg)
                          '运行：$runtimeArg',
                        if (note.isNotEmpty) note,
                      ].join('\n');
                      return PrismListTile(
                        dense: true,
                        title: Text(
                          label.isEmpty ? '未命名能力' : label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          details.isEmpty ? '无补充说明' : details,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PrismBadge(
                          label: status.isEmpty
                              ? '已检'
                              : statusLabels[status] ?? status,
                          tone: tone,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  } catch (error) {
    if (context.mounted) showPrismNotice(context, error.toString());
  }
}

Future<void> showFingerprintReport({
  required BuildContext context,
  required String title,
  required Future<dynamic> request,
}) async {
  try {
    final value = await request;
    if (!context.mounted) return;
    final result = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
    final expected = result['expected'] is Map
        ? Map<String, dynamic>.from(result['expected'] as Map)
        : <String, dynamic>{};
    final runtime = result['runtime'] is Map
        ? Map<String, dynamic>.from(result['runtime'] as Map)
        : <String, dynamic>{};
    final rows = <Map<String, dynamic>>[];
    String displayValue(dynamic raw) {
      if (raw == null) return '—';
      if (raw is List) return raw.map((item) => item.toString()).join(', ');
      if (raw is Map) return jsonEncode(raw);
      final text = raw.toString().trim();
      return text.isEmpty ? '—' : text;
    }

    String normalizedPlatform(String raw) {
      final value = raw.toLowerCase();
      if (value.contains('win')) return 'windows';
      if (value.contains('mac') || value.contains('darwin')) return 'macos';
      if (value.contains('linux')) return 'linux';
      return value;
    }

    void addRow(
      String label,
      dynamic configured,
      dynamic actual, {
      String mode = 'exact',
    }) {
      final configuredText = displayValue(configured);
      final actualText = displayValue(actual);
      var status = '观测值';
      var tone = PrismTone.neutral;
      if (configuredText != '—' && mode != 'display') {
        var matches = false;
        if (mode == 'contains') {
          matches = actualText.toLowerCase().contains(
            configuredText.toLowerCase(),
          );
        } else if (mode == 'platform') {
          matches =
              normalizedPlatform(configuredText) ==
              normalizedPlatform(actualText);
        } else if (mode == 'list') {
          final configuredItems = configuredText
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
          final actualItems = actual is List
              ? actual.map((item) => item.toString().trim()).toList()
              : actualText.split(',').map((item) => item.trim()).toList();
          matches =
              configuredItems.isNotEmpty &&
              configuredItems.length <= actualItems.length &&
              List.generate(
                configuredItems.length,
                (index) => index,
              ).every((index) => configuredItems[index] == actualItems[index]);
        } else if (mode == 'version') {
          matches = actualText.contains(configuredText);
        } else if (mode == 'number') {
          final configuredNumber = num.tryParse(configuredText);
          final actualNumber = num.tryParse(actualText);
          matches =
              configuredNumber != null &&
              actualNumber != null &&
              configuredNumber == actualNumber;
        } else {
          matches = configuredText == actualText;
        }
        status = matches ? '一致' : (mode == 'version' ? '需核对' : '不一致');
        tone = matches
            ? PrismTone.success
            : mode == 'version'
            ? PrismTone.warning
            : PrismTone.danger;
      }
      rows.add({
        'label': label,
        'configured': configuredText,
        'actual': actualText,
        'status': status,
        'tone': tone,
      });
    }

    if (expected.isNotEmpty && runtime.isNotEmpty) {
      addRow('语言', expected['language'], runtime['language']);
      addRow(
        '语言列表',
        expected['acceptLanguage'],
        runtime['languages'],
        mode: 'list',
      );
      addRow('时区', expected['timezone'], runtime['timezone']);
      addRow(
        'CPU 核心数',
        expected['hardwareConcurrency'],
        runtime['hardwareConcurrency'],
        mode: 'number',
      );
      addRow(
        '设备内存',
        expected['deviceMemory'],
        runtime['deviceMemory'],
        mode: 'number',
      );
      addRow(
        '触控点',
        expected['touchPoints'],
        runtime['maxTouchPoints'],
        mode: 'number',
      );
      addRow('Do Not Track', expected['doNotTrack'], runtime['doNotTrack']);
      addRow(
        '媒体设备',
        expected['mediaDevices'],
        runtime['mediaDeviceCount'],
        mode: 'number',
      );
      addRow(
        '窗口大小',
        expected['windowSize'],
        '${runtime['outerWidth']},${runtime['outerHeight']}',
      );
      addRow('平台', expected['platform'], runtime['platform'], mode: 'platform');
      addRow(
        '浏览器品牌',
        expected['brand'],
        runtime['userAgent'],
        mode: 'contains',
      );
      addRow(
        '浏览器版本',
        expected['brandVersion'],
        runtime['userAgent'],
        mode: 'version',
      );
      addRow(
        '系统版本',
        expected['platformVersion'],
        runtime['userAgent'],
        mode: 'version',
      );
      addRow(
        '色彩深度',
        expected['colorDepth'],
        runtime['colorDepth'],
        mode: 'number',
      );
      addRow('Webdriver', false, runtime['webdriver']);
      addRow(
        '屏幕尺寸',
        null,
        '${runtime['screenWidth']} × ${runtime['screenHeight']}',
      );
      addRow(
        '窗口内尺寸',
        null,
        '${runtime['innerWidth']} × ${runtime['innerHeight']}',
      );
      addRow('设备像素比', null, runtime['devicePixelRatio']);
      addRow('UA', null, runtime['userAgent']);
      addRow('UA Data', null, runtime['userAgentData']);
      addRow('WebGL Vendor', expected['webglVendor'], runtime['webglVendor']);
      addRow(
        'WebGL Renderer',
        expected['webglRenderer'],
        runtime['webglRenderer'],
      );
      addRow(
        'Canvas Hash',
        expected['canvasNoise'],
        runtime['canvasHash'],
        mode: 'display',
      );
      addRow(
        'Audio Hash',
        expected['audioNoise'],
        runtime['audioHash'],
        mode: 'display',
      );
      addRow(
        'ClientRects Hash',
        expected['clientRectsNoise'],
        runtime['clientRectsHash'],
        mode: 'display',
      );
      addRow('插件列表', null, runtime['plugins']);
      addRow('指纹种子', expected['seed'], '页面无法直接读取', mode: 'display');
      addRow(
        'WebRTC 策略',
        expected['webrtcPolicy'],
        '页面无法直接读取',
        mode: 'display',
      );
      addRow('排除伪装项', expected['disableSpoofing'], '页面无法直接读取', mode: 'display');
      addRow('字体列表', expected['fontList'], '页面无法直接读取', mode: 'display');
    } else {
      rows.addAll(
        ((result['items'] ?? result['rows'] ?? result['checks']) as List? ??
                const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)),
      );
    }
    final text = const JsonEncoder.withIndent('  ').convert(value);
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text(title),
        content: SizedBox(
          width: 680,
          height: 520,
          child: rows.isNotEmpty
              ? ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const prism.Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final status = (row['status'] ?? '').toString();
                    final tone = row['tone'] is PrismTone
                        ? row['tone'] as PrismTone
                        : status == 'match' || status == 'ok'
                        ? PrismTone.success
                        : status == 'compatible' || status == 'warn'
                        ? PrismTone.warning
                        : PrismTone.neutral;
                    return PrismListTile(
                      dense: true,
                      title: Text(
                        (row['label'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '期望：${row['configured'] ?? '—'}  →  实测：${row['actual'] ?? '—'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: PrismBadge(
                        label: status.isEmpty ? '已检' : status,
                        tone: tone,
                      ),
                    );
                  },
                )
              : PrismCodeSurface(code: text, language: 'json'),
        ),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted) {
      showPrismNotice(context, error.toString());
    }
  }
}
