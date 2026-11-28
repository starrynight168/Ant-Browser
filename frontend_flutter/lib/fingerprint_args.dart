import 'app_bridge.dart';

const fingerprintFieldFlags = {
  'seed': '--fingerprint',
  'brand': '--fingerprint-brand',
  'platform': '--fingerprint-platform',
  'language': '--lang',
  'acceptLanguage': '--accept-lang',
  'timezone': '--timezone',
  'windowSize': '--window-size',
  'cpu': '--fingerprint-hardware-concurrency',
};

final _languageTag = RegExp(r'^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8}){0,2}$');
final _windowSize = RegExp(r'^(\d{3,5})[,xX](\d{3,5})$');
final _digits = RegExp(r'^\d+$');
final _whitespace = RegExp(r'\s');

List<String> validateFingerprintArgs(Iterable<String> args) {
  final values = <String, String>{};
  for (final arg in args) {
    final separator = arg.indexOf('=');
    if (separator > 0) {
      values[arg.substring(0, separator).trim().toLowerCase()] = arg
          .substring(separator + 1)
          .trim();
    }
  }
  String value(String key) => values[fingerprintFieldFlags[key]] ?? '';
  bool validInteger(String text, int max) {
    final number = int.tryParse(text);
    return _digits.hasMatch(text) &&
        number != null &&
        number >= 1 &&
        number <= max;
  }

  final seed = value('seed');
  final brand = value('brand');
  final platform = value('platform').toLowerCase();
  final language = value('language');
  final acceptLanguage = value('acceptLanguage')
      .split(',')
      .map((tag) => tag.trim());
  final size = value('windowSize');
  final dimensions = _windowSize.firstMatch(size);
  final cpu = value('cpu');
  return [
    if (seed.isNotEmpty && !validInteger(seed, 2147483647))
      '指纹种子须为 1 – 2147483647 的整数',
    if (brand.isNotEmpty &&
        !const {'Chrome', 'Edge', 'Opera', 'Vivaldi'}.contains(brand))
      '浏览器品牌仅支持 Chrome、Edge、Opera、Vivaldi',
    if (platform.isNotEmpty &&
        !const {'windows', 'mac', 'macos', 'linux'}.contains(platform))
      '系统平台仅支持 windows、macos、linux',
    if (language.isNotEmpty && !_languageTag.hasMatch(language))
      '语言格式不正确，例如 zh-CN、en-US、ja-JP',
    if (acceptLanguage.any(
      (tag) => tag.isNotEmpty && !_languageTag.hasMatch(tag),
    ))
      '语言列表格式不正确，例如 zh-CN,zh 或 en-US,en',
    if (size.isNotEmpty &&
        (dimensions == null ||
            int.parse(dimensions[1]!) < 200 ||
            int.parse(dimensions[2]!) < 200))
      '窗口分辨率应为宽,高且至少为 200,200（例如 1920,1080）',
    if (cpu.isNotEmpty && !validInteger(cpu, 128)) 'CPU 核心数须为 1 – 128 的整数',
    if (_whitespace.hasMatch(value('timezone')))
      '时区不能包含空白字符（如 America/New_York）',
  ];
}

Future<List<String>> resolveFingerprintSystemTimezone(List<String> args) async {
  bool isSystemTimezone(String arg) =>
      RegExp(r'^--timezone\s*=\s*system$', caseSensitive: false).hasMatch(arg);
  if (!args.any(isSystemTimezone)) return args;
  final timezone = (await AppBridge.systemTimezone()).trim();
  if (timezone.isEmpty) throw StateError('无法读取系统时区，请手动选择一个时区');
  return [
    for (final arg in args)
      isSystemTimezone(arg) ? '--timezone=$timezone' : arg,
  ];
}
