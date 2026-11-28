import 'dart:convert';

import 'prism_widgets.dart';

class DualInstancePreview extends StatelessWidget {
  const DualInstancePreview({
    super.key,
    required this.params,
    required this.baseUrl,
    required this.authHeader,
    required this.scriptId,
  });

  final TextEditingController params;
  final String baseUrl;
  final String authHeader;
  final String scriptId;

  List<Map<String, dynamic>> _requests() {
    final input = jsonDecode(params.text.trim().isEmpty ? '{}' : params.text);
    if (input is! Map<String, dynamic>) {
      throw const FormatException('运行参数必须是 JSON 对象');
    }
    final browsers = input['browsers'];
    final targets = browsers is List && browsers.isNotEmpty
        ? browsers
        : [input['primaryCode'], input['secondaryCode']];
    final timeout = num.tryParse('${input['timeoutMs'] ?? ''}');
    List<String> readList(dynamic value) => value is List
        ? value
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const [];
    final requests = <Map<String, dynamic>>[];
    for (final (index, target) in targets.indexed) {
      final fields = target is Map ? target : const {};
      final directCode = target is String || target is num ? target : '';
      final code = '${fields['code'] ?? fields['launchCode'] ?? directCode}'
          .trim()
          .toUpperCase();
      final urls = readList(fields['startUrls']);
      final args = readList(fields['launchArgs']);
      requests.add({
        'selector': {
          'code': code.isEmpty
              ? (index == 0 ? 'BUYER_001' : 'BUYER_002')
              : code,
          'matchMode': 'unique',
        },
        'skipDefaultStartUrls':
            (fields['skipDefaultStartUrls'] ?? input['skipDefaultStartUrls']) !=
            false,
        if (urls.isNotEmpty) 'startUrls': urls,
        if (args.isNotEmpty) 'launchArgs': args,
        'timeoutMs': timeout != null && timeout.isFinite
            ? timeout.clamp(1000, 2147483647).round()
            : 45000,
      });
    }
    return requests;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: params,
    builder: (context, _) {
      final List<Map<String, dynamic>> requests;
      try {
        requests = _requests();
      } on FormatException catch (error) {
        return PrismBanner(
          tone: PrismTone.warning,
          message: '无法预览双实例请求：${error.message}',
        );
      }
      final codes = requests
          .map((request) => '${request['selector']['code']}')
          .toSet()
          .toList();
      final primary = codes.firstOrNull ?? 'BUYER_001';
      final secondary = codes.skip(1).firstOrNull ?? 'BUYER_002';
      final instruction = [
        '使用 ant-chrome-openclaw skill 执行预置脚本 $scriptId。',
        '为 $primary 设置 startUrls 为 ["https://finance.sina.com.cn/"]。',
        '为 $secondary 设置 startUrls 为 ["https://map.baidu.com/"]。',
        '每个实例使用独立会话，在 runtime/session 请求中传入 startUrls。',
        '返回两个实例各自的页面标题和当前 URL。',
      ].join('\n');
      return PrismSectionCard(
        title: '双实例请求预览',
        glyph: AntGlyphs.api,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, request) in requests.indexed) ...[
              Text('请求 ${index + 1} · ${request['selector']['code']}'),
              const SizedBox(height: 6),
              PrismCodeSurface(
                code: [
                  'POST $baseUrl/api/runtime/session',
                  'Content-Type: application/json',
                  if (authHeader.isNotEmpty) '$authHeader: <your-api-key>',
                  '',
                  const JsonEncoder.withIndent('  ').convert(request),
                ].join('\n'),
                language: 'http',
                maxHeight: 200,
              ),
              const SizedBox(height: 14),
            ],
            const Text('OpenClaw 双站点指令'),
            const SizedBox(height: 6),
            PrismCodeSurface(code: instruction, maxHeight: 200),
          ],
        ),
      );
    },
  );
}
