import 'package:prism_ui/prism_ui.dart' as prism;

import 'fingerprint_args.dart';
import 'prism_widgets.dart';

Future<void> showFingerprintArgsDialog({
  required BuildContext context,
  required TextEditingController source,
}) async {
  final args = source.text
      .split('\n')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  String value(String prefix) {
    final match = args.where((item) => item.startsWith(prefix));
    return match.isEmpty ? '' : match.last.substring(prefix.length);
  }

  final controllers = <String, TextEditingController>{
    'seed': TextEditingController(text: value('--fingerprint=')),
    'brand': TextEditingController(text: value('--fingerprint-brand=')),
    'brandVersion': TextEditingController(
      text: value('--fingerprint-brand-version='),
    ),
    'platform': TextEditingController(text: value('--fingerprint-platform=')),
    'platformVersion': TextEditingController(
      text: value('--fingerprint-platform-version='),
    ),
    'language': TextEditingController(text: value('--lang=')),
    'acceptLanguage': TextEditingController(text: value('--accept-lang=')),
    'timezone': TextEditingController(text: value('--timezone=')),
    'windowSize': TextEditingController(text: value('--window-size=')),
    'cpu': TextEditingController(
      text: value('--fingerprint-hardware-concurrency='),
    ),
    'webrtc': TextEditingController(
      text: args.contains('--disable-non-proxied-udp')
          ? 'disable_non_proxied_udp'
          : value('--webrtc-ip-handling-policy='),
    ),
  };
  String noiseValue(String canonical, String legacy) {
    if (args.contains(canonical) || args.contains(legacy)) return '1';
    for (final item in args.reversed) {
      if (item.startsWith('$canonical='))
        return item.substring(canonical.length + 1);
      if (item.startsWith('$legacy=')) return item.substring(legacy.length + 1);
    }
    return '';
  }

  var canvasNoise = noiseValue(
    '--fingerprinting-canvas-image-data-noise',
    '--fingerprint-canvas-noise',
  );
  var rectNoise = noiseValue(
    '--fingerprinting-client-rects-noise',
    '--fingerprint-client-rects-noise',
  );
  final disableSpoofing = <String>{};
  for (final arg in args.where(
    (item) => item.startsWith('--disable-spoofing='),
  )) {
    disableSpoofing.addAll(
      arg.substring('--disable-spoofing='.length).split(','),
    );
  }
  final recognized = [
    '--fingerprint=',
    '--fingerprint-brand=',
    '--fingerprint-brand-version=',
    '--fingerprint-platform=',
    '--fingerprint-platform-version=',
    '--lang=',
    '--accept-lang=',
    '--timezone=',
    '--window-size=',
    '--fingerprint-hardware-concurrency=',
    '--webrtc-ip-handling-policy=',
    '--fingerprinting-canvas-image-data-noise',
    '--fingerprinting-client-rects-noise',
    '--fingerprint-canvas-noise=',
    '--fingerprint-client-rects-noise=',
    '--disable-spoofing=',
  ];
  final unknownArgs = args.where((arg) {
    if (arg == '--disable-non-proxied-udp') return false;
    return !recognized.any((prefix) => arg.startsWith(prefix));
  }).toList();
  var resolutionCustomMode = !const <String>{
    '',
    '1920,1080',
    '1440,900',
    '1366,768',
    '2560,1440',
    '1280,800',
    '1600,900',
  }.contains(controllers['windowSize']!.text.trim());
  final result = await showPrismDialog<List<String>>(
    context: context,
    useRootNavigator: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) {
        Widget field(String key, String label, {String? hint}) =>
            PrismTextField(
              controller: controllers[key],
              onChanged: (_) => setDialog(() {}),
              decoration: PrismInputDecoration(
                labelText: label,
                hintText: hint,
              ),
            );
        const brandOptions = <PrismDropdownItem<String>>[
          PrismDropdownItem(value: '', child: Text('不设置')),
          PrismDropdownItem(value: 'Chrome', child: Text('Chrome')),
          PrismDropdownItem(value: 'Edge', child: Text('Edge')),
          PrismDropdownItem(value: 'Opera', child: Text('Opera')),
          PrismDropdownItem(value: 'Vivaldi', child: Text('Vivaldi')),
        ];
        const platformOptions = <PrismDropdownItem<String>>[
          PrismDropdownItem(value: '', child: Text('不设置')),
          PrismDropdownItem(value: 'windows', child: Text('Windows')),
          PrismDropdownItem(value: 'macos', child: Text('macOS')),
          PrismDropdownItem(value: 'linux', child: Text('Linux')),
        ];
        const languageOptions = <PrismDropdownItem<String>>[
          PrismDropdownItem(value: '', child: Text('不设置')),
          PrismDropdownItem(value: 'zh-CN', child: Text('中文（简体） zh-CN')),
          PrismDropdownItem(value: 'zh-HK', child: Text('繁體中文（香港） zh-HK')),
          PrismDropdownItem(value: 'zh-TW', child: Text('繁體中文（台湾） zh-TW')),
          PrismDropdownItem(value: 'en-US', child: Text('English US')),
          PrismDropdownItem(value: 'en-GB', child: Text('English UK')),
          PrismDropdownItem(value: 'en-CA', child: Text('English Canada')),
          PrismDropdownItem(value: 'en-AU', child: Text('English Australia')),
          PrismDropdownItem(value: 'en-SG', child: Text('English Singapore')),
          PrismDropdownItem(value: 'en-IN', child: Text('English India')),
          PrismDropdownItem(value: 'ja-JP', child: Text('日本語')),
          PrismDropdownItem(value: 'ko-KR', child: Text('한국어')),
          PrismDropdownItem(value: 'fr-FR', child: Text('Français')),
          PrismDropdownItem(value: 'de-DE', child: Text('Deutsch')),
          PrismDropdownItem(value: 'nl-NL', child: Text('Nederlands')),
          PrismDropdownItem(value: 'ru-RU', child: Text('Русский')),
          PrismDropdownItem(value: 'pt-BR', child: Text('Português Brasil')),
        ];
        const timezoneOptions = <PrismDropdownItem<String>>[
          PrismDropdownItem(value: '', child: Text('不设置')),
          PrismDropdownItem(value: 'system', child: Text('跟随系统')),
          PrismDropdownItem(
            value: 'Asia/Shanghai',
            child: Text('Asia/Shanghai'),
          ),
          PrismDropdownItem(value: 'Asia/Tokyo', child: Text('Asia/Tokyo')),
          PrismDropdownItem(value: 'Asia/Seoul', child: Text('Asia/Seoul')),
          PrismDropdownItem(
            value: 'Asia/Singapore',
            child: Text('Asia/Singapore'),
          ),
          PrismDropdownItem(
            value: 'Asia/Hong_Kong',
            child: Text('Asia/Hong_Kong'),
          ),
          PrismDropdownItem(value: 'Asia/Taipei', child: Text('Asia/Taipei')),
          PrismDropdownItem(value: 'Asia/Dubai', child: Text('Asia/Dubai')),
          PrismDropdownItem(value: 'Asia/Kolkata', child: Text('Asia/Kolkata')),
          PrismDropdownItem(
            value: 'America/New_York',
            child: Text('America/New_York'),
          ),
          PrismDropdownItem(
            value: 'America/Los_Angeles',
            child: Text('America/Los_Angeles'),
          ),
          PrismDropdownItem(
            value: 'America/Chicago',
            child: Text('America/Chicago'),
          ),
          PrismDropdownItem(
            value: 'America/Denver',
            child: Text('America/Denver'),
          ),
          PrismDropdownItem(
            value: 'America/Toronto',
            child: Text('America/Toronto'),
          ),
          PrismDropdownItem(
            value: 'America/Vancouver',
            child: Text('America/Vancouver'),
          ),
          PrismDropdownItem(
            value: 'America/Phoenix',
            child: Text('America/Phoenix'),
          ),
          PrismDropdownItem(
            value: 'America/Sao_Paulo',
            child: Text('America/Sao_Paulo'),
          ),
          PrismDropdownItem(
            value: 'Europe/London',
            child: Text('Europe/London'),
          ),
          PrismDropdownItem(value: 'Europe/Paris', child: Text('Europe/Paris')),
          PrismDropdownItem(
            value: 'Europe/Berlin',
            child: Text('Europe/Berlin'),
          ),
          PrismDropdownItem(
            value: 'Europe/Moscow',
            child: Text('Europe/Moscow'),
          ),
          PrismDropdownItem(
            value: 'Australia/Sydney',
            child: Text('Australia/Sydney'),
          ),
          PrismDropdownItem(
            value: 'Australia/Melbourne',
            child: Text('Australia/Melbourne'),
          ),
          PrismDropdownItem(
            value: 'Australia/Perth',
            child: Text('Australia/Perth'),
          ),
          PrismDropdownItem(
            value: 'Pacific/Auckland',
            child: Text('Pacific/Auckland'),
          ),
        ];
        const resolutionOptions = <PrismDropdownItem<String>>[
          PrismDropdownItem(value: '', child: Text('不设置')),
          PrismDropdownItem(value: '1920,1080', child: Text('1920 × 1080')),
          PrismDropdownItem(value: '1440,900', child: Text('1440 × 900')),
          PrismDropdownItem(value: '1366,768', child: Text('1366 × 768')),
          PrismDropdownItem(value: '2560,1440', child: Text('2560 × 1440')),
          PrismDropdownItem(value: '1280,800', child: Text('1280 × 800')),
          PrismDropdownItem(value: '1600,900', child: Text('1600 × 900')),
        ];
        const webrtcOptions = <PrismDropdownItem<String>>[
          PrismDropdownItem(value: '', child: Text('不设置')),
          PrismDropdownItem(
            value: 'disable_non_proxied_udp',
            child: Text('禁用非代理 UDP'),
          ),
          PrismDropdownItem(
            value: 'default_public_interface_only',
            child: Text('仅公网接口'),
          ),
          PrismDropdownItem(
            value: 'default_public_and_private_interfaces',
            child: Text('公网 + 私网接口'),
          ),
        ];
        const cpuOptions = <PrismDropdownItem<String>>[
          PrismDropdownItem(value: '', child: Text('不设置')),
          PrismDropdownItem(value: '2', child: Text('2 核')),
          PrismDropdownItem(value: '4', child: Text('4 核')),
          PrismDropdownItem(value: '6', child: Text('6 核')),
          PrismDropdownItem(value: '8', child: Text('8 核')),
          PrismDropdownItem(value: '10', child: Text('10 核')),
          PrismDropdownItem(value: '12', child: Text('12 核')),
          PrismDropdownItem(value: '16', child: Text('16 核')),
        ];
        final acceptLanguageOptions = <PrismDropdownItem<String>>[
          const PrismDropdownItem(value: '', child: Text('不设置')),
          for (final item in languageOptions.skip(1))
            PrismDropdownItem(
              value: '${item.value},${item.value!.split(RegExp('[-_]')).first}',
              child: Text(
                '${item.value},${item.value!.split(RegExp('[-_]')).first}',
              ),
            ),
        ];
        Widget choiceField(
          String key,
          String label,
          List<PrismDropdownItem<String>> options,
        ) {
          final current = controllers[key]!.text.trim();
          final items = options.any((item) => item.value == current)
              ? options
              : [
                  ...options,
                  PrismDropdownItem(
                    value: current,
                    child: Text('当前值：$current'),
                  ),
                ];
          return PrismDropdownField<String>(
            initialValue: current,
            decoration: PrismInputDecoration(labelText: label),
            items: items,
            onChanged: (value) =>
                setDialog(() => controllers[key]!.text = value ?? ''),
          );
        }

        Widget languageField() {
          final current = controllers['language']!.text.trim();
          final options = languageOptions.any((item) => item.value == current)
              ? languageOptions
              : [
                  ...languageOptions,
                  PrismDropdownItem(
                    value: current,
                    child: Text('当前值：$current'),
                  ),
                ];
          return PrismDropdownField<String>(
            initialValue: current,
            decoration: const PrismInputDecoration(labelText: '语言'),
            items: options,
            onChanged: (value) => setDialog(() {
              final language = value ?? '';
              controllers['language']!.text = language;
              final base = language.split(RegExp('[-_]')).first;
              controllers['acceptLanguage']!.text = language.isEmpty
                  ? ''
                  : language == base
                  ? language
                  : '$language,$base';
            }),
          );
        }

        Widget resolutionField() {
          final current = controllers['windowSize']!.text.trim();
          final isPreset = resolutionOptions.any(
            (item) => item.value == current,
          );
          final custom = resolutionCustomMode || !isPreset;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismDropdownField<String>(
                initialValue: custom ? '__custom__' : current,
                decoration: const PrismInputDecoration(labelText: '窗口大小预设'),
                items: [
                  ...resolutionOptions,
                  const PrismDropdownItem(
                    value: '__custom__',
                    child: Text('自定义尺寸'),
                  ),
                ],
                onChanged: (value) {
                  if (value == '__custom__') {
                    setDialog(() => resolutionCustomMode = true);
                  } else {
                    setDialog(() {
                      resolutionCustomMode = false;
                      controllers['windowSize']!.text = value ?? '';
                    });
                  }
                },
              ),
              if (custom) ...[
                const SizedBox(height: 8),
                field('windowSize', '自定义窗口大小', hint: '宽,高，例如 1600,900'),
              ],
            ],
          );
        }

        List<String> validateFields() => validateFingerprintArgs([
          for (final field in fingerprintFieldFlags.entries)
            '${field.value}=${controllers[field.key]!.text}',
        ]);

        Widget toggle(String label, String key, Set<String> values) => SizedBox(
          width: 160,
          child: Row(
            children: [
              prism.Checkbox(
                value: values.contains(key),
                onChanged: (enabled) => setDialog(() {
                  if (enabled == true) {
                    values.add(key);
                  } else {
                    values.remove(key);
                  }
                }),
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
        void applyPreset({
          required String brand,
          required String platform,
          required String platformVersion,
          required String language,
          required String timezone,
          required String resolution,
          required String cpu,
        }) {
          resolutionCustomMode = false;
          controllers['seed']!.text =
              '${DateTime.now().microsecondsSinceEpoch % 2147483647 + 1}';
          controllers['brand']!.text = brand;
          controllers['brandVersion']!.clear();
          controllers['platform']!.text = platform;
          controllers['platformVersion']!.text = platformVersion;
          controllers['language']!.text = language;
          final base = language.split(RegExp('[-_]')).first;
          controllers['acceptLanguage']!.text = language == base
              ? language
              : '$language,$base';
          controllers['timezone']!.text = timezone;
          controllers['windowSize']!.text = resolution;
          controllers['cpu']!.text = cpu;
          controllers['webrtc']!.text = 'disable_non_proxied_udp';
          canvasNoise = '1';
          rectNoise = '1';
        }

        final validationErrors = validateFields();
        return PrismDialog(
          title: const Text('图形化指纹设置'),
          content: SizedBox(
            width: 540,
            height: 600,
            child: ListView(
              children: [
                if (validationErrors.isNotEmpty) ...[
                  PrismBanner(
                    tone: PrismTone.danger,
                    title: '配置需要修正',
                    message: validationErrors.take(4).join('；'),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    const Expanded(child: Text('快速预设')),
                    prism.TextButton.icon(
                      onPressed: () {
                        showPrismDialog<void>(
                          context: context,
                          useRootNavigator: false,
                          builder: (helpContext) => PrismDialog(
                            title: const Text('原始参数使用方式'),
                            content: SizedBox(
                              width: 820,
                              height: 480,
                              child: ListView(
                                children: [
                                  for (final row in const <(String, String, String)>[
                                    (
                                      '--fingerprint=<seed>',
                                      '指纹种子；留空时按实例 ID 自动生成',
                                      '--fingerprint=123456',
                                    ),
                                    (
                                      '--fingerprint-brand=<brand>',
                                      '浏览器品牌，影响 UA / UA-CH 品牌口径',
                                      '--fingerprint-brand=Chrome',
                                    ),
                                    (
                                      '--fingerprint-brand-version=<version>',
                                      '浏览器版本；检测时按主版本口径匹配',
                                      '--fingerprint-brand-version=144.0.7559.132',
                                    ),
                                    (
                                      '--fingerprint-platform=<platform>',
                                      '系统平台画像；支持 windows、macos、linux',
                                      '--fingerprint-platform=windows',
                                    ),
                                    (
                                      '--fingerprint-platform-version=<version>',
                                      '系统版本；检测时按 UA / UA-CH 可见版本匹配',
                                      '--fingerprint-platform-version=10.0.0',
                                    ),
                                    (
                                      '--lang=<locale>',
                                      '主语言；同时补默认 Accept-Language',
                                      '--lang=ja-JP',
                                    ),
                                    (
                                      '--accept-lang=<list>',
                                      '语言列表，逗号分隔',
                                      '--accept-lang=ja-JP,ja',
                                    ),
                                    (
                                      '--timezone=<iana>',
                                      '使用 IANA 时区名',
                                      '--timezone=Asia/Tokyo',
                                    ),
                                    (
                                      '--window-size=<w,h>',
                                      '启动窗口尺寸，格式为宽,高',
                                      '--window-size=1600,900',
                                    ),
                                    (
                                      '--fingerprint-hardware-concurrency=<n>',
                                      'CPU 核心数；1 到 128 的整数',
                                      '--fingerprint-hardware-concurrency=8',
                                    ),
                                    (
                                      '--disable-non-proxied-udp',
                                      '禁用非代理 UDP，降低 WebRTC 泄漏风险',
                                      '--disable-non-proxied-udp',
                                    ),
                                    (
                                      '--webrtc-ip-handling-policy=<policy>',
                                      'WebRTC IP 暴露策略',
                                      '--webrtc-ip-handling-policy=default_public_interface_only',
                                    ),
                                    (
                                      '--fingerprinting-canvas-image-data-noise',
                                      '启用 Canvas ImageData 噪声',
                                      '--fingerprinting-canvas-image-data-noise',
                                    ),
                                    (
                                      '--fingerprinting-client-rects-noise',
                                      '启用 ClientRects 噪声',
                                      '--fingerprinting-client-rects-noise',
                                    ),
                                    (
                                      '--disable-spoofing=<items>',
                                      '排除伪装项；font、audio、canvas、clientrects、gpu',
                                      '--disable-spoofing=font,audio',
                                    ),
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 235,
                                            child: prism.SelectableText(row.$1),
                                          ),
                                          Expanded(child: Text(row.$2)),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                            width: 230,
                                            child: prism.SelectableText(row.$3),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            actions: [
                              prism.TextButton(
                                onPressed: () => Navigator.pop(helpContext),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const PrismGlyph(AntGlyphs.info, size: 15),
                      label: const Text('参数帮助'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'windows',
                          platformVersion: '10.0.0',
                          language: 'en-US',
                          timezone: 'America/New_York',
                          resolution: '1920,1080',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('美国 Windows Chrome'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'macos',
                          platformVersion: '15.2.0',
                          language: 'ja-JP',
                          timezone: 'Asia/Tokyo',
                          resolution: '1440,900',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('日本 macOS Chrome'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Edge',
                          platform: 'windows',
                          platformVersion: '10.0.0',
                          language: 'en-GB',
                          timezone: 'Europe/London',
                          resolution: '1920,1080',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('英国 Windows Edge'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'windows',
                          platformVersion: '10.0.0',
                          language: 'zh-CN',
                          timezone: 'Asia/Shanghai',
                          resolution: '1920,1080',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('Windows Chrome 办公'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'windows',
                          platformVersion: '10.0.0',
                          language: 'en-US',
                          timezone: 'America/New_York',
                          resolution: '2560,1440',
                          cpu: '16',
                        ),
                      ),
                      child: const Text('Windows Chrome 游戏主机'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'macos',
                          platformVersion: '15.2.0',
                          language: 'zh-CN',
                          timezone: 'Asia/Shanghai',
                          resolution: '2560,1440',
                          cpu: '10',
                        ),
                      ),
                      child: const Text('macOS Chrome 设计师'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'windows',
                          platformVersion: '10.0.0',
                          language: 'en-SG',
                          timezone: 'Asia/Singapore',
                          resolution: '1920,1080',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('新加坡 Windows Chrome'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'linux',
                          platformVersion: '',
                          language: 'de-DE',
                          timezone: 'Europe/Berlin',
                          resolution: '1920,1080',
                          cpu: '12',
                        ),
                      ),
                      child: const Text('德国 Linux Chrome'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Edge',
                          platform: 'windows',
                          platformVersion: '',
                          language: 'zh-CN',
                          timezone: 'Asia/Shanghai',
                          resolution: '1366,768',
                          cpu: '4',
                        ),
                      ),
                      child: const Text('Windows Edge 企业'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'windows',
                          platformVersion: '',
                          language: 'en-US',
                          timezone: 'America/Los_Angeles',
                          resolution: '1920,1080',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('美国 Windows Chrome（西海岸）'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'macos',
                          platformVersion: '',
                          language: 'ja-JP',
                          timezone: 'Asia/Tokyo',
                          resolution: '1440,900',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('日本 macOS Chrome 标准'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'windows',
                          platformVersion: '',
                          language: 'en-GB',
                          timezone: 'Europe/London',
                          resolution: '1920,1080',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('英国 Windows Chrome 办公'),
                    ),
                    prism.TextButton(
                      onPressed: () => setDialog(
                        () => applyPreset(
                          brand: 'Chrome',
                          platform: 'macos',
                          platformVersion: '',
                          language: 'en-US',
                          timezone: 'America/New_York',
                          resolution: '1440,900',
                          cpu: '8',
                        ),
                      ),
                      child: const Text('美国 macOS Chrome 教育'),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: field('seed', '指纹种子', hint: '留空则按实例自动生成')),
                    const SizedBox(width: 8),
                    prism.TextButton.icon(
                      onPressed: () async {
                        final yes = await showPrismDialog<bool>(
                          context: context,
                          useRootNavigator: false,
                          builder: (c) => PrismDialog(
                            title: const Text('重新生成指纹种子？'),
                            content: const Text('修改种子会改变该实例的浏览器指纹标识。'),
                            actions: [
                              prism.TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('取消'),
                              ),
                              prism.FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('重新生成'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true) {
                          setDialog(
                            () => controllers['seed']!.text =
                                '${DateTime.now().microsecondsSinceEpoch % 2147483647 + 1}',
                          );
                        }
                      },
                      icon: const PrismGlyph(AntGlyphs.refresh, size: 16),
                      label: const Text('重新生成'),
                    ),
                  ],
                ),
                choiceField('brand', '浏览器品牌', brandOptions),
                field('brandVersion', '浏览器版本'),
                choiceField('platform', '系统平台', platformOptions),
                field('platformVersion', '系统版本'),
                languageField(),
                choiceField('acceptLanguage', '语言列表预设', acceptLanguageOptions),
                field('acceptLanguage', '语言列表', hint: 'en-US,en'),
                choiceField('timezone', '时区', timezoneOptions),
                resolutionField(),
                choiceField('cpu', 'CPU 核心数', cpuOptions),
                choiceField('webrtc', 'WebRTC 策略', webrtcOptions),
                const SizedBox(height: 8),
                const Text('噪声开关（留空使用内核默认）'),
                PrismDropdownField<String>(
                  initialValue: canvasNoise,
                  decoration: const PrismInputDecoration(
                    labelText: 'Canvas 噪声',
                  ),
                  items: const [
                    PrismDropdownItem(value: '', child: Text('默认')),
                    PrismDropdownItem(value: '1', child: Text('开启')),
                    PrismDropdownItem(value: '0', child: Text('关闭')),
                  ],
                  onChanged: (value) =>
                      setDialog(() => canvasNoise = value ?? ''),
                ),
                PrismDropdownField<String>(
                  initialValue: rectNoise,
                  decoration: const PrismInputDecoration(
                    labelText: 'ClientRects 噪声',
                  ),
                  items: const [
                    PrismDropdownItem(value: '', child: Text('默认')),
                    PrismDropdownItem(value: '1', child: Text('开启')),
                    PrismDropdownItem(value: '0', child: Text('关闭')),
                  ],
                  onChanged: (value) =>
                      setDialog(() => rectNoise = value ?? ''),
                ),
                const SizedBox(height: 12),
                const Text('排除伪装项'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    toggle('字体', 'font', disableSpoofing),
                    toggle('音频', 'audio', disableSpoofing),
                    toggle('Canvas', 'canvas', disableSpoofing),
                    toggle('ClientRects', 'clientrects', disableSpoofing),
                    toggle('GPU', 'gpu', disableSpoofing),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () async {
                if (validateFields().isNotEmpty) return;
                final next = <String>[];
                void add(String key, String flag) {
                  final text = controllers[key]!.text.trim();
                  if (text.isNotEmpty) next.add('$flag$text');
                }

                add('seed', '--fingerprint=');
                add('brand', '--fingerprint-brand=');
                add('brandVersion', '--fingerprint-brand-version=');
                add('platform', '--fingerprint-platform=');
                add('platformVersion', '--fingerprint-platform-version=');
                final language = controllers['language']!.text.trim();
                final acceptLanguage = controllers['acceptLanguage']!.text
                    .trim();
                if (language.isNotEmpty) {
                  next.add('--lang=$language');
                  final base = language.split(RegExp('[-_]')).first;
                  next.add(
                    '--accept-lang=${acceptLanguage.isNotEmpty
                        ? acceptLanguage
                        : language == base
                        ? language
                        : '$language,$base'}',
                  );
                } else if (acceptLanguage.isNotEmpty) {
                  next.add('--accept-lang=$acceptLanguage');
                }
                add('timezone', '--timezone=');
                add('windowSize', '--window-size=');
                add('cpu', '--fingerprint-hardware-concurrency=');
                final webrtc = controllers['webrtc']!.text.trim();
                if (webrtc == 'disable_non_proxied_udp') {
                  next.add('--disable-non-proxied-udp');
                } else if (webrtc.isNotEmpty) {
                  next.add('--webrtc-ip-handling-policy=$webrtc');
                }
                if (canvasNoise.isNotEmpty) {
                  next.add(
                    '--fingerprinting-canvas-image-data-noise${canvasNoise == '0' ? '=0' : ''}',
                  );
                }
                if (rectNoise.isNotEmpty) {
                  next.add(
                    '--fingerprinting-client-rects-noise${rectNoise == '0' ? '=0' : ''}',
                  );
                }
                if (disableSpoofing.isNotEmpty) {
                  next.add('--disable-spoofing=${disableSpoofing.join(',')}');
                }
                final args = [...next, ...unknownArgs];
                if (controllers['timezone']!.text.trim() != 'system') {
                  Navigator.pop(context, args);
                  return;
                }
                try {
                  final resolved = await resolveFingerprintSystemTimezone(args);
                  if (context.mounted &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.pop(context, resolved);
                  }
                } catch (error) {
                  if (context.mounted) showPrismNotice(context, '$error');
                }
              },
              child: const Text('应用'),
            ),
          ],
        );
      },
    ),
  );
  for (final controller in controllers.values) {
    controller.dispose();
  }
  if (result != null) source.text = result.join('\n');
}
