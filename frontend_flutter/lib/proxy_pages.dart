import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:yaml/yaml.dart';

import 'app_bridge.dart';
import 'prism_widgets.dart';

const List<String> _supportedKernels = [
  'auto',
  'xray',
  'sing-box',
  'mihomo',
  'mieru',
];

const Map<String, String> _kernelLabels = {
  'auto': '自动',
  'xray': 'Xray',
  'sing-box': 'sing-box',
  'mihomo': 'Mihomo',
  'mieru': 'mieru',
};

const Map<String, dynamic> _builtinDirectProxy = {
  'proxyId': '__direct__',
  'proxyName': '直连（不使用代理）',
  'proxyConfig': 'direct://',
  'groupName': '',
};

String _hostGoos() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'darwin';
  if (Platform.isLinux) return 'linux';
  return 'windows';
}

String _hostGoarch() {
  final abi = Platform.version.toLowerCase();
  if (abi.contains('arm64') || abi.contains('aarch64')) return 'arm64';
  if (abi.contains('ia32') || abi.contains('x86"') || abi.contains('_x86')) {
    return '386';
  }
  return 'amd64';
}

String _normalizeKernel(dynamic raw) {
  final value = (raw ?? '').toString().trim().toLowerCase();
  return _supportedKernels.contains(value) ? value : 'auto';
}

void _applyPreferredKernel(Map<String, dynamic> row, String kernel) {
  final normalized = _normalizeKernel(kernel);
  if (normalized == 'auto') {
    row.remove('preferredKernel');
  } else {
    row['preferredKernel'] = normalized;
  }
}

dynamic _plainYaml(dynamic value) {
  if (value is YamlMap) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _plainYaml(entry.value),
    };
  }
  if (value is YamlList) return value.map(_plainYaml).toList();
  if (value is DateTime) return value.toIso8601String();
  return value;
}

List<Map<String, dynamic>> _parseClashNodes(String content, String prefix) {
  final parsed = loadYaml(content);
  final rawNodes = parsed is YamlMap
      ? parsed['proxies'] ?? parsed['proxy'] ?? parsed['Proxy']
      : parsed;
  if (rawNodes is! YamlList) {
    throw const FormatException('订阅内容中没有 proxies 节点列表');
  }
  final nodes = <Map<String, dynamic>>[];
  for (final item in rawNodes) {
    final plain = _plainYaml(item);
    if (plain is! Map) continue;
    final node = Map<String, dynamic>.from(plain);
    final rawName = (node['name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? '导入代理 ${nodes.length + 1}' : rawName;
    node['name'] = name;
    final fullName = prefix.trim().isEmpty ? name : '${prefix.trim()}-$name';
    final config = jsonEncode([node]);
    nodes.add({
      'index': nodes.length,
      'key': '$fullName|||$config',
      'name': fullName,
      'config': config,
      'server': node['server'],
      'port': node['port'],
      'type': node['type'],
    });
  }
  if (nodes.isEmpty) throw const FormatException('订阅内容未解析到可用节点');
  return nodes;
}

Map<String, dynamic>? _decodeChainProxyConfig(String config) {
  const prefix = 'chain+socks5://';
  final trimmed = config.trim();
  if (!trimmed.toLowerCase().startsWith(prefix)) return null;
  try {
    final value = jsonDecode(
      Uri.decodeComponent(trimmed.substring(prefix.length)),
    );
    if (value is! Map || value['first'] is! Map || value['second'] is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  } catch (_) {
    return null;
  }
}

String _encodeChainProxyConfig({
  required String localPort,
  required Map<String, String> first,
  required Map<String, String> second,
}) {
  Map<String, dynamic> hop(Map<String, String> value, String label) {
    final server = value['server']!.trim();
    final port = int.tryParse(value['port']!.trim()) ?? 0;
    if (!{'http', 'socks5'}.contains(value['protocol']) ||
        server.isEmpty ||
        port < 1 ||
        port > 65535) {
      throw FormatException('$label代理协议、地址或端口无效');
    }
    final username = value['username']!.trim();
    final password = value['password']!;
    if (password.isNotEmpty && username.isEmpty) {
      throw FormatException('$label填写密码时请同时填写账号');
    }
    return {
      'protocol': value['protocol'],
      'server': server,
      'port': port,
      if (username.isNotEmpty) 'username': username,
      if (password.isNotEmpty) 'password': password,
    };
  }

  final portText = localPort.trim();
  final listenPort = portText.isEmpty ? 0 : (int.tryParse(portText) ?? -1);
  if (listenPort < 0 || listenPort > 65535) {
    throw const FormatException('本地监听端口必须在 1-65535 之间');
  }
  final payload = {
    'first': hop(first, '第一层'),
    'second': hop(second, '第二层'),
    if (listenPort > 0) 'localPort': listenPort,
  };
  return 'chain+socks5://${Uri.encodeComponent(jsonEncode(payload))}';
}

Map<String, String>? _decodeDirectProxyUrl(String config) {
  final raw = config.trim();
  if (raw.isEmpty) return null;
  final normalizedRaw = raw.replaceFirst(
    RegExp(r'^(socket|socks)://', caseSensitive: false),
    'socks5://',
  );
  final uri = Uri.tryParse(normalizedRaw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty || uri.port <= 0) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (!{'http', 'https', 'socks5'}.contains(scheme)) return null;
  var username = '';
  var password = '';
  if (uri.userInfo.isNotEmpty) {
    final sep = uri.userInfo.indexOf(':');
    if (sep >= 0) {
      username = Uri.decodeComponent(uri.userInfo.substring(0, sep));
      password = Uri.decodeComponent(uri.userInfo.substring(sep + 1));
    } else {
      username = Uri.decodeComponent(uri.userInfo);
    }
  }
  return {
    'protocol': scheme,
    'server': uri.host.replaceAll(RegExp(r'^\[|\]$'), ''),
    'port': '${uri.port}',
    'username': username,
    'password': password,
  };
}

String _encodeDirectProxyUrl({
  required String protocol,
  required String server,
  required String port,
  String username = '',
  String password = '',
}) {
  final schemeRaw = protocol.trim().toLowerCase();
  final scheme = (schemeRaw == 'socks' || schemeRaw == 'socket')
      ? 'socks5'
      : schemeRaw;
  final host = server.trim().replaceAll(RegExp(r'^\[|\]$'), '');
  final parsedPort = int.tryParse(port.trim()) ?? 0;
  if (!{'http', 'https', 'socks5'}.contains(scheme) ||
      host.isEmpty ||
      parsedPort < 1 ||
      parsedPort > 65535) {
    throw const FormatException('代理协议、地址或端口无效');
  }
  final user = username.trim();
  if (password.isNotEmpty && user.isEmpty) {
    throw const FormatException('填写密码时请同时填写账号');
  }
  return Uri(
    scheme: scheme,
    userInfo: user.isEmpty
        ? ''
        : password.isEmpty
        ? user
        : '$user:$password',
    host: host,
    port: parsedPort,
  ).toString();
}

List<Map<String, dynamic>> _parseProxyImport(
  String mode,
  String content,
  String prefix,
) {
  if (mode == 'clash') return _parseClashNodes(content, prefix);
  final raw = content.trim();
  if (raw.isEmpty) throw const FormatException('请粘贴代理配置');
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    decoded = null;
  }
  var fallbackGroup = '';
  var entries = <dynamic>[];
  if (decoded is List) {
    entries = decoded;
  } else if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    fallbackGroup = (map['group'] ?? map['groupName'] ?? '').toString();
    final source = map['proxies'] ?? map['proxy'] ?? map['items'];
    entries = source is List ? source : [map];
  } else {
    entries = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
  }
  final result = <Map<String, dynamic>>[];
  for (final entry in entries) {
    if (entry is String) {
      final value = entry.trim();
      if (mode == 'chain' ||
          value.toLowerCase().startsWith('chain+socks5://')) {
        if (!value.toLowerCase().startsWith('chain+socks5://')) {
          throw const FormatException('链式代理请填写 chain+socks5:// 配置或双层 JSON');
        }
        result.add({'name': '链式代理 ${result.length + 1}', 'config': value});
        continue;
      }
      final uri = Uri.tryParse(
        value.replaceFirst(
          RegExp(r'^(socket|socks)://', caseSensitive: false),
          'socks5://',
        ),
      );
      if (uri == null ||
          !uri.hasScheme ||
          uri.host.isEmpty ||
          uri.port < 1 ||
          uri.port > 65535) {
        throw FormatException('无效的代理地址：$value');
      }
      final scheme =
          uri.scheme.toLowerCase() == 'socks' ||
              uri.scheme.toLowerCase() == 'socket'
          ? 'socks5'
          : uri.scheme.toLowerCase();
      if (!{'http', 'https', 'socks5'}.contains(scheme)) {
        throw FormatException('不支持的代理协议：${uri.scheme}');
      }
      final normalized = Uri(
        scheme: scheme,
        userInfo: uri.userInfo,
        host: uri.host.replaceAll(RegExp(r'^\[|\]$'), ''),
        port: uri.port,
      ).toString();
      result.add({
        'name': '${scheme.toUpperCase()}-${uri.host}:${uri.port}',
        'config': normalized,
      });
      continue;
    }
    if (entry is! Map) continue;
    final item = Map<String, dynamic>.from(entry);
    final name = (item['name'] ?? item['proxyName'] ?? '').toString().trim();
    final groupName = (item['group'] ?? item['groupName'] ?? fallbackGroup)
        .toString()
        .trim();
    if (mode == 'chain' || item['first'] is Map || item['second'] is Map) {
      final first = item['first'];
      final second = item['second'];
      if (first is! Map || second is! Map) {
        throw const FormatException('链式代理需要填写 first 和 second');
      }
      Map<String, dynamic> hop(Map source, String label) {
        final protocol = (source['protocol'] ?? 'socks5')
            .toString()
            .toLowerCase();
        final server = (source['server'] ?? source['host'] ?? '')
            .toString()
            .trim();
        final port = int.tryParse((source['port'] ?? '').toString()) ?? 0;
        if (!{'http', 'socks5'}.contains(protocol) ||
            server.isEmpty ||
            port < 1 ||
            port > 65535) {
          throw FormatException('$label代理协议、地址或端口无效');
        }
        return {
          'protocol': protocol,
          'server': server,
          'port': port,
          if ((source['username'] ?? '').toString().isNotEmpty)
            'username': source['username'],
          if ((source['password'] ?? '').toString().isNotEmpty)
            'password': source['password'],
        };
      }

      final localPortRaw = (item['localPort'] ?? '').toString().trim();
      final localPort = localPortRaw.isEmpty
          ? 0
          : (int.tryParse(localPortRaw) ?? -1);
      if (localPort < 0 || localPort > 65535) {
        throw const FormatException('本地监听端口必须在 1-65535 之间');
      }
      final chain = {
        'first': hop(first, '第一层'),
        'second': hop(second, '第二层'),
        if (localPort > 0) 'localPort': localPort,
      };
      result.add({
        'name': name.isEmpty ? '链式代理 ${result.length + 1}' : name,
        'groupName': groupName,
        'config': 'chain+socks5://${Uri.encodeComponent(jsonEncode(chain))}',
      });
      continue;
    }
    final uriText =
        (item['url'] ??
                item['proxyUrl'] ??
                item['proxy'] ??
                item['proxyConfig'] ??
                '')
            .toString()
            .trim();
    if (uriText.isNotEmpty) {
      final parsed = _parseProxyImport('direct', uriText, '').single;
      result.add({
        ...parsed,
        'name': name.isEmpty ? parsed['name'] : name,
        'groupName': groupName,
      });
      continue;
    }
    final protocolRaw = (item['protocol'] ?? item['scheme'] ?? 'http')
        .toString()
        .toLowerCase();
    final protocol = protocolRaw == 'socks' || protocolRaw == 'socket'
        ? 'socks5'
        : protocolRaw;
    final host = (item['server'] ?? item['host'] ?? '').toString().trim();
    final port = int.tryParse((item['port'] ?? '').toString()) ?? 0;
    if (!{'http', 'https', 'socks5'}.contains(protocol) ||
        host.isEmpty ||
        port < 1 ||
        port > 65535) {
      throw const FormatException('代理 JSON 需要有效 protocol、server 和 port');
    }
    final username = (item['username'] ?? item['user'] ?? '').toString();
    final password = (item['password'] ?? '').toString();
    final config = Uri(
      scheme: protocol,
      userInfo: username.isEmpty
          ? ''
          : password.isEmpty
          ? username
          : '$username:$password',
      host: host.replaceAll(RegExp(r'^\[|\]$'), ''),
      port: port,
    ).toString();
    result.add({
      'name': name.isEmpty ? '${protocol.toUpperCase()}-$host:$port' : name,
      'groupName': groupName,
      'config': config,
    });
  }
  if (result.isEmpty) throw const FormatException('没有解析到可导入的代理');
  if (mode == 'chain' &&
      result.any(
        (item) => !(item['config'] as String).startsWith('chain+socks5://'),
      )) {
    throw const FormatException('链式模式只接受双层代理 JSON');
  }
  return result
      .map(
        (item) => {
          ...item,
          'name': prefix.trim().isEmpty
              ? item['name']
              : '${prefix.trim()}-${item['name']}',
          'groupName': item['groupName'] ?? fallbackGroup,
        },
      )
      .toList();
}

String _stableSourceId(String url, String prefix) {
  final parsed = Uri.parse(url.trim());
  final normalizedUrl = parsed.replace(fragment: '').toString();
  final key = '$normalizedUrl|||${prefix.trim()}';
  var hash = 5381;
  for (final unit in key.codeUnits) {
    hash = (((hash << 5) + hash) ^ unit) & 0xffffffff;
  }
  return 'src-${hash.toRadixString(36)}';
}

Map<String, dynamic> _decodeVmessUri(String config) {
  try {
    var payload = config.substring('vmess://'.length).trim();
    final hashIdx = payload.indexOf('#');
    if (hashIdx >= 0) payload = payload.substring(0, hashIdx);
    final padded = base64.normalize(payload);
    final decoded = jsonDecode(utf8.decode(base64Decode(padded)));
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      return {
        'type': 'vmess',
        'server': map['add'] ?? map['server'] ?? '',
        'port': map['port'] ?? 0,
      };
    }
  } catch (_) {}
  return const {'type': 'vmess'};
}

Map<String, dynamic> _decodeSsUri(String config) {
  final uri = Uri.tryParse(config);
  if (uri != null && uri.host.isNotEmpty && uri.port > 0) {
    return {'type': 'ss', 'server': uri.host, 'port': uri.port};
  }
  try {
    var payload = config.substring('ss://'.length).trim();
    final hashIdx = payload.indexOf('#');
    if (hashIdx >= 0) payload = payload.substring(0, hashIdx);
    final queryIdx = payload.indexOf('?');
    if (queryIdx >= 0) payload = payload.substring(0, queryIdx);
    final decoded = utf8.decode(base64Decode(base64.normalize(payload)));
    final atIdx = decoded.lastIndexOf('@');
    if (atIdx >= 0) {
      final hostPort = decoded.substring(atIdx + 1);
      final parsed = Uri.tryParse('ss://$hostPort');
      if (parsed != null && parsed.host.isNotEmpty) {
        return {'type': 'ss', 'server': parsed.host, 'port': parsed.port};
      }
    }
  } catch (_) {}
  return const {'type': 'ss'};
}

/// Parses proxyConfig across chain+socks5://, JSON, Clash YAML, and URL schemes.
Map<String, dynamic> _proxyNode(Map<String, dynamic> proxy) {
  final config = (proxy['proxyConfig'] ?? '').toString().trim();
  if (config.isEmpty || config == 'direct://') return {};

  final chain = _decodeChainProxyConfig(config);
  if (chain != null) return chain;

  final lower = config.toLowerCase();
  if (lower.startsWith('vmess://')) return _decodeVmessUri(config);
  if (lower.startsWith('ss://')) return _decodeSsUri(config);

  const urlSchemes = [
    'http://',
    'https://',
    'socks5://',
    'socks://',
    'socket://',
    'vless://',
    'trojan://',
    'hysteria2://',
    'hy2://',
    'tuic://',
    'anytls://',
  ];
  for (final schemePrefix in urlSchemes) {
    if (lower.startsWith(schemePrefix)) {
      final uri = Uri.tryParse(config);
      if (uri != null) {
        var scheme = uri.scheme.toLowerCase();
        if (scheme == 'socks' || scheme == 'socket') scheme = 'socks5';
        if (scheme == 'hy2') scheme = 'hysteria2';
        return {
          'type': scheme,
          'server': uri.host.replaceAll(RegExp(r'^\[|\]$'), ''),
          'port': uri.port,
        };
      }
    }
  }

  try {
    final decoded = jsonDecode(config);
    final node = decoded is List && decoded.isNotEmpty
        ? decoded.first
        : decoded;
    if (node is Map) {
      final map = Map<String, dynamic>.from(node);
      final nested = map['proxies'] ?? map['proxy'] ?? map['Proxy'];
      if (nested is List && nested.isNotEmpty && nested.first is Map) {
        return Map<String, dynamic>.from(nested.first as Map);
      }
      return map;
    }
  } catch (_) {}

  try {
    final parsed = _plainYaml(loadYaml(config));
    dynamic node = parsed;
    if (node is Map) {
      final nested = node['proxies'] ?? node['proxy'] ?? node['Proxy'];
      if (nested is List && nested.isNotEmpty) {
        node = nested.first;
      }
    } else if (node is List && node.isNotEmpty) {
      node = node.first;
    }
    if (node is Map) return Map<String, dynamic>.from(node);
  } catch (_) {}

  return {};
}

String _proxyProtocol(Map<String, dynamic> proxy) {
  final config = (proxy['proxyConfig'] ?? '').toString().trim();
  if (config == 'direct://') return 'direct';
  if (config.toLowerCase().startsWith('chain+socks5://')) return 'chain';
  final node = _proxyNode(proxy);
  if (node.isNotEmpty) {
    if (node['first'] is Map && node['second'] is Map) return 'chain';
    final protocol = (node['type'] ?? node['protocol'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (protocol.isNotEmpty) {
      if (protocol == 'socks' || protocol == 'socket') return 'socks5';
      if (protocol == 'hy2') return 'hysteria2';
      return protocol;
    }
  }
  final separator = config.indexOf('://');
  if (separator > 0) {
    final scheme = config.substring(0, separator).toLowerCase();
    if (scheme == 'socks' || scheme == 'socket') return 'socks5';
    if (scheme == 'hy2') return 'hysteria2';
    return scheme;
  }
  return '-';
}

String _proxyServer(Map<String, dynamic> proxy) {
  final node = _proxyNode(proxy);
  final directServer = (node['server'] ?? node['host'] ?? '').toString().trim();
  if (directServer.isNotEmpty) return directServer;
  for (final key in ['second', 'first']) {
    final part = node[key];
    if (part is Map) {
      final hopServer = (part['server'] ?? part['host'] ?? '')
          .toString()
          .trim();
      if (hopServer.isNotEmpty) return hopServer;
    }
  }
  return Uri.tryParse((proxy['proxyConfig'] ?? '').toString())?.host ?? '';
}

int _proxyPort(Map<String, dynamic> proxy) {
  final node = _proxyNode(proxy);
  final second = node['second'];
  final first = node['first'];
  final raw =
      node['port'] ??
      (second is Map ? second['port'] : null) ??
      (first is Map ? first['port'] : null);
  return int.tryParse(raw?.toString() ?? '') ??
      Uri.tryParse((proxy['proxyConfig'] ?? '').toString())?.port ??
      0;
}

String _proxyEndpointSummary(Map<String, dynamic> proxy) {
  final proto = _proxyProtocol(proxy);
  if (proto == 'direct') return '直连';
  final server = _proxyServer(proxy);
  final port = _proxyPort(proxy);
  if (server.isEmpty) return proto.toUpperCase();
  return port > 0 ? '$server:$port' : server;
}

String _subscriptionHost(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.host.isNotEmpty) return uri.host;
  return trimmed;
}

String _formatShortTime(String iso) {
  final raw = iso.trim();
  if (raw.isEmpty) return '从未';
  final dt = DateTime.tryParse(raw)?.toLocal();
  if (dt == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

String _formatNextRefreshCountdown(String lastIso, int intervalM) {
  if (intervalM <= 0) return '未开启';
  final last = DateTime.tryParse(lastIso.trim());
  if (last == null) return '等待首次刷新';
  final nextAt = last.toUtc().add(Duration(minutes: intervalM));
  final diff = nextAt.difference(DateTime.now().toUtc());
  if (diff.inSeconds <= 0) return '即将刷新';
  if (diff.inMinutes < 60) return '约 ${diff.inMinutes.clamp(1, 59)} 分钟后';
  final hours = diff.inHours;
  final mins = diff.inMinutes % 60;
  return mins == 0 ? '约 $hours 小时后' : '约 $hours 小时 $mins 分钟后';
}

String _formatIpHealthSummary(Map<String, dynamic>? health) {
  if (health == null) return '';
  if (health['ok'] != true) return '检测失败';
  final parts = <String>[];
  final fraud = health['fraudScore'] ?? health['fraud_score'] ?? health['risk'];
  if (fraud != null && fraud.toString().trim().isNotEmpty) {
    parts.add('风险 $fraud');
  }
  final isResidential = health['isResidential'] ?? health['residential'];
  final ipType = (health['ipType'] ?? health['usageType'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  if (isResidential == true || ipType.contains('res')) {
    parts.add('住宅');
  } else if (isResidential == false ||
      ipType.contains('dc') ||
      ipType.contains('data') ||
      ipType.contains('hosting')) {
    parts.add('机房');
  }
  final country = (health['country'] ?? health['countryCode'] ?? '')
      .toString()
      .trim();
  final city = (health['city'] ?? health['region'] ?? '').toString().trim();
  final location = [
    if (country.isNotEmpty) country,
    if (city.isNotEmpty && city != country) city,
  ].join('/');
  if (location.isNotEmpty) parts.add(location);
  return parts.join(' | ');
}

(String, PrismTone) _localizedMemberState(String rawState) {
  return switch (rawState.trim().toLowerCase()) {
    'healthy' => ('健康', PrismTone.success),
    'suspect' => ('可疑', PrismTone.warning),
    'degraded' => ('已降级', PrismTone.danger),
    'recovering' => ('恢复中', PrismTone.info),
    _ => ('未观测', PrismTone.neutral),
  };
}

bool _isMieruProxy(Map<String, dynamic> proxy) {
  if (_proxyProtocol(proxy) == 'mieru') return true;
  if ((proxy['preferredKernel'] ?? '').toString().trim().toLowerCase() ==
      'mieru') {
    return true;
  }
  return false;
}

String _virtualGroupFilterKey(Map<String, dynamic> group) {
  final id = (group['groupId'] ?? '').toString().trim();
  final name = (group['groupName'] ?? '').toString().trim().toLowerCase();
  return 'virtual:${id.isNotEmpty ? id : name}';
}

class ProxyPoolPage extends StatefulWidget {
  const ProxyPoolPage({
    super.key,
    required this.onOpenGroups,
    required this.onOpenAlign,
  });
  final VoidCallback onOpenGroups;
  final VoidCallback onOpenAlign;

  @override
  State<ProxyPoolPage> createState() => _ProxyPoolPageState();
}

class _ProxyPoolPageState extends State<ProxyPoolPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _virtualGroups = [];
  List<Map<String, dynamic>> _virtualGroupHealth = [];
  List<String> _backendGroups = [];
  final Map<String, Map<String, dynamic>> _coreStatuses = {};
  bool _dismissedMieruBanner = false;
  bool _loading = true;
  bool _refreshing = false;
  String _busy = '';
  String _globalCustomDns = '';
  String _query = '';
  String _filterProtocol = 'all';
  String _filterGroup = 'all';
  String _sortBy = '';
  bool _sortDescending = false;
  bool _availableOnly = false;
  bool _filtersCollapsed = true;
  final Set<String> _selectedIds = {};
  final Set<String> _testingIds = {};
  final Map<String, Map<String, dynamic>> _speedResults = {};
  final Map<String, Map<String, dynamic>> _ipHealthResults = {};
  String? _error;
  final List<void Function()> _eventUnsubscribers = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _listenProxyEvents();
  }

  void _listenProxyEvents() {
    _eventUnsubscribers.add(
      AppBridge.onEvent('proxy:sources:refreshed', (_) {
        if (!mounted) return;
        _refresh();
      }),
    );
    _eventUnsubscribers.add(
      AppBridge.onEvent('proxy:sources:refresh:failed', (payload) {
        if (!mounted) return;
        final message = payload is Map
            ? '${payload['message'] ?? payload['error'] ?? ''}'.trim()
            : '';
        showPrismNotice(
          context,
          message.isEmpty ? '订阅来源自动刷新失败' : '订阅来源刷新失败：$message',
          level: prism.BannerLevel.error,
        );
      }),
    );
    _eventUnsubscribers.add(
      AppBridge.onEvent('proxy:speed:result', (payload) {
        if (!mounted || payload is! Map) return;
        final row = Map<String, dynamic>.from(payload);
        final id = (row['proxyId'] ?? '').toString().trim();
        if (id.isEmpty) return;
        setState(() {
          _testingIds.remove(id);
          _speedResults[id] = row;
        });
      }),
    );
    _eventUnsubscribers.add(
      AppBridge.onEvent('proxy:iphealth:result', (payload) {
        if (!mounted || payload is! Map) return;
        final row = Map<String, dynamic>.from(payload);
        final id = (row['proxyId'] ?? '').toString().trim();
        if (id.isEmpty) return;
        setState(() {
          _ipHealthResults[id] = row;
        });
      }),
    );
    _eventUnsubscribers.add(
      AppBridge.onEvent('proxy:bridge:failed', (payload) {
        if (!mounted || payload is! Map) return;
        final id = (payload['proxyId'] ?? '').toString().trim();
        if (id.isEmpty) return;
        setState(() {
          _testingIds.remove(id);
          _speedResults[id] = {
            'proxyId': id,
            'ok': false,
            'latencyMs': -1,
            'engine': (payload['engine'] ?? '').toString(),
            'error': (payload['error'] ?? '桥接启动失败').toString(),
          };
        });
      }),
    );
    _eventUnsubscribers.add(
      AppBridge.onEvent('proxy:bridge:died', (payload) {
        if (!mounted || payload is! Map) return;
        final ids = (payload['proxyIds'] as List? ?? [])
            .map((item) => item.toString().trim())
            .where((id) => id.isNotEmpty)
            .toList();
        if (ids.isEmpty) return;
        setState(() {
          for (final id in ids) {
            _testingIds.remove(id);
            _speedResults[id] = {
              'proxyId': id,
              'ok': false,
              'latencyMs': -1,
              'engine': (payload['engine'] ?? '').toString(),
              'error': (payload['error'] ?? '桥接进程异常退出').toString(),
            };
          }
        });
      }),
    );
  }

  @override
  void dispose() {
    for (final remove in _eventUnsubscribers) {
      remove();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshCoreStatuses() async {
    final goos = _hostGoos();
    final goarch = _hostGoarch();
    final cores = const ['xray', 'sing-box', 'mihomo', 'mieru'];
    final results = await Future.wait(
      cores.map((core) async {
        try {
          final res = await AppBridge.call('BrowserProxyCoreStatus', [
            {'core': core, 'goos': goos, 'goarch': goarch},
          ]);
          if (res is Map) {
            return MapEntry(core, Map<String, dynamic>.from(res));
          }
        } catch (_) {}
        return MapEntry(core, <String, dynamic>{
          'core': core,
          'installed': false,
        });
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final entry in results) {
        _coreStatuses[entry.key] = entry.value;
      }
    });
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    setState(() => _loading = true);
    try {
      final values = await Future.wait<dynamic>([
        AppBridge.call('BrowserProxyList'),
        AppBridge.call('BrowserProxyVirtualGroupList'),
        AppBridge.call('BrowserProxyListGroups').catchError((_) => const []),
        AppBridge.call('BrowserProxyVirtualGroupHealthList')
            .catchError((_) => const []),
        AppBridge.call('GetBrowserSettings').catchError((_) => const {}),
      ]);
      final settingsMap = values[4] is Map
          ? Map<String, dynamic>.from(values[4] as Map)
          : const <String, dynamic>{};
      _globalCustomDns = (settingsMap['bridgeCustomDns'] ?? '').toString().trim();
      final fetchedProxies = (values[0] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final hasDirect = fetchedProxies.any(
        (p) =>
            (p['proxyId'] ?? '').toString() == '__direct__' ||
            (p['proxyConfig'] ?? '').toString().trim() == 'direct://',
      );
      _proxies = hasDirect
          ? fetchedProxies
          : [Map<String, dynamic>.from(_builtinDirectProxy), ...fetchedProxies];
      _virtualGroups = (values[1] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _backendGroups = (values[2] as List? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      _virtualGroupHealth = (values[3] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final knownGroups = {
        ..._backendGroups,
        ..._proxies.map((proxy) => (proxy['groupName'] ?? '').toString()),
      };
      if (_filterGroup != 'all' &&
          !_virtualGroups.any(
            (group) => _virtualGroupFilterKey(group) == _filterGroup,
          ) &&
          !knownGroups.contains(_filterGroup)) {
        _filterGroup = 'all';
      }
      final knownProtocols = _proxies.map(_proxyProtocol).toSet();
      if (_filterProtocol != 'all' &&
          !knownProtocols.contains(_filterProtocol)) {
        _filterProtocol = 'all';
      }
      for (final proxy in _proxies) {
        final id = (proxy['proxyId'] ?? '').toString();
        final testedAt = (proxy['lastTestedAt'] ?? '').toString();
        if (id.isNotEmpty && testedAt.isNotEmpty) {
          _speedResults[id] = {
            'proxyId': id,
            'ok': proxy['lastTestOk'] == true,
            'latencyMs': proxy['lastLatencyMs'] ?? 0,
            'engine': proxy['lastTestEngine'] ?? '',
            'error': proxy['lastTestError'] ?? '',
            'testedAt': testedAt,
          };
        }
        final rawHealth = (proxy['lastIPHealthJson'] ?? '').toString();
        if (id.isNotEmpty && rawHealth.isNotEmpty) {
          try {
            final health = jsonDecode(rawHealth);
            if (health is Map) {
              _ipHealthResults[id] = Map<String, dynamic>.from(health);
            }
          } catch (_) {}
        }
      }
      _selectedIds.removeWhere(
        (id) => !_proxies.any((proxy) => proxy['proxyId'] == id),
      );
      _error = null;
      unawaited(_refreshCoreStatuses());
    } catch (error) {
      _error = error.toString();
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(List<Map<String, dynamic>> next) async {
    final toSave = next
        .where(
          (item) =>
              (item['proxyId'] ?? '').toString() != '__direct__' &&
              (item['proxyConfig'] ?? '').toString().trim() != 'direct://',
        )
        .toList();
    await AppBridge.call('SaveBrowserProxies', [toSave]);
    await _refresh();
  }

  List<String> get _allGroupSuggestions {
    final set = <String>{
      ..._backendGroups,
      ..._proxies
          .map((proxy) => (proxy['groupName'] ?? '').toString().trim())
          .where((g) => g.isNotEmpty),
    };
    final list = set.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> get _usableFetchProxies {
    final candidates = _proxies.where((proxy) {
      final id = (proxy['proxyId'] ?? '').toString().trim();
      if (id.isEmpty ||
          id == '__direct__' ||
          proxy['proxyConfig'] == 'direct://') {
        return false;
      }
      return _speedResults[id]?['ok'] == true;
    }).toList();
    candidates.sort((a, b) {
      final latA =
          int.tryParse(
            '${_speedResults[(a['proxyId'] ?? '').toString()]?['latencyMs'] ?? 999999}',
          ) ??
          999999;
      final latB =
          int.tryParse(
            '${_speedResults[(b['proxyId'] ?? '').toString()]?['latencyMs'] ?? 999999}',
          ) ??
          999999;
      return latA.compareTo(latB);
    });
    return candidates;
  }

  Future<void> _edit([Map<String, dynamic>? proxy]) async {
    final name = TextEditingController(
      text: (proxy?['proxyName'] ?? '').toString(),
    );
    final config = TextEditingController(
      text: (proxy?['proxyConfig'] ?? '').toString(),
    );
    final group = TextEditingController(
      text: (proxy?['groupName'] ?? '').toString(),
    );
    final dns = TextEditingController(
      text: (proxy?['dnsServers'] ?? '').toString(),
    );
    final chainConfig = _decodeChainProxyConfig(config.text);
    final directParsed = chainConfig == null
        ? _decodeDirectProxyUrl(config.text)
        : null;
    var directEditMode = chainConfig == null && directParsed != null;
    var directProtocol = directParsed?['protocol'] ?? 'http';
    final directServer = TextEditingController(
      text: directParsed?['server'] ?? '',
    );
    final directPort = TextEditingController(text: directParsed?['port'] ?? '');
    final directUsername = TextEditingController(
      text: directParsed?['username'] ?? '',
    );
    final directPassword = TextEditingController(
      text: directParsed?['password'] ?? '',
    );

    Map<String, dynamic> chainHop(String key) => chainConfig?[key] is Map
        ? Map<String, dynamic>.from(chainConfig![key] as Map)
        : <String, dynamic>{};
    final firstHop = chainHop('first');
    final secondHop = chainHop('second');
    final localPort = TextEditingController(
      text: (chainConfig?['localPort'] ?? '').toString(),
    );
    final firstServer = TextEditingController(
      text: (firstHop['server'] ?? '').toString(),
    );
    final firstPort = TextEditingController(
      text: (firstHop['port'] ?? '').toString(),
    );
    final firstUsername = TextEditingController(
      text: (firstHop['username'] ?? '').toString(),
    );
    final firstPassword = TextEditingController(
      text: (firstHop['password'] ?? '').toString(),
    );
    final secondServer = TextEditingController(
      text: (secondHop['server'] ?? '').toString(),
    );
    final secondPort = TextEditingController(
      text: (secondHop['port'] ?? '').toString(),
    );
    final secondUsername = TextEditingController(
      text: (secondHop['username'] ?? '').toString(),
    );
    final secondPassword = TextEditingController(
      text: (secondHop['password'] ?? '').toString(),
    );
    var firstProtocol = (firstHop['protocol'] ?? 'http').toString();
    var secondProtocol = (secondHop['protocol'] ?? 'http').toString();
    var preferredKernel = _normalizeKernel(proxy?['preferredKernel']);
    final groupSuggestions = _allGroupSuggestions;

    final result = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: Text(proxy == null ? '添加代理' : '编辑代理'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrismTextField(
                    controller: name,
                    autofocus: true,
                    decoration: const PrismInputDecoration(labelText: '代理名称'),
                  ),
                  const SizedBox(height: 14),
                  if (chainConfig == null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            directEditMode
                                ? '结构化直连表单（HTTP / HTTPS / SOCKS5）'
                                : '原始代理配置（URL / JSON / YAML）',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: prism.AppTextStyle.footnote
                                .of(context, emphasized: true)
                                .copyWith(
                                  color: prism.Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        prism.TextButton(
                          onPressed: () {
                            setDialog(() {
                              if (directEditMode) {
                                try {
                                  if (directServer.text.trim().isNotEmpty &&
                                      directPort.text.trim().isNotEmpty) {
                                    config.text = _encodeDirectProxyUrl(
                                      protocol: directProtocol,
                                      server: directServer.text,
                                      port: directPort.text,
                                      username: directUsername.text,
                                      password: directPassword.text,
                                    );
                                  }
                                } catch (_) {}
                                directEditMode = false;
                              } else {
                                final parsed = _decodeDirectProxyUrl(
                                  config.text,
                                );
                                if (parsed != null) {
                                  directProtocol = parsed['protocol']!;
                                  directServer.text = parsed['server']!;
                                  directPort.text = parsed['port']!;
                                  directUsername.text = parsed['username']!;
                                  directPassword.text = parsed['password']!;
                                }
                                directEditMode = true;
                              }
                            });
                          },
                          child: Text(directEditMode ? '切换原始文本' : '切换结构化表单'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (directEditMode) ...[
                      PrismDropdownField<String>(
                        value: directProtocol,
                        decoration: const PrismInputDecoration(labelText: '协议'),
                        items: const [
                          PrismDropdownItem(value: 'http', child: Text('HTTP')),
                          PrismDropdownItem(
                            value: 'https',
                            child: Text('HTTPS'),
                          ),
                          PrismDropdownItem(
                            value: 'socks5',
                            child: Text('SOCKS5'),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialog(() => directProtocol = value ?? 'http'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: PrismTextField(
                              controller: directServer,
                              decoration: const PrismInputDecoration(
                                labelText: '服务器地址',
                                hintText: '127.0.0.1',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: PrismTextField(
                              controller: directPort,
                              keyboardType: TextInputType.number,
                              decoration: const PrismInputDecoration(
                                labelText: '端口',
                                hintText: '8080',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: directUsername,
                              decoration: const PrismInputDecoration(
                                labelText: '账号（可选）',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PrismTextField(
                              controller: directPassword,
                              obscureText: true,
                              decoration: const PrismInputDecoration(
                                labelText: '密码（可选）',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else
                      PrismTextField(
                        controller: config,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const PrismInputDecoration(
                          labelText: '代理配置',
                          hintText:
                              'http://127.0.0.1:8080 或 Clash YAML / JSON 节点',
                        ),
                      ),
                  ] else ...[
                    PrismTextField(
                      controller: localPort,
                      keyboardType: TextInputType.number,
                      decoration: const PrismInputDecoration(
                        labelText: '本地监听端口（可选）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '第一层代理',
                      style: prism.AppTextStyle.footnote.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PrismDropdownField<String>(
                      value: firstProtocol,
                      decoration: const PrismInputDecoration(
                        labelText: '第一层协议',
                      ),
                      items: const [
                        PrismDropdownItem(value: 'http', child: Text('HTTP')),
                        PrismDropdownItem(
                          value: 'socks5',
                          child: Text('SOCKS5'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialog(() => firstProtocol = value ?? 'http'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: PrismTextField(
                            controller: firstServer,
                            decoration: const PrismInputDecoration(
                              labelText: '第一层地址',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: PrismTextField(
                            controller: firstPort,
                            keyboardType: TextInputType.number,
                            decoration: const PrismInputDecoration(
                              labelText: '端口',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: PrismTextField(
                            controller: firstUsername,
                            decoration: const PrismInputDecoration(
                              labelText: '第一层账号',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrismTextField(
                            controller: firstPassword,
                            obscureText: true,
                            decoration: const PrismInputDecoration(
                              labelText: '第一层密码',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '第二层代理',
                      style: prism.AppTextStyle.footnote.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PrismDropdownField<String>(
                      value: secondProtocol,
                      decoration: const PrismInputDecoration(
                        labelText: '第二层协议',
                      ),
                      items: const [
                        PrismDropdownItem(value: 'http', child: Text('HTTP')),
                        PrismDropdownItem(
                          value: 'socks5',
                          child: Text('SOCKS5'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialog(() => secondProtocol = value ?? 'http'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: PrismTextField(
                            controller: secondServer,
                            decoration: const PrismInputDecoration(
                              labelText: '第二层地址',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: PrismTextField(
                            controller: secondPort,
                            keyboardType: TextInputType.number,
                            decoration: const PrismInputDecoration(
                              labelText: '端口',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: PrismTextField(
                            controller: secondUsername,
                            decoration: const PrismInputDecoration(
                              labelText: '第二层账号',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrismTextField(
                            controller: secondPassword,
                            obscureText: true,
                            decoration: const PrismInputDecoration(
                              labelText: '第二层密码',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  PrismTextField(
                    controller: group,
                    decoration: const PrismInputDecoration(labelText: '分组（可选）'),
                  ),
                  if (groupSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final suggestion in groupSuggestions.take(12))
                          PrismChip(
                            label: Text(suggestion),
                            selected: group.text.trim() == suggestion,
                            onPressed: () =>
                                setDialog(() => group.text = suggestion),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  PrismDropdownField<String>(
                    value: preferredKernel,
                    decoration: const PrismInputDecoration(labelText: '代理内核'),
                    items: [
                      for (final k in _supportedKernels)
                        PrismDropdownItem(
                          value: k,
                          child: Text(_kernelLabels[k] ?? k),
                        ),
                    ],
                    onChanged: (value) => setDialog(
                      () => preferredKernel = _normalizeKernel(value),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PrismTextField(
                    controller: dns,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const PrismInputDecoration(
                      labelText: 'DNS 服务器（可选）',
                      hintText: 'dns:\n  enable: true\n  nameserver:\n    - 119.29.29.29',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == true && name.text.trim().isNotEmpty) {
      String proxyConfig;
      try {
        if (chainConfig != null) {
          proxyConfig = _encodeChainProxyConfig(
            localPort: localPort.text,
            first: {
              'protocol': firstProtocol,
              'server': firstServer.text,
              'port': firstPort.text,
              'username': firstUsername.text,
              'password': firstPassword.text,
            },
            second: {
              'protocol': secondProtocol,
              'server': secondServer.text,
              'port': secondPort.text,
              'username': secondUsername.text,
              'password': secondPassword.text,
            },
          );
        } else if (directEditMode) {
          proxyConfig = _encodeDirectProxyUrl(
            protocol: directProtocol,
            server: directServer.text,
            port: directPort.text,
            username: directUsername.text,
            password: directPassword.text,
          );
        } else {
          proxyConfig = config.text.trim();
        }
        if (proxyConfig.isEmpty) throw const FormatException('请填写代理地址');
      } catch (error) {
        if (mounted) showPrismNotice(context, error.toString());
        _disposeEditControllers([
          name,
          config,
          group,
          dns,
          directServer,
          directPort,
          directUsername,
          directPassword,
          localPort,
          firstServer,
          firstPort,
          firstUsername,
          firstPassword,
          secondServer,
          secondPort,
          secondUsername,
          secondPassword,
        ]);
        return;
      }
      final id =
          (proxy?['proxyId'] ??
                  'proxy-${DateTime.now().millisecondsSinceEpoch}')
              .toString();
      final row = <String, dynamic>{
        ...?proxy,
        'proxyId': id,
        'proxyName': name.text.trim(),
        'proxyConfig': proxyConfig,
        'groupName': group.text.trim(),
        'dnsServers': dns.text.trim(),
      };
      _applyPreferredKernel(row, preferredKernel);
      await _save(
        proxy == null
            ? [..._proxies, row]
            : _proxies
                  .map((item) => item['proxyId'] == id ? row : item)
                  .toList(),
      );
    }
    _disposeEditControllers([
      name,
      config,
      group,
      dns,
      directServer,
      directPort,
      directUsername,
      directPassword,
      localPort,
      firstServer,
      firstPort,
      firstUsername,
      firstPassword,
      secondServer,
      secondPort,
      secondUsername,
      secondPassword,
    ]);
  }

  void _disposeEditControllers(List<TextEditingController> list) {
    for (final c in list) {
      c.dispose();
    }
  }

  static String _importTemplateForMode(String mode) {
    return switch (mode) {
      'clash' =>
        '''proxies:
  - name: hk-vless
    type: vless
    server: example.com
    port: 443
    uuid: your-uuid
    network: ws
    tls: true
    servername: example.com''',
      'direct' =>
        '''http://user:password@gateway.example.com:8080
socks5://user:password@proxy.example.com:1080''',
      'chain' =>
        '''{
  "name": "链式落地节点",
  "first": {
    "protocol": "socks5",
    "server": "127.0.0.1",
    "port": 7890
  },
  "second": {
    "protocol": "socks5",
    "server": "gateway.example.com",
    "port": 6616,
    "username": "user",
    "password": "password"
  }
}''',
      _ => '',
    };
  }

  Future<void> _importProxies() async {
    final content = TextEditingController();
    final prefix = TextEditingController();
    final group = TextEditingController();
    final dns = TextEditingController();
    final proxyName = TextEditingController();
    final server = TextEditingController();
    final port = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final localPort = TextEditingController();
    final firstServer = TextEditingController();
    final firstPort = TextEditingController();
    final firstUsername = TextEditingController();
    final firstPassword = TextEditingController();
    final secondServer = TextEditingController();
    final secondPort = TextEditingController();
    final secondUsername = TextEditingController();
    final secondPassword = TextEditingController();
    var mode = 'clash';
    var kernel = 'auto';
    var protocol = 'http';
    var firstProtocol = 'http';
    var secondProtocol = 'http';
    var candidates = <Map<String, dynamic>>[];

    String buildDirectJson() => jsonEncode({
      'name': proxyName.text.trim(),
      'group': group.text.trim(),
      'protocol': protocol,
      'server': server.text.trim(),
      'port': port.text.trim(),
      'username': username.text.trim(),
      'password': password.text,
    });

    String buildChainJson() => jsonEncode({
      'name': proxyName.text.trim(),
      'group': group.text.trim(),
      'localPort': localPort.text.trim(),
      'first': {
        'protocol': firstProtocol,
        'server': firstServer.text.trim(),
        'port': firstPort.text.trim(),
        'username': firstUsername.text.trim(),
        'password': firstPassword.text,
      },
      'second': {
        'protocol': secondProtocol,
        'server': secondServer.text.trim(),
        'port': secondPort.text.trim(),
        'username': secondUsername.text.trim(),
        'password': secondPassword.text,
      },
    });

    void applyTextToForm(void Function(void Function()) setDialog) {
      final raw = content.text.trim();
      if (raw.isEmpty) {
        showPrismNotice(context, '解析框内容为空');
        return;
      }
      try {
        if (mode == 'direct') {
          final parsed = _parseProxyImport('direct', raw, '').first;
          final urlParts = _decodeDirectProxyUrl(
            (parsed['config'] ?? '').toString(),
          );
          if (urlParts == null) throw const FormatException('无法识别为直连代理');
          setDialog(() {
            proxyName.text = (parsed['name'] ?? '').toString();
            if ((parsed['groupName'] ?? '').toString().isNotEmpty) {
              group.text = parsed['groupName'].toString();
            }
            protocol = urlParts['protocol']!;
            server.text = urlParts['server']!;
            port.text = urlParts['port']!;
            username.text = urlParts['username']!;
            password.text = urlParts['password']!;
          });
          showPrismNotice(context, '已应用文本到表单');
        } else if (mode == 'chain') {
          final parsed = _parseProxyImport('chain', raw, '').first;
          final chain = _decodeChainProxyConfig(
            (parsed['config'] ?? '').toString(),
          );
          if (chain == null) throw const FormatException('无法识别为链式代理');
          final f = Map<String, dynamic>.from(chain['first'] as Map);
          final s = Map<String, dynamic>.from(chain['second'] as Map);
          setDialog(() {
            proxyName.text = (parsed['name'] ?? '').toString();
            if ((parsed['groupName'] ?? '').toString().isNotEmpty) {
              group.text = parsed['groupName'].toString();
            }
            localPort.text = (chain['localPort'] ?? '').toString();
            firstProtocol = (f['protocol'] ?? 'http').toString();
            firstServer.text = (f['server'] ?? '').toString();
            firstPort.text = (f['port'] ?? '').toString();
            firstUsername.text = (f['username'] ?? '').toString();
            firstPassword.text = (f['password'] ?? '').toString();
            secondProtocol = (s['protocol'] ?? 'http').toString();
            secondServer.text = (s['server'] ?? '').toString();
            secondPort.text = (s['port'] ?? '').toString();
            secondUsername.text = (s['username'] ?? '').toString();
            secondPassword.text = (s['password'] ?? '').toString();
          });
          showPrismNotice(context, '已应用文本到表单');
        }
      } catch (error) {
        showPrismNotice(context, '应用文本失败：$error');
      }
    }

    try {
      final accepted = await showPrismDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: const Text('导入代理配置'),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrismDropdownField<String>(
                      value: mode,
                      decoration: const PrismInputDecoration(labelText: '导入类型'),
                      items: const [
                        PrismDropdownItem(
                          value: 'clash',
                          child: Text('Clash YAML / 节点列表'),
                        ),
                        PrismDropdownItem(
                          value: 'direct',
                          child: Text('HTTP / HTTPS / SOCKS5'),
                        ),
                        PrismDropdownItem(
                          value: 'chain',
                          child: Text('双层链式代理 JSON'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialog(() => mode = value ?? 'clash'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        prism.OutlinedButton.icon(
                          onPressed: () {
                            content.text = _importTemplateForMode(mode);
                            showPrismNotice(context, '已填入示例模板');
                          },
                          icon: const PrismGlyph(AntGlyphs.docs, size: 15),
                          label: const Text('填入模板'),
                        ),
                        prism.OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _importTemplateForMode(mode)),
                            );
                            if (context.mounted) {
                              showPrismNotice(context, '模板已复制到剪贴板');
                            }
                          },
                          icon: const PrismGlyph(AntGlyphs.copy, size: 15),
                          label: const Text('复制模板'),
                        ),
                        if (mode == 'direct' || mode == 'chain')
                          prism.OutlinedButton.icon(
                            onPressed: () => applyTextToForm(setDialog),
                            icon: const PrismGlyph(AntGlyphs.paste, size: 15),
                            label: const Text('应用文本'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (mode == 'direct') ...[
                      PrismDropdownField<String>(
                        value: protocol,
                        decoration: const PrismInputDecoration(
                          labelText: '代理协议',
                        ),
                        items: const [
                          PrismDropdownItem(value: 'http', child: Text('HTTP')),
                          PrismDropdownItem(
                            value: 'https',
                            child: Text('HTTPS'),
                          ),
                          PrismDropdownItem(
                            value: 'socks5',
                            child: Text('SOCKS5'),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialog(() => protocol = value ?? 'http'),
                      ),
                      const SizedBox(height: 8),
                      PrismTextField(
                        controller: proxyName,
                        decoration: const PrismInputDecoration(
                          labelText: '代理名称（可选）',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: PrismTextField(
                              controller: server,
                              decoration: const PrismInputDecoration(
                                labelText: '代理地址',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: PrismTextField(
                              controller: port,
                              keyboardType: TextInputType.number,
                              decoration: const PrismInputDecoration(
                                labelText: '端口',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: username,
                              decoration: const PrismInputDecoration(
                                labelText: '账号（可选）',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrismTextField(
                              controller: password,
                              obscureText: true,
                              decoration: const PrismInputDecoration(
                                labelText: '密码（可选）',
                              ),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: prism.TextButton(
                          onPressed: () => content.text = buildDirectJson(),
                          child: const Text('填入解析框'),
                        ),
                      ),
                    ],
                    if (mode == 'chain') ...[
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: PrismTextField(
                              controller: proxyName,
                              decoration: const PrismInputDecoration(
                                labelText: '代理名称（可选）',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrismTextField(
                              controller: localPort,
                              keyboardType: TextInputType.number,
                              decoration: const PrismInputDecoration(
                                labelText: '本地监听端口（可选）',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '第一层代理',
                        style: prism.AppTextStyle.footnote.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      PrismDropdownField<String>(
                        value: firstProtocol,
                        decoration: const PrismInputDecoration(
                          labelText: '第一层协议',
                        ),
                        items: const [
                          PrismDropdownItem(value: 'http', child: Text('HTTP')),
                          PrismDropdownItem(
                            value: 'socks5',
                            child: Text('SOCKS5'),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialog(() => firstProtocol = value ?? 'http'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: PrismTextField(
                              controller: firstServer,
                              decoration: const PrismInputDecoration(
                                labelText: '第一层代理地址',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrismTextField(
                              controller: firstPort,
                              keyboardType: TextInputType.number,
                              decoration: const PrismInputDecoration(
                                labelText: '端口',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: firstUsername,
                              decoration: const PrismInputDecoration(
                                labelText: '第一层账号（可选）',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrismTextField(
                              controller: firstPassword,
                              obscureText: true,
                              decoration: const PrismInputDecoration(
                                labelText: '第一层密码（可选）',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '第二层代理',
                        style: prism.AppTextStyle.footnote.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      PrismDropdownField<String>(
                        value: secondProtocol,
                        decoration: const PrismInputDecoration(
                          labelText: '第二层协议',
                        ),
                        items: const [
                          PrismDropdownItem(value: 'http', child: Text('HTTP')),
                          PrismDropdownItem(
                            value: 'socks5',
                            child: Text('SOCKS5'),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialog(() => secondProtocol = value ?? 'http'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: PrismTextField(
                              controller: secondServer,
                              decoration: const PrismInputDecoration(
                                labelText: '第二层代理地址',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrismTextField(
                              controller: secondPort,
                              keyboardType: TextInputType.number,
                              decoration: const PrismInputDecoration(
                                labelText: '端口',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: secondUsername,
                              decoration: const PrismInputDecoration(
                                labelText: '第二层账号（可选）',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrismTextField(
                              controller: secondPassword,
                              obscureText: true,
                              decoration: const PrismInputDecoration(
                                labelText: '第二层密码（可选）',
                              ),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: prism.TextButton(
                          onPressed: () => content.text = buildChainJson(),
                          child: const Text('填入解析框'),
                        ),
                      ),
                    ],
                    PrismTextField(
                      controller: content,
                      minLines: 7,
                      maxLines: 14,
                      decoration: PrismInputDecoration(
                        labelText: mode == 'clash'
                            ? '粘贴 Clash YAML'
                            : mode == 'direct'
                            ? '粘贴代理 JSON 或地址（留空时自动读取上方表单）'
                            : '粘贴双层代理 JSON（留空时自动读取上方表单）',
                        hintText: mode == 'direct'
                            ? 'socks5://user:password@127.0.0.1:1080'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (mode != 'chain') ...[
                      PrismTextField(
                        controller: prefix,
                        decoration: const PrismInputDecoration(
                          labelText: '节点名称前缀（可选）',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    PrismTextField(
                      controller: group,
                      decoration: const PrismInputDecoration(
                        labelText: '分组名称（可选）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismDropdownField<String>(
                      value: kernel,
                      decoration: const PrismInputDecoration(labelText: '代理内核'),
                      items: [
                        for (final k in _supportedKernels)
                          PrismDropdownItem(
                            value: k,
                            child: Text(_kernelLabels[k] ?? k),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialog(() => kernel = _normalizeKernel(value)),
                    ),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: dns,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const PrismInputDecoration(
                        labelText: '批量 DNS 配置（可选，订阅刷新会同步源 DNS；全局固定请用自定义桥接 DNS）',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              prism.FilledButton(
                onPressed: () {
                  try {
                    var effectiveContent = content.text.trim();
                    if (effectiveContent.isEmpty) {
                      if (mode == 'direct') {
                        effectiveContent = buildDirectJson();
                      } else if (mode == 'chain') {
                        effectiveContent = buildChainJson();
                      }
                    }
                    candidates = _parseProxyImport(
                      mode,
                      effectiveContent,
                      prefix.text,
                    );
                    Navigator.pop(context, true);
                  } catch (error) {
                    showPrismNotice(context, error.toString());
                  }
                },
                child: const Text('解析并预览'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true || !mounted) return;
      final selected = List<bool>.filled(candidates.length, true);
      final confirmed = await showPrismDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: Text('导入预览（${candidates.length} 个）'),
            content: SizedBox(
              width: 560,
              height: 420,
              child: ListView.builder(
                itemCount: candidates.length,
                itemBuilder: (context, index) {
                  final item = candidates[index];
                  return PrismCheckboxTile(
                    value: selected[index],
                    title: Text((item['name'] ?? '').toString()),
                    subtitle: Text(
                      (item['config'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (value) =>
                        setDialog(() => selected[index] = value ?? false),
                  );
                },
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              prism.FilledButton(
                onPressed: selected.any((item) => item)
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text('导入 ${selected.where((item) => item).length} 个'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      final retained = <Map<String, dynamic>>[];
      for (var i = 0; i < candidates.length; i++) {
        if (selected[i]) retained.add(candidates[i]);
      }
      final next = [..._proxies];
      for (var index = 0; index < retained.length; index++) {
        final item = retained[index];
        final name = (item['name'] ?? '').toString().trim();
        final config = (item['config'] ?? '').toString().trim();
        final groupName = group.text.trim().isNotEmpty
            ? group.text.trim()
            : (item['groupName'] ?? '').toString().trim();
        final existingIndex = next.indexWhere(
          (proxy) =>
              proxy['proxyName'] == name && proxy['proxyConfig'] == config,
        );
        final existing = existingIndex >= 0 ? next[existingIndex] : null;
        final row = <String, dynamic>{
          ...?existing,
          'proxyId':
              existing?['proxyId'] ??
              'proxy-${DateTime.now().microsecondsSinceEpoch}-$index',
          'proxyName': name,
          'proxyConfig': config,
          'groupName': groupName,
          'dnsServers': dns.text.trim().isEmpty
              ? (existing?['dnsServers'] ?? '')
              : dns.text.trim(),
        };
        final effectiveKernel = kernel == 'auto'
            ? _normalizeKernel(existing?['preferredKernel'])
            : kernel;
        _applyPreferredKernel(row, effectiveKernel);
        if (existingIndex >= 0) {
          next[existingIndex] = row;
        } else {
          next.add(row);
        }
      }
      await _save(next);
      if (mounted) showPrismNotice(context, '已导入 ${retained.length} 个代理');
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      _disposeEditControllers([
        content,
        prefix,
        group,
        dns,
        proxyName,
        server,
        port,
        username,
        password,
        localPort,
        firstServer,
        firstPort,
        firstUsername,
        firstPassword,
        secondServer,
        secondPort,
        secondUsername,
        secondPassword,
      ]);
    }
  }

  Future<void> _delete(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    final ok = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除代理？'),
        content: Text((proxy['proxyName'] ?? id).toString()),
        destructive: true,
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _save(_proxies.where((item) => item['proxyId'] != id).toList());
    }
  }

  int get _missingCount =>
      _proxies.where((proxy) => proxy['sourceMissing'] == true).length;

  Future<void> _cleanupMissing() async {
    setState(() => _busy = 'cleanup-preview');
    try {
      final preview = Map<String, dynamic>.from(
        await AppBridge.call('BrowserProxyCleanupMissing', ['', true]) as Map,
      );
      final scanned = int.tryParse('${preview['scanned'] ?? 0}') ?? 0;
      final deletable = int.tryParse('${preview['deletable'] ?? 0}') ?? 0;
      final skipped = (preview['skipped'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (scanned == 0) {
        if (mounted) showPrismNotice(context, '当前没有标记异常的订阅节点');
        return;
      }
      if (deletable == 0) {
        if (mounted) {
          showPrismNotice(context, '异常节点都仍被实例或虚拟分组引用，暂时不能清理');
        }
        return;
      }
      final confirmed = await showPrismDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => PrismDialog(
          title: const Text('清理异常节点？'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发现 $scanned 个订阅异常节点，可以安全删除 $deletable 个。'),
                if (skipped.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('以下 ${skipped.length} 个仍被使用，将保留：'),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final item in skipped)
                          Text(
                            '• ${(item['proxyName'] ?? item['proxyId'] ?? '').toString()} · ${switch (item['reason']) {
                              'instance' => '实例正在使用',
                              'virtual_group' => '虚拟分组正在使用',
                              'fetch_proxy' => '订阅刷新正在使用',
                              _ => '仍被引用',
                            }}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('删除 $deletable 个'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() => _busy = 'cleanup');
      final result = Map<String, dynamic>.from(
        await AppBridge.call('BrowserProxyCleanupMissing', ['', false]) as Map,
      );
      await _refresh();
      final deleted = int.tryParse('${result['deleted'] ?? 0}') ?? 0;
      final skippedCount = (result['skipped'] as List? ?? []).length;
      if (mounted) {
        showPrismNotice(
          context,
          skippedCount == 0
              ? '已清理 $deleted 个异常节点'
              : '已清理 $deleted 个，$skippedCount 个仍被使用的节点已保留',
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '清理异常节点失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _openProxyCoreDownload({String? initialCore}) async {
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _ProxyCoreDownloadDialog(
        initialCore: initialCore,
        usableProxies: _usableFetchProxies,
        speedResults: _speedResults,
      ),
    );
    if (mounted) unawaited(_refreshCoreStatuses());
  }

  Future<void> _openSourceRefreshModal() async {
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _ProxySourceRefreshModal(
        proxies: _proxies,
        usableProxies: _usableFetchProxies,
        speedResults: _speedResults,
        onChanged: _refresh,
      ),
    );
  }

  Future<void> _inspectVirtualGroupMembers(Map<String, dynamic> group) async {
    final id = (group['groupId'] ?? '').toString();
    final selected = <String>{
      ...(group['memberProxyIds'] as List? ?? [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty),
    };
    final groupNames = (group['memberGroupNames'] as List? ?? [])
        .map((value) => value.toString().trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final proxy in _proxies) {
      final pg = (proxy['groupName'] ?? '').toString().trim().toLowerCase();
      if (pg.isNotEmpty &&
          groupNames.contains(pg) &&
          proxy['proxyConfig'] != 'direct://') {
        selected.add((proxy['proxyId'] ?? '').toString());
      }
    }
    final healthRows = _virtualGroupHealth.where((row) => row['groupId'] == id);
    final health = healthRows.isEmpty ? null : healthRows.first;
    final memberHealth = (health?['members'] as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text('虚拟分组成员 · ${group['groupName'] ?? id}'),
        content: SizedBox(
          width: 660,
          height: 460,
          child: selected.isEmpty
              ? const PrismEmptyState(
                  title: '暂无关联代理',
                  subtitle: '可在虚拟分组管理中为该分组添加成员节点。',
                  glyph: AntGlyphs.hub,
                )
              : ListView.separated(
                  padding: kPrismListPadding,
                  itemCount: selected.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final proxyId = selected.elementAt(index);
                    final proxy = _proxies
                        .where((p) => p['proxyId'] == proxyId)
                        .firstOrNull;
                    final state = memberHealth
                        .where((r) => r['proxyId'] == proxyId)
                        .firstOrNull;
                    final (stateLabel, stateTone) = _localizedMemberState(
                      (state?['state'] ?? '').toString(),
                    );
                    final latency = state?['latencyMs'];
                    final endpoint = proxy == null
                        ? proxyId
                        : '${_proxyProtocol(proxy).toUpperCase()} · ${_proxyEndpointSummary(proxy)}';
                    return PrismCard(
                      margin: EdgeInsets.zero,
                      child: PrismListTile(
                        dense: true,
                        leading: PrismGlyph(
                          state?['active'] == true
                              ? AntGlyphs.checkCircle
                              : AntGlyphs.circle,
                          size: 18,
                          color: PrismToneColors.of(context, stateTone).fg,
                        ),
                        title: Text(
                          (proxy?['proxyName'] ??
                                  state?['proxyName'] ??
                                  proxyId)
                              .toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$endpoint${latency is num && latency > 0 ? ' · ${latency}ms' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PrismBadge(
                          label: stateLabel,
                          tone: stateTone,
                          dot: true,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          prism.OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onOpenGroups();
            },
            child: const Text('管理虚拟分组'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _test(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    setState(() {
      _busy = id;
      _testingIds.add(id);
    });
    try {
      final result = await AppBridge.call('BrowserProxyTestSpeed', [id]);
      final row = Map<String, dynamic>.from(result as Map);
      _speedResults[id] = row;
      if (mounted) setState(() {});
      final message = row['ok'] == true
          ? '连接成功，延迟 ${row['latencyMs'] ?? 0} ms'
          : '连接失败：${row['error'] ?? '未知错误'}';
      if (mounted) showPrismNotice(context, message);
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _testingIds.remove(id);
          _busy = '';
        });
      }
    }
  }

  Future<void> _testIpHealth(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    setState(() => _busy = id);
    try {
      final result = await AppBridge.call('BrowserProxyCheckIPHealth', [id]);
      final row = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};
      _ipHealthResults[id] = row;
      if (mounted) setState(() {});
      final message = row['ok'] == true
          ? 'IP 检查完成：${row['ip'] ?? '未返回 IP'} · ${row['country'] ?? row['region'] ?? ''}'
          : 'IP 检查失败：${row['error'] ?? '未知错误'}';
      if (mounted) showPrismNotice(context, message);
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  bool _isAvailable(Map<String, dynamic> proxy) {
    final id = (proxy['proxyId'] ?? '').toString();
    return _speedResults[id]?['ok'] == true ||
        _ipHealthResults[id]?['ok'] == true;
  }

  Future<void> _testAll(List<Map<String, dynamic>> proxies) async {
    final ids = proxies
        .where((proxy) => proxy['proxyConfig'] != 'direct://')
        .map((proxy) => (proxy['proxyId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    setState(() {
      _busy = 'batch-speed';
      _testingIds.addAll(ids);
    });
    try {
      final raw = await AppBridge.call('BrowserProxyBatchTestSpeed', [ids, 0]);
      final results = raw is List ? raw : const [];
      var failed = 0;
      for (final item in results.whereType<Map>()) {
        final result = Map<String, dynamic>.from(item);
        final id = (result['proxyId'] ?? '').toString();
        if (id.isNotEmpty) {
          _testingIds.remove(id);
          _speedResults[id] = result;
        }
        if (result['ok'] != true) failed++;
      }
      if (mounted) {
        setState(() {});
        showPrismNotice(
          context,
          failed == 0
              ? '批量测速完成：${results.length} 个代理'
              : '批量测速完成：${results.length - failed} 个成功，$failed 个失败',
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '批量测速失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _testingIds.removeAll(ids);
          _busy = '';
        });
      }
    }
  }

  Future<void> _checkAllIPHealth(List<Map<String, dynamic>> proxies) async {
    final ids = proxies
        .map((proxy) => (proxy['proxyId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    setState(() => _busy = 'batch-ip');
    try {
      final raw = await AppBridge.call('BrowserProxyBatchCheckIPHealth', [
        ids,
        10,
      ]);
      final results = raw is List ? raw : const [];
      var failed = 0;
      for (final item in results.whereType<Map>()) {
        final result = Map<String, dynamic>.from(item);
        final id = (result['proxyId'] ?? '').toString();
        if (id.isNotEmpty) _ipHealthResults[id] = result;
        if (result['ok'] != true) failed++;
      }
      if (mounted) {
        setState(() {});
        showPrismNotice(
          context,
          failed == 0
              ? 'IP 健康检测完成：${results.length} 个代理'
              : 'IP 健康检测完成：${results.length - failed} 个成功，$failed 个失败',
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '批量 IP 检测失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _warmupBridge(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() => _busy = id);
    try {
      final result = await AppBridge.call('BrowserProxyWarmupBridge', [id]);
      final map = result is Map ? Map<String, dynamic>.from(result) : {};
      final ok = map['ok'] == true;
      final latency = (map['latencyMs'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() {});
        showPrismNotice(
          context,
          ok
              ? '桥接预热成功：${proxy['proxyName'] ?? id}（${latency}ms）'
              : '桥接预热失败：${map['error'] ?? '未知错误'}',
          level: ok ? prism.BannerLevel.info : prism.BannerLevel.error,
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '桥接预热失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _warmupAll(List<Map<String, dynamic>> proxies) async {
    final ids = proxies
        .where((proxy) => proxy['proxyConfig'] != 'direct://')
        .map((proxy) => (proxy['proxyId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      showPrismNotice(context, '当前没有需要预热的代理');
      return;
    }
    setState(() => _busy = 'batch-warmup');
    try {
      final raw = await AppBridge.call('BrowserProxyBatchWarmupBridge', [
        ids,
        5,
      ]);
      final results = raw is List ? raw : const [];
      var failed = 0;
      for (final item in results.whereType<Map>()) {
        if (Map<String, dynamic>.from(item)['ok'] != true) failed++;
      }
      if (mounted) {
        showPrismNotice(
          context,
          failed == 0
              ? '桥接预热完成：${results.length} 个代理'
              : '桥接预热完成：${results.length - failed} 个成功，$failed 个失败',
          level: failed == 0 ? prism.BannerLevel.info : prism.BannerLevel.error,
        );
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '批量桥接预热失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _refreshAllSources() async {
    final sources = <String, Map<String, dynamic>>{};
    for (final proxy in _proxies) {
      final id = (proxy['sourceId'] ?? '').toString();
      if (id.isNotEmpty && (proxy['sourceUrl'] ?? '').toString().isNotEmpty) {
        sources.putIfAbsent(id, () => proxy);
      }
    }
    if (sources.isEmpty) {
      showPrismNotice(context, '当前没有可刷新的订阅');
      return;
    }
    setState(() => _busy = 'refresh-all');
    var succeeded = 0;
    var failed = 0;
    try {
      for (final entry in sources.entries) {
        try {
          await AppBridge.call('BrowserProxyRefreshSource', [
            entry.key,
            entry.value['sourceFetchProxyId'] ?? '',
          ]);
          succeeded++;
        } catch (_) {
          failed++;
        }
      }
      await _refresh();
      if (mounted) {
        showPrismNotice(
          context,
          failed == 0
              ? '已刷新 $succeeded 个订阅'
              : '刷新完成：$succeeded 个成功，$failed 个失败',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _refreshSource(Map<String, dynamic> proxy) async {
    final sourceId = (proxy['sourceId'] ?? '').toString();
    if (sourceId.isEmpty) return;
    setState(() => _busy = sourceId);
    try {
      await AppBridge.call('BrowserProxyRefreshSource', [
        sourceId,
        proxy['sourceFetchProxyId'] ?? '',
      ]);
      await _refresh();
      if (mounted) showPrismNotice(context, '订阅刷新完成');
    } catch (error) {
      if (mounted) showPrismNotice(context, '刷新订阅失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedIds.toList();
    if (selected.isEmpty) return;
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除所选代理？'),
        content: Text('将从代理池删除 ${selected.length} 个代理。'),
        destructive: true,
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = 'delete-selected');
    try {
      await _save(
        _proxies
            .where((proxy) => !selected.contains(proxy['proxyId']))
            .toList(),
      );
      if (mounted) {
        setState(() => _selectedIds.clear());
        showPrismNotice(context, '已删除 ${selected.length} 个代理');
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '批量删除失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _showIPHealthDetail(Map<String, dynamic> proxy) async {
    final id = (proxy['proxyId'] ?? '').toString();
    final result = _ipHealthResults[id];
    if (result == null) {
      showPrismNotice(context, '请先检测此代理的 IP 健康信息');
      return;
    }
    final rawData = result['rawData'] is Map ? result['rawData'] : result;
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('IP 健康检测详情'),
        content: SizedBox(
          width: 680,
          height: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '代理：${proxy['proxyName'] ?? id}  ·  来源：${result['source'] ?? '-'}  ·  时间：${result['updatedAt'] ?? '-'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: prism.AppTextStyle.footnote.of(context),
              ),
              if (result['ok'] != true) ...[
                const SizedBox(height: 8),
                PrismBanner(
                  tone: PrismTone.danger,
                  message: '检测失败：${result['error'] ?? '未知错误'}',
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: PrismCodeSurface(
                  language: 'json',
                  code: const JsonEncoder.withIndent('  ').convert(rawData),
                ),
              ),
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

  Future<void> _showUsageGuide() async {
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => const _ProxyUsageGuideDialog(),
    );
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _filterProtocol = 'all';
      _filterGroup = 'all';
      _sortBy = '';
      _sortDescending = false;
      _availableOnly = false;
    });
  }

  Future<void> _editCheckSettings() async {
    try {
      final raw = await AppBridge.call('GetProxyCheckSettings');
      if (raw is! Map) return;
      final settings = Map<String, dynamic>.from(raw);
      final bridgeTimeout = TextEditingController(
        text: '${settings['bridgeStartTimeoutMs'] ?? 15000}',
      );
      final interval = TextEditingController(
        text: '${settings['speedIntervalMinutes'] ?? 30}',
      );
      final retry = TextEditingController(
        text: '${settings['failureRetryMinutes'] ?? 5}',
      );
      final concurrency = TextEditingController(
        text: '${settings['speedConcurrency'] ?? 5}',
      );
      final speedTarget = TextEditingController(
        text: '${settings['speedTargetId'] ?? ''}',
      );
      final healthTarget = TextEditingController(
        text: '${settings['ipHealthTargetId'] ?? ''}',
      );
      final targets = TextEditingController(
        text: const JsonEncoder.withIndent('  ')
            .convert(settings['targets'] ?? []),
      );
      var filterAvailableOnly =
          settings['filterAvailableOnly'] == true || _availableOnly;
      final result = await showPrismDialog<Map<String, dynamic>>(
        context: context,
        useRootNavigator: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => PrismDialog(
            title: const Text('代理检测设置'),
            content: SizedBox(
              width: 620,
              height: 580,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrismSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('仅显示可选'),
                      subtitle: const Text('在代理池和代理选择器中默认隐藏不可用节点'),
                      value: filterAvailableOnly,
                      onChanged: (value) =>
                          setDialog(() => filterAvailableOnly = value),
                    ),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: bridgeTimeout,
                      keyboardType: TextInputType.number,
                      decoration: const PrismInputDecoration(
                        labelText: '代理启动等待（毫秒）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: interval,
                      keyboardType: TextInputType.number,
                      decoration: const PrismInputDecoration(
                        labelText: '成功节点重测间隔（分钟）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: retry,
                      keyboardType: TextInputType.number,
                      decoration: const PrismInputDecoration(
                        labelText: '失败重试间隔（分钟）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: concurrency,
                      keyboardType: TextInputType.number,
                      decoration: const PrismInputDecoration(
                        labelText: '测速并发上限（1 到 10）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: speedTarget,
                      decoration: const PrismInputDecoration(
                        labelText: '测速目标 ID',
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: healthTarget,
                      decoration: const PrismInputDecoration(
                        labelText: 'IP 健康目标 ID',
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: targets,
                      minLines: 8,
                      maxLines: 16,
                      decoration: const PrismInputDecoration(
                        labelText: '检测目标列表 JSON',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              prism.FilledButton(
                onPressed: () {
                  try {
                    final parsedTargets = jsonDecode(targets.text);
                    if (parsedTargets is! List) {
                      throw const FormatException('目标列表必须是 JSON 数组');
                    }
                    Navigator.pop(context, {
                      ...settings,
                      'filterAvailableOnly': filterAvailableOnly,
                      'bridgeStartTimeoutMs':
                          int.tryParse(bridgeTimeout.text) ?? 15000,
                      'speedIntervalMinutes': int.tryParse(interval.text) ?? 30,
                      'failureRetryMinutes': int.tryParse(retry.text) ?? 5,
                      'speedConcurrency': (int.tryParse(concurrency.text) ?? 5)
                          .clamp(1, 10),
                      'speedTargetId': speedTarget.text.trim(),
                      'ipHealthTargetId': healthTarget.text.trim(),
                      'targets': parsedTargets,
                    });
                  } catch (error) {
                    showPrismNotice(context, '检测目标 JSON 无效：$error');
                  }
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      _disposeEditControllers([
        bridgeTimeout,
        interval,
        retry,
        concurrency,
        speedTarget,
        healthTarget,
        targets,
      ]);
      if (result == null) return;
      await AppBridge.call('SaveProxyCheckSettings', [result]);
      if (mounted) {
        setState(() {
          _availableOnly = result['filterAvailableOnly'] == true;
        });
        await _refresh();
        if (mounted) showPrismNotice(context, '代理检测设置已保存');
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    }
  }

  Future<void> _importSubscription() async {
    final url = TextEditingController();
    final prefix = TextEditingController();
    final group = TextEditingController();
    final dns = TextEditingController();
    final interval = TextEditingController(text: '1440');
    var autoRefresh = false;
    var fetchProxyId = '';
    final usableProxies = _usableFetchProxies;

    try {
      while (mounted) {
        final accepted = await showPrismDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialog) => PrismDialog(
              title: const Text('导入代理订阅'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrismTextField(
                        controller: url,
                        autofocus: true,
                        decoration: const PrismInputDecoration(
                          labelText: '订阅地址',
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrismTextField(
                        controller: prefix,
                        decoration: const PrismInputDecoration(
                          labelText: '节点名前缀（可选）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrismTextField(
                        controller: group,
                        decoration: const PrismInputDecoration(
                          labelText: '代理分组（可选）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrismTextField(
                        controller: dns,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const PrismInputDecoration(
                          labelText: '批量 DNS 配置（可选）',
                          hintText: 'dns:\n  enable: true\n  nameserver:\n    - 119.29.29.29',
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrismDropdownField<String>(
                        value: fetchProxyId,
                        decoration: const PrismInputDecoration(
                          labelText: '拉取订阅使用的代理（仅显示测速可用节点）',
                        ),
                        items: [
                          const PrismDropdownItem(value: '', child: Text('直连')),
                          for (final proxy in usableProxies)
                            PrismDropdownItem(
                              value: (proxy['proxyId'] ?? '').toString(),
                              child: Text(
                                '${proxy['proxyName'] ?? '未命名代理'} (${_speedResults[(proxy['proxyId'] ?? '').toString()]?['latencyMs'] ?? 0}ms)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setDialog(() => fetchProxyId = value ?? ''),
                      ),
                      const SizedBox(height: 12),
                      PrismSwitchTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自动刷新'),
                        value: autoRefresh,
                        onChanged: (value) =>
                            setDialog(() => autoRefresh = value),
                      ),
                      if (autoRefresh) ...[
                        const SizedBox(height: 10),
                        PrismTextField(
                          controller: interval,
                          keyboardType: TextInputType.number,
                          decoration: const PrismInputDecoration(
                            labelText: '刷新间隔（分钟，5–1440）',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final preset in const [
                              ('60', '1 小时'),
                              ('360', '6 小时'),
                              ('720', '12 小时'),
                              ('1440', '24 小时'),
                            ])
                              PrismChip(
                                label: Text(preset.$2),
                                selected: interval.text.trim() == preset.$1,
                                onPressed: () =>
                                    setDialog(() => interval.text = preset.$1),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                prism.TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                prism.FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('拉取并预览'),
                ),
              ],
            ),
          ),
        );
        if (accepted != true || url.text.trim().isEmpty || !mounted) return;

        setState(() => _busy = 'subscription');
        Map<String, dynamic> fetched;
        List<Map<String, dynamic>> nodes;
        final importUrl = url.text.trim();
        final importPrefix = prefix.text.trim();
        try {
          final fetch = await AppBridge.call(
            fetchProxyId.isEmpty
                ? 'BrowserProxyFetchClashByURL'
                : 'BrowserProxyFetchClashByURLWithProxy',
            fetchProxyId.isEmpty ? [importUrl] : [importUrl, fetchProxyId],
          );
          fetched = Map<String, dynamic>.from(fetch as Map);
          nodes = _parseClashNodes(
            (fetched['content'] ?? '').toString(),
            importPrefix,
          );
          if (group.text.trim().isEmpty &&
              fetched['suggestedGroup']?.toString().trim().isNotEmpty == true) {
            group.text = fetched['suggestedGroup'].toString().trim();
          }
        } catch (error) {
          if (mounted) showPrismNotice(context, error.toString());
          if (mounted) setState(() => _busy = '');
          return;
        } finally {
          if (mounted) setState(() => _busy = '');
        }

        if (!mounted) return;
        final choice = await _chooseSubscriptionNodes(nodes);
        if (!mounted || choice == null) return;
        if (choice.backToEdit) continue;
        final selectedIndices = choice.selected;
        if (selectedIndices.isEmpty) return;

        setState(() => _busy = 'subscription');
        try {
          final minutes = autoRefresh
              ? (int.tryParse(interval.text) ?? 1440).clamp(5, 1440)
              : 0;
          final selectedNodes = nodes
              .where((node) => selectedIndices.contains(node['index']))
              .toList();
          final existingSourceId = _proxies
              .where(
                (proxy) =>
                    _normalizedSubscriptionUrl(
                          proxy['sourceUrl']?.toString() ?? '',
                        ) ==
                        _normalizedSubscriptionUrl(importUrl) &&
                    (proxy['sourceNamePrefix'] ?? '').toString().trim() ==
                        importPrefix,
              )
              .map((proxy) => (proxy['sourceId'] ?? '').toString().trim())
              .firstWhere((id) => id.isNotEmpty, orElse: () => '');
          final sourceId = existingSourceId.isEmpty
              ? _stableSourceId(importUrl, importPrefix)
              : existingSourceId;
          final now = DateTime.now().toUtc().toIso8601String();
          final existingRows = _proxies
              .where(
                (proxy) => (proxy['sourceId'] ?? '').toString() == sourceId,
              )
              .toList();
          final consumedOld = <String>{};
          final imported = <Map<String, dynamic>>[];
          for (var index = 0; index < selectedNodes.length; index++) {
            final node = selectedNodes[index];
            final name = node['name'].toString();
            Map<String, dynamic>? old;
            for (final candidate in existingRows) {
              final id = (candidate['proxyId'] ?? '').toString();
              if (consumedOld.contains(id)) continue;
              if ((candidate['proxyName'] ?? '').toString() == name ||
                  (candidate['proxyConfig'] ?? '').toString() ==
                      node['config']) {
                old = candidate;
                consumedOld.add(id);
                break;
              }
            }
            final row = <String, dynamic>{
              'proxyId':
                  old?['proxyId'] ??
                  'proxy-${DateTime.now().microsecondsSinceEpoch}-$index',
              'proxyName': name,
              'proxyConfig': node['config'],
              'dnsServers': dns.text.trim().isEmpty
                  ? (fetched['dnsServers'] ?? '').toString()
                  : dns.text.trim(),
              'groupName': group.text.trim(),
              'sourceId': sourceId,
              'sourceUrl': (fetched['url'] ?? importUrl).toString(),
              'sourceNamePrefix': importPrefix,
              'sourceAutoRefresh': autoRefresh,
              'sourceRefreshIntervalM': minutes,
              'sourceLastRefreshAt': now,
              'sourceFetchProxyId': fetchProxyId,
              'sourceMissing': false,
              'sourceMissingSince': '',
              'sourceLastRefreshError': '',
            };
            _applyPreferredKernel(
              row,
              _normalizeKernel(old?['preferredKernel']),
            );
            imported.add(row);
          }
          final missing = existingRows
              .where(
                (proxy) =>
                    !consumedOld.contains((proxy['proxyId'] ?? '').toString()),
              )
              .map(
                (proxy) => {
                  ...proxy,
                  'sourceAutoRefresh': autoRefresh,
                  'sourceRefreshIntervalM': minutes,
                  'sourceFetchProxyId': fetchProxyId,
                  'sourceMissing': true,
                  'sourceMissingSince':
                      (proxy['sourceMissingSince'] ?? '').toString().isEmpty
                      ? now
                      : proxy['sourceMissingSince'],
                },
              )
              .toList();
          final next = [
            ..._proxies.where(
              (proxy) =>
                  (proxy['sourceId'] ?? '').toString() != sourceId &&
                  (proxy['proxyId'] ?? '').toString() != '__direct__',
            ),
            ...imported,
            ...missing,
          ];
          await AppBridge.call('SaveBrowserProxies', [next]);
          final ignoredNames = nodes
              .where((node) => !selectedIndices.contains(node['index']))
              .map((node) => node['name'].toString())
              .toList();
          await AppBridge.call('BrowserProxySetSourceIgnoredNames', [
            sourceId,
            ignoredNames,
          ]);
          await _refresh();
          if (mounted) {
            showPrismNotice(context, '导入完成：保存 ${imported.length} 个代理');
          }
        } catch (error) {
          if (mounted) showPrismNotice(context, error.toString());
        } finally {
          if (mounted) setState(() => _busy = '');
        }
        return;
      }
    } finally {
      _disposeEditControllers([url, prefix, group, dns, interval]);
    }
  }

  String _normalizedSubscriptionUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    try {
      return Uri.parse(raw).replace(fragment: '').toString();
    } catch (_) {
      return raw;
    }
  }

  Future<({Set<int> selected, bool backToEdit})?> _chooseSubscriptionNodes(
    List<Map<String, dynamic>> nodes,
  ) => showPrismDialog<({Set<int> selected, bool backToEdit})>(
    context: context,
    useRootNavigator: false,
    builder: (context) {
      final selected = nodes.map((node) => node['index'] as int).toSet();
      return StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: Text('选择要导入的节点（${nodes.length}）'),
          content: SizedBox(
            width: 560,
            height: 480,
            child: ListView.builder(
              itemCount: nodes.length,
              itemBuilder: (context, index) {
                final node = nodes[index];
                final nodeIndex = node['index'] as int;
                return PrismCheckboxTile(
                  value: selected.contains(nodeIndex),
                  title: Text(node['name'].toString()),
                  subtitle: Text(
                    '${node['server'] ?? ''}:${node['port'] ?? ''} · ${node['type'] ?? ''}',
                  ),
                  onChanged: (value) => setDialog(() {
                    if (value == true) {
                      selected.add(nodeIndex);
                    } else {
                      selected.remove(nodeIndex);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            prism.OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, (selected: <int>{}, backToEdit: true)),
              child: const Text('返回修改'),
            ),
            prism.FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, (
                      selected: selected,
                      backToEdit: false,
                    )),
              child: Text('导入 ${selected.length} 个'),
            ),
          ],
        ),
      );
    },
  );

  (String, PrismTone) _latencyBadgeInfo(Map<String, dynamic> proxy) {
    final id = (proxy['proxyId'] ?? '').toString();
    if (proxy['proxyConfig'] == 'direct://') {
      return ('不适用', PrismTone.neutral);
    }
    if (_testingIds.contains(id)) {
      return ('测试中...', PrismTone.info);
    }
    final speed = _speedResults[id];
    if (speed == null) return ('未测速', PrismTone.neutral);
    if (speed['ok'] == true) {
      final ms = int.tryParse('${speed['latencyMs'] ?? 0}') ?? 0;
      if (ms < 200) return ('${ms}ms', PrismTone.success);
      if (ms < 500) return ('${ms}ms', PrismTone.warning);
      return ('${ms}ms', PrismTone.danger);
    }
    final err = (speed['error'] ?? '').toString().toLowerCase();
    if (err.contains('timeout') ||
        err.contains('deadline') ||
        err.contains('超时')) {
      return ('超时', PrismTone.warning);
    }
    if (err.contains('unsupported') || err.contains('不支持')) {
      return ('不支持', PrismTone.neutral);
    }
    return ('失败', PrismTone.danger);
  }

  Widget _buildOverviewStrip(BuildContext context, {required bool hasSources}) {
    final realProxies = _proxies
        .where(
          (item) =>
              (item['proxyId'] ?? '').toString() != '__direct__' &&
              item['proxyConfig'] != 'direct://',
        )
        .toList();
    final protocolCount = realProxies
        .map(_proxyProtocol)
        .where((p) => p != '-')
        .toSet()
        .length;
    final availableCount = realProxies.where(_isAvailable).length;
    final testedCount = realProxies
        .where(
          (p) => _speedResults.containsKey((p['proxyId'] ?? '').toString()),
        )
        .length;
    final sourceCount = realProxies
        .map((p) => (p['sourceId'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
    final missingCount = _missingCount;
    final installedCores = _coreStatuses.entries
        .where((e) => e.value['installed'] == true)
        .length;
    final totalCores = _coreStatuses.length;
    final hasActiveFilters =
        _query.isNotEmpty ||
        _filterProtocol != 'all' ||
        _filterGroup != 'all' ||
        _sortBy.isNotEmpty ||
        _availableOnly;

    final tiles = [
      PrismMetricTile(
        label: '节点总数',
        value: '${realProxies.length}',
        subtitle: realProxies.isEmpty
            ? '点击添加代理或导入订阅'
            : '$protocolCount 种协议 · ${_virtualGroups.length} 虚拟组',
        glyph: AntGlyphs.globe,
        tone: PrismTone.primary,
        onPressed: hasActiveFilters ? _clearFilters : null,
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '可用节点',
        value: '$availableCount',
        subtitle: testedCount > 0
            ? '已测速 $testedCount 个 · ${_availableOnly ? '仅看可用中' : '点击筛选可用'}'
            : '尚未完成批量测速',
        glyph: AntGlyphs.checkCircle,
        tone: _availableOnly
            ? PrismTone.primary
            : (availableCount > 0 ? PrismTone.success : PrismTone.neutral),
        onPressed: () => setState(() => _availableOnly = !_availableOnly),
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '订阅来源',
        value: '$sourceCount',
        subtitle: missingCount > 0
            ? '异常节点 $missingCount 个 · 点击管理'
            : (hasSources ? '点击管理订阅自动更新' : '暂无远程订阅源'),
        glyph: AntGlyphs.sync,
        tone: missingCount > 0 ? PrismTone.warning : PrismTone.info,
        onPressed: _busy.isEmpty ? _openSourceRefreshModal : null,
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '代理内核',
        value: _coreStatuses.isEmpty ? '检测中' : '$installedCores/$totalCores',
        subtitle: _coreStatuses.isEmpty
            ? '正在检查 Xray / Sing-box / Mihomo'
            : (installedCores == totalCores ? '内核已就绪 · 点击管理' : '点击下载或管理代理内核'),
        glyph: AntGlyphs.cpu,
        tone: _coreStatuses.isEmpty
            ? PrismTone.neutral
            : (installedCores > 0 ? PrismTone.primary : PrismTone.warning),
        onPressed: () => _openProxyCoreDownload(),
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

  Widget _buildToolbar(
    BuildContext context, {
    required List<String> protocols,
    required List<String> groups,
    required List<Map<String, dynamic>> visible,
    required bool hasSources,
  }) {
    final activeFilterCount =
        (_filterProtocol != 'all' ? 1 : 0) +
        (_filterGroup != 'all' ? 1 : 0) +
        (_sortBy.isNotEmpty ? 1 : 0);
    final hasAnyFilter =
        activeFilterCount > 0 || _query.isNotEmpty || _availableOnly;

    final availabilityFilter = SizedBox(
      width: 136,
      child: prism.SegmentedControl<String>(
        value: _availableOnly ? 'available' : 'all',
        onChanged: (value) =>
            setState(() => _availableOnly = value == 'available'),
        segments: const [('all', '全部'), ('available', '可用')],
      ),
    );

    final actionWidgets = <Widget>[
      PrismTonalButton.icon(
        onPressed: () => setState(() => _filtersCollapsed = !_filtersCollapsed),
        icon: PrismGlyph(
          _filtersCollapsed ? AntGlyphs.chevronDown : AntGlyphs.chevronUp,
          size: 15,
        ),
        child: Text(activeFilterCount > 0 ? '筛选 ($activeFilterCount)' : '筛选'),
      ),
      PrismHoverMotion(
        child: prism.FilledButton.icon(
          onPressed: () => _edit(),
          icon: const PrismGlyph(AntGlyphs.add, size: 15),
          label: const Text('添加代理'),
        ),
      ),
      prism.TonalButtonGroup(
        size: prism.TonalButtonSize.section,
        children: [
          prism.IconButton(
            tooltip: '导入订阅',
            onPressed: _busy.isEmpty ? _importSubscription : null,
            icon: const PrismGlyph(AntGlyphs.upload, size: 17),
          ),
          prism.IconButton(
            tooltip: _busy == 'batch-speed' ? '测速中…' : '批量测速',
            onPressed: _busy.isEmpty ? () => _testAll(visible) : null,
            icon: _busy == 'batch-speed'
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: PrismProgressIndicator(size: 17),
                  )
                : const PrismGlyph(AntGlyphs.speed, size: 17),
          ),
          prism.IconButton(
            tooltip: _refreshing ? '刷新中…' : '刷新列表',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: PrismProgressIndicator(size: 17),
                  )
                : const PrismGlyph(AntGlyphs.refresh, size: 17),
          ),
        ],
      ),
      PrismPopupMenuButton<String>(
        tooltip: '更多操作',
        enabled: _busy.isEmpty,
        icon: const PrismGlyph(AntGlyphs.more, size: 17),
        itemBuilder: (_) => [
          const PrismMenuItem(value: 'import-sub', child: Text('导入订阅')),
          const PrismMenuItem(value: 'import-proxies', child: Text('导入代理')),
          const PrismMenuItem(value: 'check-ip', child: Text('检测 IP 健康')),
          const PrismMenuItem(value: 'warmup', child: Text('桥接预热全部')),
          PrismMenuItem(
            value: 'refresh-sources',
            enabled: hasSources,
            child: const Text('刷新全部订阅'),
          ),
          const PrismMenuItem(value: 'source-modal', child: Text('更新管理')),
          const PrismMenuItem(value: 'groups', child: Text('虚拟分组')),
          const PrismMenuItem(value: 'align', child: Text('订阅管理')),
          const PrismMenuItem(value: 'check-settings', child: Text('代理检测设置')),
          PrismMenuItem(
            value: 'cleanup-missing',
            enabled: _missingCount > 0,
            child: Text('清理异常订阅节点（$_missingCount）'),
          ),
          const PrismMenuItem(value: 'core-download', child: Text('下载代理内核')),
          const PrismMenuItem(value: 'guide', child: Text('使用说明')),
        ],
        onSelected: (action) {
          switch (action) {
            case 'import-sub':
              _importSubscription();
            case 'import-proxies':
              _importProxies();
            case 'check-ip':
              _checkAllIPHealth(visible);
            case 'warmup':
              _warmupAll(visible);
            case 'refresh-sources':
              _refreshAllSources();
            case 'source-modal':
              _openSourceRefreshModal();
            case 'groups':
              widget.onOpenGroups();
            case 'align':
              widget.onOpenAlign();
            case 'check-settings':
              _editCheckSettings();
            case 'cleanup-missing':
              _cleanupMissing();
            case 'core-download':
              _openProxyCoreDownload();
            case 'guide':
              _showUsageGuide();
          }
        },
      ),
    ];

    final filterFields = <Widget>[
      PrismDropdownField<String>(
        value: _filterProtocol,
        decoration: const PrismInputDecoration(labelText: '代理协议'),
        items: [
          const PrismDropdownItem(value: 'all', child: Text('全部协议')),
          for (final protocol in protocols)
            PrismDropdownItem(
              value: protocol,
              child: Text(protocol.toUpperCase()),
            ),
        ],
        onChanged: (value) => setState(() => _filterProtocol = value ?? 'all'),
      ),
      PrismDropdownField<String>(
        value: _filterGroup,
        decoration: const PrismInputDecoration(labelText: '代理分组'),
        items: [
          const PrismDropdownItem(value: 'all', child: Text('全部分组')),
          for (final group in groups)
            PrismDropdownItem(value: group, child: Text(group)),
          for (final group in _virtualGroups)
            PrismDropdownItem(
              value: _virtualGroupFilterKey(group),
              child: Text('虚拟：${group['groupName']}'),
            ),
        ],
        onChanged: (value) => setState(() => _filterGroup = value ?? 'all'),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: PrismDropdownField<String>(
              value: _sortBy,
              decoration: const PrismInputDecoration(labelText: '排序'),
              items: const [
                PrismDropdownItem(value: '', child: Text('默认顺序')),
                PrismDropdownItem(value: 'name', child: Text('代理名称')),
                PrismDropdownItem(value: 'group', child: Text('分组')),
                PrismDropdownItem(value: 'protocol', child: Text('协议')),
                PrismDropdownItem(value: 'server', child: Text('服务器')),
                PrismDropdownItem(value: 'port', child: Text('端口')),
                PrismDropdownItem(value: 'latency', child: Text('延迟')),
              ],
              onChanged: (value) => setState(() => _sortBy = value ?? ''),
            ),
          ),
          const SizedBox(width: 6),
          prism.IconButton(
            tooltip: _sortDescending ? '降序' : '升序',
            onPressed: () => setState(() => _sortDescending = !_sortDescending),
            icon: PrismGlyph(
              _sortDescending ? AntGlyphs.arrowDown : AntGlyphs.arrowUp,
              size: 18,
            ),
          ),
        ],
      ),
    ];

    return PrismHoverCard(
      staggerIndex: 4,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              if (wide) {
                return Row(
                  children: [
                    Expanded(
                      child: PrismSearchBar(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        hintText: '搜索代理名称、地址或分组…',
                        height: 36,
                      ),
                    ),
                    const SizedBox(width: 12),
                    availabilityFilter,
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actionWidgets,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: PrismSearchBar(
                          controller: _searchController,
                          onChanged: (value) => setState(() => _query = value),
                          hintText: '搜索代理名称、地址或分组…',
                          height: 36,
                        ),
                      ),
                      const SizedBox(width: 12),
                      availabilityFilter,
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actionWidgets,
                  ),
                ],
              );
            },
          ),
          PrismCollapsible(
            expanded: !_filtersCollapsed,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 14),
                const prism.Divider(height: 1),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 760) {
                      return Row(
                        children: [
                          for (var i = 0; i < filterFields.length; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            Expanded(child: filterFields[i]),
                          ],
                        ],
                      );
                    }
                    return Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        for (final field in filterFields)
                          SizedBox(width: 210, child: field),
                      ],
                    );
                  },
                ),
                if (_virtualGroups.isNotEmpty || hasAnyFilter) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_virtualGroups.isNotEmpty) ...[
                        Text(
                          '虚拟分组：',
                          style: prism.AppTextStyle.caption1
                              .of(context, emphasized: true)
                              .copyWith(
                                color: prism.Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        for (final vg in _virtualGroups)
                          Builder(
                            builder: (context) {
                              final vgId = (vg['groupId'] ?? '').toString();
                              final vgName = (vg['groupName'] ?? vgId)
                                  .toString();
                              final h = _virtualGroupHealth
                                  .where((r) => r['groupId'] == vgId)
                                  .firstOrNull;
                              final count =
                                  (vg['memberProxyIds'] as List? ?? []).length;
                              final tone = h == null
                                  ? PrismTone.primary
                                  : h['allDegraded'] == true
                                  ? PrismTone.danger
                                  : PrismTone.success;
                              final suffix = h == null
                                  ? ' ($count)'
                                  : ' (${h['healthy'] ?? 0}/${h['total'] ?? count})';
                              return PrismBadge(
                                label: '$vgName$suffix',
                                glyph: AntGlyphs.hub,
                                tone: tone,
                                onPressed: () =>
                                    _inspectVirtualGroupMembers(vg),
                              );
                            },
                          ),
                      ],
                      if (hasAnyFilter)
                        prism.TextButton(
                          onPressed: _clearFilters,
                          child: const Text('清除筛选'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProxyRow(BuildContext context, Map<String, dynamic> item) {
    final id = (item['proxyId'] ?? '').toString();
    final isSelectable = id.isNotEmpty && id != '__direct__';
    final isDirect = item['proxyConfig'] == 'direct://';
    final speed = _speedResults[id];
    final health = _ipHealthResults[id];
    final sourceId = (item['sourceId'] ?? '').toString();
    final sourceHost = _subscriptionHost((item['sourceUrl'] ?? '').toString());
    final (latencyLabel, latencyTone) = _latencyBadgeInfo(item);
    final engine = (speed?['engine'] ?? item['lastTestEngine'] ?? '')
        .toString()
        .trim();
    final ipSummary = _formatIpHealthSummary(health);
    final ipAddr = health != null && health['ok'] == true
        ? (health['ip'] ?? '').toString().trim()
        : '';
    final kernelPref = _normalizeKernel(item['preferredKernel']);
    final endpoint = _proxyEndpointSummary(item);
    final groupName = (item['groupName'] ?? '').toString().trim();

    return PrismCard(
      margin: EdgeInsets.zero,
      child: PrismListTile(
        leading: isSelectable
            ? prism.Checkbox(
                value: _selectedIds.contains(id),
                onChanged: _busy.isEmpty
                    ? (value) => setState(() {
                        if (value == true) {
                          _selectedIds.add(id);
                        } else {
                          _selectedIds.remove(id);
                        }
                      })
                    : null,
              )
            : const PrismGlyph(AntGlyphs.shield, size: 18),
        title: Row(
          children: [
            Expanded(
              child: Text(
                (item['proxyName'] ?? id).toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: prism.AppTextStyle.subheadline.of(
                  context,
                  emphasized: true,
                ),
              ),
            ),
            if (groupName.isNotEmpty) ...[
              const SizedBox(width: 12),
              PrismBadge(label: groupName, tone: PrismTone.neutral),
            ],
            if (kernelPref != 'auto') ...[
              const SizedBox(width: 12),
              PrismBadge(
                label: _kernelLabels[kernelPref] ?? kernelPref,
                tone: PrismTone.primary,
              ),
            ],
            if (item['sourceMissing'] == true) ...[
              const SizedBox(width: 12),
              const PrismBadge(label: '订阅异常', tone: PrismTone.danger),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PrismBadge(
                label: _proxyProtocol(item).toUpperCase(),
                tone: PrismTone.neutral,
              ),
              Text(
                endpoint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: prism.AppTextStyle.caption1
                    .of(context)
                    .copyWith(
                      color: prism.Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              PrismBadge(
                label: engine.isEmpty
                    ? latencyLabel
                    : '$latencyLabel · $engine',
                tone: latencyTone,
                dot: true,
              ),
              if (ipAddr.isNotEmpty || ipSummary.isNotEmpty)
                PrismBadge(
                  label: [
                    if (ipAddr.isNotEmpty) ipAddr,
                    if (ipSummary.isNotEmpty) ipSummary,
                  ].join(' · '),
                  tone: health?['ok'] == true
                      ? PrismTone.info
                      : PrismTone.danger,
                  onPressed: () => _showIPHealthDetail(item),
                ),
              if (_globalCustomDns.isNotEmpty)
                prism.Tooltip(
                  message: '全局自定义桥接 DNS，覆盖所有节点',
                  child: const PrismBadge(
                    label: 'DNS: 自定义',
                    tone: PrismTone.info,
                  ),
                )
              else if ((item['dnsServers'] ?? '').toString().trim().isNotEmpty)
                prism.Tooltip(
                  message: '节点 DNS 来自订阅或手动填写；订阅刷新会同步',
                  child: const PrismBadge(
                    label: 'DNS: 节点',
                    tone: PrismTone.neutral,
                  ),
                ),
              if (sourceHost.isNotEmpty)
                PrismBadge(
                  label:
                      '$sourceHost · ${item['sourceAutoRefresh'] == true ? '自动' : '手动'}',
                  glyph: AntGlyphs.link,
                  tone: PrismTone.neutral,
                ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            prism.TonalButtonGroup(
              size: prism.TonalButtonSize.section,
              children: [
                prism.IconButton(
                  tooltip: '检查代理 IP',
                  onPressed: _busy.isEmpty ? () => _testIpHealth(item) : null,
                  icon: const PrismGlyph(AntGlyphs.globe, size: 18),
                ),
                prism.IconButton(
                  tooltip: '测试连接',
                  onPressed: _busy.isEmpty && !isDirect
                      ? () => _test(item)
                      : null,
                  icon: _busy == id || _testingIds.contains(id)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: PrismProgressIndicator(size: 18),
                        )
                      : const PrismGlyph(AntGlyphs.speed, size: 18),
                ),
                prism.IconButton(
                  tooltip: '桥接预热',
                  onPressed: _busy.isEmpty && !isDirect
                      ? () => _warmupBridge(item)
                      : null,
                  icon: _busy == 'batch-warmup'
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: PrismProgressIndicator(size: 18),
                        )
                      : const PrismGlyph(AntGlyphs.fire, size: 18),
                ),
              ],
            ),
            const SizedBox(width: 8),
            PrismPopupMenuButton<String>(
              tooltip: '更多操作',
              enabled: _busy.isEmpty,
              icon: const PrismGlyph(AntGlyphs.more, size: 18),
              itemBuilder: (_) => [
                if (sourceId.isNotEmpty)
                  const PrismMenuItem(value: 'refresh', child: Text('刷新订阅')),
                if (health != null)
                  const PrismMenuItem(
                    value: 'ip-detail',
                    child: Text('查看 IP 检测详情'),
                  ),
                PrismMenuItem(
                  value: 'edit',
                  child: const Text('编辑'),
                  enabled: isSelectable,
                ),
                const PrismMenuItem(value: 'ip-health', child: Text('IP 健康')),
                PrismMenuItem(
                  value: 'delete',
                  child: const Text('删除'),
                  danger: true,
                  enabled: isSelectable,
                ),
              ],
              onSelected: (action) {
                if (action == 'refresh') {
                  _refreshSource(item);
                } else if (action == 'ip-detail') {
                  _showIPHealthDetail(item);
                } else if (action == 'ip-health') {
                  _testIpHealth(item);
                } else if (action == 'edit') {
                  _edit(item);
                } else if (action == 'delete') {
                  _delete(item);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyListSection(
    BuildContext context, {
    required List<Map<String, dynamic>> visible,
    required List<Map<String, dynamic>> selectable,
    required bool allFilteredSelected,
  }) {
    final busyLabel = switch (_busy) {
      'batch-speed' => '批量测速中…',
      'batch-ip' => 'IP 健康检测中…',
      'batch-warmup' => '桥接预热中…',
      'refresh-all' => '刷新订阅中…',
      _ => '',
    };

    return PrismHoverCard(
      staggerIndex: 5,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          prism.InfoHeader(
            info: const prism.Info(label: '代理节点', glyph: AntGlyphs.globe),
            actions: [
              if (busyLabel.isNotEmpty)
                PrismBadge(label: busyLabel, tone: PrismTone.info, dot: true),
              if (selectable.isNotEmpty)
                prism.TextButton(
                  onPressed: () => setState(() {
                    if (allFilteredSelected) {
                      _selectedIds.removeAll(
                        selectable.map((item) => item['proxyId'].toString()),
                      );
                    } else {
                      _selectedIds.addAll(
                        selectable.map((item) => item['proxyId'].toString()),
                      );
                    }
                  }),
                  child: Text(
                    allFilteredSelected
                        ? '取消全选'
                        : '全选当前 (${selectable.length})',
                  ),
                ),
              if (_selectedIds.isNotEmpty)
                PrismTonalButton.icon(
                  onPressed: _busy.isEmpty ? _deleteSelected : null,
                  icon: const PrismGlyph(AntGlyphs.delete, size: 15),
                  child: Text('删除所选 (${_selectedIds.length})'),
                ),
              PrismBadge(
                label: '${visible.length} 个',
                tone: visible.isEmpty ? PrismTone.neutral : PrismTone.primary,
              ),
            ],
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
          ),
          const prism.Divider(height: 1),
          Expanded(
            child: prism.PageTransitionSwitcher(
              duration: PrismMotionSpec.current.pageDuration,
              transitionBuilder: PrismSlideThroughTransition.builder,
              child: KeyedSubtree(
                key: ValueKey(
                  '$_filterProtocol-$_filterGroup-$_availableOnly-$_sortBy-$_sortDescending-$_query-$_loading-${_error != null}-${visible.isEmpty}',
                ),
                child: _loading
                    ? const Center(child: PrismProgressIndicator())
                    : _error != null
                    ? PrismEmptyState(
                        title: '加载代理池失败',
                        subtitle: _error!,
                        glyph: AntGlyphs.error,
                        action: PrismHoverMotion(
                          child: prism.FilledButton(
                            onPressed: _refresh,
                            child: const Text('重试'),
                          ),
                        ),
                      )
                    : visible.isEmpty
                    ? PrismEmptyState(
                        title: '没有匹配的代理',
                        subtitle: _proxies.length <= 1
                            ? '点击右上角“添加代理”或“导入订阅”开始构建代理池。'
                            : '当前筛选条件下没有结果，尝试清除筛选条件。',
                        glyph: AntGlyphs.globe,
                        action:
                            _query.isNotEmpty ||
                                _filterProtocol != 'all' ||
                                _filterGroup != 'all' ||
                                _availableOnly
                            ? prism.OutlinedButton(
                                onPressed: _clearFilters,
                                child: const Text('清除筛选'),
                              )
                            : PrismHoverMotion(
                                child: prism.FilledButton.icon(
                                  onPressed: () => _edit(),
                                  icon: const PrismGlyph(
                                    AntGlyphs.add,
                                    size: 16,
                                  ),
                                  label: const Text('添加代理'),
                                ),
                              ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: ListView.separated(
                          padding: kPrismListPadding,
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) =>
                              _buildProxyRow(context, visible[index]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final protocols =
        _proxies
            .map(_proxyProtocol)
            .where((protocol) => protocol != '-')
            .toSet()
            .toList()
          ..sort();
    final groups = _allGroupSuggestions;
    Map<String, dynamic>? selectedVirtualGroup;
    for (final group in _virtualGroups) {
      if (_virtualGroupFilterKey(group) == _filterGroup) {
        selectedVirtualGroup = group;
        break;
      }
    }
    final virtualMemberIds = Set<String>.from(
      (selectedVirtualGroup?['memberProxyIds'] as List? ?? []).map(
        (id) => id.toString().trim().toLowerCase(),
      ),
    );
    final virtualMemberGroups = Set<String>.from(
      (selectedVirtualGroup?['memberGroupNames'] as List? ?? []).map(
        (name) => name.toString().trim().toLowerCase(),
      ),
    );
    final visible = _proxies.where((item) {
      final text = [
        item['proxyName'],
        item['proxyConfig'],
        item['groupName'],
        _proxyServer(item),
      ].join(' ').toLowerCase();
      final id = (item['proxyId'] ?? '').toString().trim().toLowerCase();
      final groupName = (item['groupName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final groupMatches = selectedVirtualGroup != null
          ? item['proxyConfig'] != 'direct://' &&
                (virtualMemberIds.contains(id) ||
                    virtualMemberGroups.contains(groupName))
          : _filterGroup == 'all' ||
                (item['groupName'] ?? '').toString() == _filterGroup;
      return text.contains(_query.toLowerCase()) &&
          (_filterProtocol == 'all' ||
              _proxyProtocol(item) == _filterProtocol) &&
          groupMatches &&
          (!_availableOnly || _isAvailable(item));
    }).toList();

    int latency(Map<String, dynamic> proxy) {
      final id = (proxy['proxyId'] ?? '').toString();
      final result = _speedResults[id];
      if (result == null || result['ok'] != true) return 1 << 60;
      return int.tryParse(
            (result['latencyMs'] ?? proxy['lastLatencyMs'] ?? 0).toString(),
          ) ??
          (1 << 60);
    }

    if (_sortBy.isNotEmpty) {
      visible.sort((a, b) {
        final comparison = switch (_sortBy) {
          'name' => (a['proxyName'] ?? '').toString().compareTo(
            (b['proxyName'] ?? '').toString(),
          ),
          'group' => (a['groupName'] ?? '').toString().compareTo(
            (b['groupName'] ?? '').toString(),
          ),
          'protocol' => _proxyProtocol(a).compareTo(_proxyProtocol(b)),
          'server' => _proxyServer(a).compareTo(_proxyServer(b)),
          'port' => _proxyPort(a).compareTo(_proxyPort(b)),
          'latency' => latency(a).compareTo(latency(b)),
          _ => 0,
        };
        return _sortDescending ? -comparison : comparison;
      });
    }
    final selectable = visible
        .where((item) => (item['proxyId'] ?? '').toString() != '__direct__')
        .toList();
    final allFilteredSelected =
        selectable.isNotEmpty &&
        selectable.every(
          (item) => _selectedIds.contains(item['proxyId'].toString()),
        );
    final hasSources = _proxies.any(
      (proxy) =>
          (proxy['sourceId'] ?? '').toString().isNotEmpty &&
          (proxy['sourceUrl'] ?? '').toString().isNotEmpty,
    );
    final hasMieruProxies = _proxies.any(_isMieruProxy);
    final mieruInstalled = _coreStatuses['mieru']?['installed'] == true;
    final showMieruBanner =
        hasMieruProxies &&
        _coreStatuses.containsKey('mieru') &&
        !mieruInstalled &&
        !_dismissedMieruBanner;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewStrip(context, hasSources: hasSources),
          const SizedBox(height: 16),
          _buildToolbar(
            context,
            protocols: protocols,
            groups: groups,
            visible: visible,
            hasSources: hasSources,
          ),
          if (showMieruBanner) ...[
            const SizedBox(height: 16),
            PrismBanner(
              tone: PrismTone.warning,
              title: '检测到 mieru 代理节点，但尚未安装 mieru 内核',
              message: '下载并安装 mieru 内核后即可正常测速和启动使用 mieru 代理的浏览器实例。',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  prism.FilledButton(
                    onPressed: () =>
                        _openProxyCoreDownload(initialCore: 'mieru'),
                    child: const Text('下载 mieru 内核'),
                  ),
                  const SizedBox(width: 6),
                  prism.IconButton(
                    tooltip: '忽略提示',
                    onPressed: () =>
                        setState(() => _dismissedMieruBanner = true),
                    icon: const PrismGlyph(AntGlyphs.close, size: 16),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _buildProxyListSection(
              context,
              visible: visible,
              selectable: selectable,
              allFilteredSelected: allFilteredSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxySourceRefreshModal extends StatefulWidget {
  const _ProxySourceRefreshModal({
    required this.proxies,
    required this.usableProxies,
    required this.speedResults,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> proxies;
  final List<Map<String, dynamic>> usableProxies;
  final Map<String, Map<String, dynamic>> speedResults;
  final Future<void> Function() onChanged;

  @override
  State<_ProxySourceRefreshModal> createState() =>
      _ProxySourceRefreshModalState();
}

class _ProxySourceRefreshModalState extends State<_ProxySourceRefreshModal> {
  late List<Map<String, dynamic>> _proxies;
  String _busy = '';
  String? _editingSourceId;
  bool _editAutoRefresh = false;
  final TextEditingController _editInterval = TextEditingController();
  String _editFetchProxyId = '';

  @override
  void initState() {
    super.initState();
    _proxies = List<Map<String, dynamic>>.from(widget.proxies);
  }

  @override
  void dispose() {
    _editInterval.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _sources {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final proxy in _proxies) {
      final id = (proxy['sourceId'] ?? '').toString().trim();
      final url = (proxy['sourceUrl'] ?? '').toString().trim();
      if (id.isNotEmpty && url.isNotEmpty) {
        grouped.putIfAbsent(id, () => []).add(proxy);
      }
    }
    return grouped.entries.map((entry) {
      final items = entry.value;
      final first = items.first;
      final abnormal = items.where((p) => p['sourceMissing'] == true).toList();
      final lastError = items
          .map((p) => (p['sourceLastRefreshError'] ?? '').toString().trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      return {
        'sourceId': entry.key,
        'sourceUrl': (first['sourceUrl'] ?? '').toString(),
        'host': _subscriptionHost((first['sourceUrl'] ?? '').toString()),
        'prefix': (first['sourceNamePrefix'] ?? '').toString().trim(),
        'groupName': (first['groupName'] ?? '').toString().trim(),
        'autoRefresh': first['sourceAutoRefresh'] == true,
        'intervalM':
            int.tryParse('${first['sourceRefreshIntervalM'] ?? 0}') ?? 0,
        'fetchProxyId': (first['sourceFetchProxyId'] ?? '').toString(),
        'lastRefreshAt': (first['sourceLastRefreshAt'] ?? '').toString(),
        'lastRefreshError': lastError,
        'totalCount': items.length,
        'abnormalNodes': abnormal,
      };
    }).toList();
  }

  Future<void> _reloadLocal() async {
    await widget.onChanged();
    try {
      final raw = await AppBridge.call('BrowserProxyList');
      if (mounted) {
        setState(() {
          _proxies = (raw as List? ?? [])
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
        });
      }
    } catch (_) {}
  }

  void _beginEdit(Map<String, dynamic> source) {
    setState(() {
      _editingSourceId = source['sourceId'].toString();
      _editAutoRefresh = source['autoRefresh'] == true;
      final intervalM = (source['intervalM'] as int? ?? 0);
      _editInterval.text = '${intervalM > 0 ? intervalM : 1440}';
      _editFetchProxyId = (source['fetchProxyId'] ?? '').toString();
    });
  }

  Future<void> _saveEdit(String sourceId) async {
    setState(() => _busy = 'save:$sourceId');
    try {
      final intervalM = _editAutoRefresh
          ? (int.tryParse(_editInterval.text) ?? 1440).clamp(5, 1440)
          : 0;
      await AppBridge.call('BrowserProxyUpdateSourceConfig', [
        sourceId,
        _editAutoRefresh,
        intervalM,
        _editFetchProxyId,
      ]);
      _editingSourceId = null;
      await _reloadLocal();
      if (mounted) showPrismNotice(context, '订阅源更新配置已保存');
    } catch (error) {
      if (mounted) showPrismNotice(context, '保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _refreshOne(Map<String, dynamic> source) async {
    final id = source['sourceId'].toString();
    setState(() => _busy = id);
    try {
      await AppBridge.call('BrowserProxyRefreshSource', [
        id,
        source['fetchProxyId'] ?? '',
      ]);
      await _reloadLocal();
      if (mounted) showPrismNotice(context, '订阅已刷新');
    } catch (error) {
      if (mounted) showPrismNotice(context, '刷新失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _refreshAll() async {
    final sources = _sources;
    if (sources.isEmpty) return;
    setState(() => _busy = 'all');
    var ok = 0;
    var fail = 0;
    try {
      for (final source in sources) {
        try {
          await AppBridge.call('BrowserProxyRefreshSource', [
            source['sourceId'],
            source['fetchProxyId'] ?? '',
          ]);
          ok++;
        } catch (_) {
          fail++;
        }
      }
      await _reloadLocal();
      if (mounted) {
        showPrismNotice(
          context,
          fail == 0 ? '已刷新全部 $ok 个订阅源' : '刷新完成：$ok 成功，$fail 失败',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _openAbnormalModal(Map<String, dynamic> source) async {
    final nodes = List<Map<String, dynamic>>.from(
      source['abnormalNodes'] as List,
    );
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _ProxySourceAbnormalModal(
        sourceId: source['sourceId'].toString(),
        sourceLabel: (source['host'] ?? source['sourceId']).toString(),
        abnormalNodes: nodes,
        onCleaned: _reloadLocal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    final colors = prism.Theme.of(context).colorScheme;
    return PrismDialog(
      title: const Text('订阅更新管理'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: sources.isEmpty
            ? const PrismEmptyState(
                title: '暂无 URL 订阅源',
                subtitle: '通过“导入订阅”添加远程订阅链接后，可在此集中管理刷新策略与异常节点。',
                glyph: AntGlyphs.link,
              )
            : ListView.separated(
                padding: kPrismListPadding,
                itemCount: sources.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  final sourceId = source['sourceId'].toString();
                  final host = (source['host'] ?? sourceId).toString();
                  final prefix = (source['prefix'] ?? '').toString();
                  final groupName = (source['groupName'] ?? '').toString();
                  final total = source['totalCount'] as int;
                  final abnormal =
                      source['abnormalNodes'] as List<Map<String, dynamic>>;
                  final autoRefresh = source['autoRefresh'] == true;
                  final intervalM = source['intervalM'] as int;
                  final lastAt = (source['lastRefreshAt'] ?? '').toString();
                  final lastError = (source['lastRefreshError'] ?? '')
                      .toString();
                  final isEditing = _editingSourceId == sourceId;
                  return PrismSectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    host,
                                    style: prism.AppTextStyle.subheadline.of(
                                      context,
                                      emphasized: true,
                                    ),
                                  ),
                                  if (groupName.isNotEmpty)
                                    PrismBadge(
                                      label: '分组：$groupName',
                                      tone: PrismTone.neutral,
                                    ),
                                  if (prefix.isNotEmpty)
                                    PrismBadge(
                                      label: '前缀：$prefix',
                                      tone: PrismTone.neutral,
                                    ),
                                  PrismBadge(
                                    label: '$total 节点',
                                    tone: PrismTone.primary,
                                  ),
                                  if (abnormal.isNotEmpty)
                                    PrismBadge(
                                      label: '异常 ${abnormal.length}',
                                      tone: PrismTone.danger,
                                      onPressed: () =>
                                          _openAbnormalModal(source),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            prism.IconButton(
                              tooltip: '编辑刷新配置',
                              onPressed: _busy.isEmpty
                                  ? () => isEditing
                                        ? setState(
                                            () => _editingSourceId = null,
                                          )
                                        : _beginEdit(source)
                                  : null,
                              icon: PrismGlyph(
                                isEditing ? AntGlyphs.close : AntGlyphs.edit,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            prism.OutlinedButton.icon(
                              onPressed: _busy.isEmpty
                                  ? () => _refreshOne(source)
                                  : null,
                              icon: _busy == sourceId
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: PrismProgressIndicator(size: 14),
                                    )
                                  : const PrismGlyph(AntGlyphs.sync, size: 15),
                              label: const Text('立即刷新'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            PrismBadge(
                              label: autoRefresh
                                  ? '自动刷新 · 每 $intervalM 分钟 · ${_formatNextRefreshCountdown(lastAt, intervalM)}'
                                  : '手动刷新',
                              glyph: AntGlyphs.schedule,
                              tone: autoRefresh
                                  ? PrismTone.info
                                  : PrismTone.neutral,
                            ),
                            if (lastError.isNotEmpty)
                              const PrismBadge(
                                label: '上次刷新失败',
                                tone: PrismTone.danger,
                              )
                            else
                              Text(
                                '上次刷新：${_formatShortTime(lastAt)}',
                                style: prism.AppTextStyle.caption1
                                    .of(context)
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                          ],
                        ),
                        if (lastError.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          PrismBanner(
                            tone: PrismTone.danger,
                            message: lastError,
                          ),
                        ],
                        if (isEditing) ...[
                          const SizedBox(height: 14),
                          const prism.Divider(height: 1),
                          const SizedBox(height: 14),
                          PrismSwitchTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('启用自动刷新'),
                            value: _editAutoRefresh,
                            onChanged: (value) =>
                                setState(() => _editAutoRefresh = value),
                          ),
                          if (_editAutoRefresh) ...[
                            const SizedBox(height: 10),
                            PrismTextField(
                              controller: _editInterval,
                              keyboardType: TextInputType.number,
                              decoration: const PrismInputDecoration(
                                labelText: '刷新间隔（分钟，5–1440）',
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          PrismDropdownField<String>(
                            value: _editFetchProxyId,
                            decoration: const PrismInputDecoration(
                              labelText: '拉取订阅使用的代理',
                            ),
                            items: [
                              const PrismDropdownItem(
                                value: '',
                                child: Text('直连'),
                              ),
                              if (_editFetchProxyId.isNotEmpty &&
                                  !widget.usableProxies.any(
                                    (p) =>
                                        (p['proxyId'] ?? '').toString() ==
                                        _editFetchProxyId,
                                  ))
                                PrismDropdownItem(
                                  value: _editFetchProxyId,
                                  child: Text('当前代理（$_editFetchProxyId）'),
                                ),
                              for (final p in widget.usableProxies)
                                PrismDropdownItem(
                                  value: (p['proxyId'] ?? '').toString(),
                                  child: Text(
                                    '${p['proxyName'] ?? '未命名代理'} (${widget.speedResults[(p['proxyId'] ?? '').toString()]?['latencyMs'] ?? 0}ms)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _editFetchProxyId = value ?? ''),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              prism.TextButton(
                                onPressed: () =>
                                    setState(() => _editingSourceId = null),
                                child: const Text('取消'),
                              ),
                              const SizedBox(width: 8),
                              prism.FilledButton(
                                onPressed: _busy.isEmpty
                                    ? () => _saveEdit(sourceId)
                                    : null,
                                child: Text(
                                  _busy == 'save:$sourceId' ? '保存中…' : '保存配置',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        prism.TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (sources.isNotEmpty)
          prism.FilledButton.icon(
            onPressed: _busy.isEmpty ? _refreshAll : null,
            icon: _busy == 'all'
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: PrismProgressIndicator(size: 14),
                  )
                : const PrismGlyph(AntGlyphs.sync, size: 15),
            label: Text(_busy == 'all' ? '全部刷新中…' : '全部刷新'),
          ),
      ],
    );
  }
}

class _ProxySourceAbnormalModal extends StatefulWidget {
  const _ProxySourceAbnormalModal({
    required this.sourceId,
    required this.sourceLabel,
    required this.abnormalNodes,
    required this.onCleaned,
  });

  final String sourceId;
  final String sourceLabel;
  final List<Map<String, dynamic>> abnormalNodes;
  final Future<void> Function() onCleaned;

  @override
  State<_ProxySourceAbnormalModal> createState() =>
      _ProxySourceAbnormalModalState();
}

class _ProxySourceAbnormalModalState extends State<_ProxySourceAbnormalModal> {
  bool _cleaning = false;

  Future<void> _cleanupThisSource() async {
    setState(() => _cleaning = true);
    try {
      final result = Map<String, dynamic>.from(
        await AppBridge.call('BrowserProxyCleanupMissing', [
          widget.sourceId,
          false,
        ]) as Map,
      );
      await widget.onCleaned();
      final deleted = int.tryParse('${result['deleted'] ?? 0}') ?? 0;
      final skipped = (result['skipped'] as List? ?? []).length;
      if (mounted) {
        showPrismNotice(
          context,
          skipped == 0
              ? '已清理 $deleted 个异常节点'
              : '已清理 $deleted 个，$skipped 个仍被引用已保留',
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '清理失败：$error');
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PrismDialog(
      title: Text('异常节点 · ${widget.sourceLabel}'),
      content: SizedBox(
        width: 600,
        height: 420,
        child: widget.abnormalNodes.isEmpty
            ? const PrismEmptyState(
                title: '没有异常节点',
                glyph: AntGlyphs.checkCircle,
              )
            : ListView.separated(
                padding: kPrismListPadding,
                itemCount: widget.abnormalNodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final node = widget.abnormalNodes[index];
                  final missingSince = _formatShortTime(
                    (node['sourceMissingSince'] ?? '').toString(),
                  );
                  return PrismCard(
                    margin: EdgeInsets.zero,
                    child: PrismListTile(
                      dense: true,
                      leading: PrismGlyph(
                        AntGlyphs.warning,
                        size: 18,
                        color: PrismToneColors.of(context, PrismTone.danger).fg,
                      ),
                      title: Text(
                        (node['proxyName'] ?? node['proxyId'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_proxyProtocol(node).toUpperCase()} · ${_proxyEndpointSummary(node)} · 异常自 $missingSince',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const PrismBadge(
                        label: '订阅缺失',
                        tone: PrismTone.danger,
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        prism.TextButton(
          onPressed: _cleaning ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (widget.abnormalNodes.isNotEmpty)
          prism.FilledButton.icon(
            onPressed: _cleaning ? null : _cleanupThisSource,
            icon: const PrismGlyph(AntGlyphs.deleteSweep, size: 15),
            label: Text(_cleaning ? '清理中…' : '清理未引用异常节点'),
          ),
      ],
    );
  }
}

class _ProxyUsageGuideDialog extends StatefulWidget {
  const _ProxyUsageGuideDialog();

  @override
  State<_ProxyUsageGuideDialog> createState() => _ProxyUsageGuideDialogState();
}

class _ProxyUsageGuideDialogState extends State<_ProxyUsageGuideDialog> {
  String _tab = 'ipfly';

  static const _clashExample = '''proxies:
  - name: hk-vless
    type: vless
    server: example.com
    port: 443
    uuid: your-uuid
    network: ws
    tls: true
    servername: example.com''';
  static const _proxyExample = '''http://user:password@gateway.example.com:8080
https://user:password@gateway.example.com:8443
socks5://user:password@proxy.example.com:6616''';
  static const _chainExample = '''{
  "name": "IPFLY-落地",
  "first": {
    "protocol": "socks5",
    "server": "127.0.0.1",
    "port": "7890"
  },
  "second": {
    "protocol": "socks5",
    "server": "gateway.example.com",
    "port": "6616",
    "username": "账号",
    "password": "密码"
  }
}''';

  @override
  Widget build(BuildContext context) => PrismDialog(
    title: const Text('代理池使用说明'),
    content: SizedBox(
      width: 880,
      height: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tab 切换走 SegmentedControl（全站统一分段控件），不再手搓按钮组。
          prism.SegmentedControl<String>(
            value: _tab,
            onChanged: (value) => setState(() => _tab = value),
            segments: const [
              ('clash', 'Clash 订阅 / YAML'),
              ('direct', 'HTTP / SOCKS5'),
              ('ipfly', '链式代理'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (_tab == 'clash') ...[
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('导入订阅或 YAML'),
                      subtitle: Text(
                        '输入订阅 URL 获取内容，或粘贴 YAML。内容需要包含 proxies 节点列表；解析后先检查名称和数量，再确认导入。',
                      ),
                    ),
                  ),
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('拉取失败或解析为空'),
                      subtitle: Text(
                        '订阅无法直连时，在导入界面选择拉取代理。解析为空时检查 YAML 缩进、proxies 拼写及每个节点的 name、type、server、port。',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const PrismCodeSurface(language: 'yaml', code: _clashExample),
                ],
                if (_tab == 'direct') ...[
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('手动添加'),
                      subtitle: Text(
                        '表单地址只填域名或 IP，不要带协议头。HTTP、HTTPS 和 SOCKS5 均可用；有密码时同时填写账号。',
                      ),
                    ),
                  ),
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('批量导入'),
                      subtitle: Text(
                        '一行一个代理地址。地址格式为“协议://账号:密码@服务器:端口”，也可以在导入界面粘贴 JSON。',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const PrismCodeSurface(language: 'text', code: _proxyExample),
                ],
                if (_tab == 'ipfly') ...[
                  const PrismCard(
                    child: PrismListTile(
                      title: Text('链式代理'),
                      subtitle: Text(
                        'first 填本机的 VPN 或前置代理，second 填 IPFLY 等落地代理。前置代理需先运行，端口和账号信息要与实际配置一致。',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const PrismCodeSurface(language: 'json', code: _chainExample),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      prism.TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  );
}

class _ProxyCoreDownloadDialog extends StatefulWidget {
  const _ProxyCoreDownloadDialog({
    this.initialCore,
    this.usableProxies = const [],
    this.speedResults = const {},
  });

  final String? initialCore;
  final List<Map<String, dynamic>> usableProxies;
  final Map<String, Map<String, dynamic>> speedResults;

  @override
  State<_ProxyCoreDownloadDialog> createState() =>
      _ProxyCoreDownloadDialogState();
}

class _ProxyCoreDownloadDialogState extends State<_ProxyCoreDownloadDialog> {
  final _proxyConfig = TextEditingController();
  late String _core;
  late String _goos;
  late String _goarch;
  String _selectedProxyPreset = '';
  bool _loadingStatus = true;
  bool _loadingInfo = false;
  bool _starting = false;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _downloadInfo;
  late final void Function() _removeProgressListener;

  bool get _downloading =>
      _starting ||
      (_progress != null &&
          !{'done', 'error'}.contains(_progress!['phase']?.toString()));

  Map<String, Object?> get _request => {
    'core': _core,
    'goos': _goos,
    'goarch': _goarch,
    'proxyConfig': _proxyConfig.text.trim(),
  };

  @override
  void initState() {
    super.initState();
    const validCores = {'xray', 'mihomo', 'sing-box', 'mieru'};
    final initial = (widget.initialCore ?? '').trim().toLowerCase();
    _core = validCores.contains(initial) ? initial : 'xray';
    _goos = _hostGoos();
    _goarch = _hostGoarch();
    _removeProgressListener = AppBridge.onEvent(
      'proxy-core:download:progress',
      _onProgress,
    );
    _refreshStatus();
  }

  @override
  void dispose() {
    _removeProgressListener();
    _proxyConfig.dispose();
    super.dispose();
  }

  void _onProgress(dynamic value) {
    if (!mounted || value is! Map) return;
    final progress = Map<String, dynamic>.from(value);
    if (progress['core'] != _core ||
        progress['goos'] != _goos ||
        progress['goarch'] != _goarch) {
      return;
    }
    setState(() => _progress = progress);
    if (progress['phase'] == 'done') unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    if (mounted) setState(() => _loadingStatus = true);
    try {
      final result = await AppBridge.call('BrowserProxyCoreStatus', [_request]);
      if (mounted) {
        setState(() => _status = Map<String, dynamic>.from(result as Map));
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '读取代理内核状态失败：$error');
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  void _changeTarget({String? core, String? goos, String? goarch}) {
    setState(() {
      _core = core ?? _core;
      _goos = goos ?? _goos;
      _goarch = goarch ?? _goarch;
      _progress = null;
      _downloadInfo = null;
    });
    _refreshStatus();
  }

  Future<void> _startDownload() async {
    if (_downloading) return;
    setState(() {
      _starting = true;
      _progress = {'phase': 'starting', 'progress': 0, 'message': '正在准备下载…'};
    });
    try {
      await AppBridge.call('BrowserProxyCoreDownload', [_request]);
    } catch (error) {
      if (mounted) {
        setState(() {
          _progress = {
            'phase': 'error',
            'progress': 0,
            'message': error.toString(),
          };
        });
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openRemoteDownload() async {
    setState(() => _loadingInfo = true);
    try {
      final result = await AppBridge.call('BrowserProxyCoreDownloadInfo', [
        _request,
      ]);
      final info = Map<String, dynamic>.from(result as Map);
      if (mounted) setState(() => _downloadInfo = info);
      final url = (info['downloadUrl'] ?? info['releaseUrl'] ?? '')
          .toString()
          .trim();
      if (url.isEmpty) {
        if (mounted) {
          showPrismNotice(
            context,
            (info['message'] ?? '没有可打开的下载地址').toString(),
          );
        }
      } else {
        AppBridge.openExternal(url);
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, '获取下载地址失败：$error');
    } finally {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  Future<void> _openLocalDirectory() async {
    try {
      await AppBridge.call('BrowserProxyCoreOpenLocal', [_request]);
    } catch (error) {
      if (mounted) showPrismNotice(context, '打开代理内核目录失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = _status?['installed'] == true;
    final progressValue = _progress == null
        ? null
        : ((num.tryParse('${_progress!['progress'] ?? 0}') ?? 0) / 100.0).clamp(
            0.0,
            1.0,
          );
    return PrismDialog(
      title: const Text('代理内核下载与管理'),
      content: SizedBox(
        width: 580,
        height: 540,
        child: SingleChildScrollView(
          padding: kPrismScrollPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismDropdownField<String>(
                key: ValueKey(_core),
                value: _core,
                decoration: const PrismInputDecoration(labelText: '代理内核'),
                items: const [
                  PrismDropdownItem(value: 'xray', child: Text('Xray')),
                  PrismDropdownItem(value: 'mihomo', child: Text('Mihomo')),
                  PrismDropdownItem(value: 'sing-box', child: Text('sing-box')),
                  PrismDropdownItem(value: 'mieru', child: Text('mieru')),
                ],
                onChanged: _downloading
                    ? null
                    : (value) {
                        if (value != null) _changeTarget(core: value);
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PrismDropdownField<String>(
                      key: ValueKey(_goos),
                      value: _goos,
                      decoration: const PrismInputDecoration(labelText: '目标系统'),
                      items: const [
                        PrismDropdownItem(
                          value: 'windows',
                          child: Text('Windows'),
                        ),
                        PrismDropdownItem(value: 'linux', child: Text('Linux')),
                        PrismDropdownItem(
                          value: 'darwin',
                          child: Text('macOS'),
                        ),
                      ],
                      onChanged: _downloading
                          ? null
                          : (value) {
                              if (value != null) _changeTarget(goos: value);
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrismDropdownField<String>(
                      key: ValueKey(_goarch),
                      value: _goarch,
                      decoration: const PrismInputDecoration(labelText: '目标架构'),
                      items: const [
                        PrismDropdownItem(
                          value: 'amd64',
                          child: Text('amd64 / x64'),
                        ),
                        PrismDropdownItem(value: 'arm64', child: Text('arm64')),
                        PrismDropdownItem(
                          value: '386',
                          child: Text('386 / x86'),
                        ),
                      ],
                      onChanged: _downloading
                          ? null
                          : (value) {
                              if (value != null) _changeTarget(goarch: value);
                            },
                    ),
                  ),
                ],
              ),
              if (widget.usableProxies.isNotEmpty) ...[
                const SizedBox(height: 12),
                PrismDropdownField<String>(
                  value: _selectedProxyPreset,
                  decoration: const PrismInputDecoration(
                    labelText: '快速选择可用代理（测速通过）',
                  ),
                  items: [
                    const PrismDropdownItem(
                      value: '',
                      child: Text('直连 / 手动填写'),
                    ),
                    for (final proxy in widget.usableProxies)
                      PrismDropdownItem(
                        value: (proxy['proxyId'] ?? '').toString(),
                        child: Text(
                          '${proxy['proxyName'] ?? '未命名代理'} (${widget.speedResults[(proxy['proxyId'] ?? '').toString()]?['latencyMs'] ?? 0}ms)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _downloading
                      ? null
                      : (value) {
                          setState(() {
                            _selectedProxyPreset = value ?? '';
                            if (_selectedProxyPreset.isEmpty) {
                              _proxyConfig.clear();
                            } else {
                              final matched = widget.usableProxies
                                  .where(
                                    (p) =>
                                        (p['proxyId'] ?? '').toString() ==
                                        _selectedProxyPreset,
                                  )
                                  .firstOrNull;
                              if (matched != null) {
                                _proxyConfig.text =
                                    (matched['proxyConfig'] ?? '').toString();
                              }
                            }
                          });
                        },
                ),
              ],
              const SizedBox(height: 12),
              PrismTextField(
                controller: _proxyConfig,
                enabled: !_downloading,
                decoration: const PrismInputDecoration(
                  labelText: '下载代理配置（可选）',
                  hintText: '例如 http://127.0.0.1:7890',
                ),
              ),
              const SizedBox(height: 16),
              PrismSectionCard(
                padding: const EdgeInsets.all(14),
                staggerIndex: 0,
                staggerDelay: const Duration(milliseconds: 45),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PrismBadge(
                          label: _loadingStatus
                              ? '检查中'
                              : installed
                              ? '已安装'
                              : '未安装',
                          tone: _loadingStatus
                              ? PrismTone.neutral
                              : installed
                              ? PrismTone.success
                              : PrismTone.warning,
                          dot: true,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _loadingStatus
                                ? '正在检查内核…'
                                : (_status?['message'] ?? '未知状态').toString(),
                            style: prism.AppTextStyle.footnote.of(context),
                          ),
                        ),
                      ],
                    ),
                    if ((_status?['binaryPath'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _status!['binaryPath'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.caption1
                            .of(context)
                            .copyWith(
                              color: prism.Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_progress case final progress?) ...[
                const SizedBox(height: 16),
                PrismProgressPanel(
                  title: progress['phase'] == 'done'
                      ? '下载完成'
                      : progress['phase'] == 'error'
                      ? '下载失败'
                      : '正在下载 $_core',
                  subtitle: (progress['message'] ?? '').toString(),
                  progress: progress['phase'] == 'error' ? 0 : progressValue,
                ),
              ],
              if (_downloadInfo case final info?) ...[
                const SizedBox(height: 16),
                PrismSectionCard(
                  title: '手动下载信息',
                  glyph: AntGlyphs.info,
                  padding: const EdgeInsets.all(14),
                  staggerIndex: 1,
                  staggerDelay: const Duration(milliseconds: 45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((info['version'] ?? '').toString().isNotEmpty)
                        Text(
                          '版本：${info['version']}',
                          style: prism.AppTextStyle.footnote.of(context),
                        ),
                      if ((info['assetName'] ?? '').toString().isNotEmpty)
                        Text(
                          '资源文件：${info['assetName']}',
                          style: prism.AppTextStyle.footnote.of(context),
                        ),
                      if ((info['installDir'] ?? '').toString().isNotEmpty)
                        Text(
                          '安装目录：${info['installDir']}',
                          style: prism.AppTextStyle.footnote.of(context),
                        ),
                      if ((info['message'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          info['message'].toString(),
                          style: prism.AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                color: prism.Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        prism.TextButton(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        prism.OutlinedButton(
          onPressed: _loadingInfo ? null : _openRemoteDownload,
          child: Text(_loadingInfo ? '查询中…' : '手动下载'),
        ),
        prism.OutlinedButton(
          onPressed: _openLocalDirectory,
          child: const Text('打开目录'),
        ),
        prism.FilledButton(
          onPressed: _downloading ? null : _startDownload,
          child: Text(_downloading ? '下载中…' : '开始下载'),
        ),
      ],
    );
  }
}

class ProxyAlignPage extends StatefulWidget {
  const ProxyAlignPage({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<ProxyAlignPage> createState() => _ProxyAlignPageState();
}

class _ProxyAlignPageState extends State<ProxyAlignPage> {
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _records = [];
  String _sourceId = '';
  String _busy = '';
  bool _loading = true;

  List<Map<String, dynamic>> get _sources {
    final result = <String, Map<String, dynamic>>{};
    for (final proxy in _proxies) {
      final id = (proxy['sourceId'] ?? '').toString().trim();
      if (id.isNotEmpty) result.putIfAbsent(id, () => proxy);
    }
    return result.entries
        .map((entry) => {'sourceId': entry.key, ...entry.value})
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final value = await AppBridge.call('BrowserProxyList');
      _proxies = (value as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final sources = _sources;
      if (!sources.any((item) => item['sourceId'] == _sourceId) &&
          sources.isNotEmpty) {
        _sourceId = sources.first['sourceId'].toString();
      }
      if (_sourceId.isNotEmpty) await _loadRecords();
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRecords() async {
    final result = await AppBridge.call('BrowserProxyAlignRecords', [
      _sourceId,
    ]);
    _records = (result as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _editSourceSettings(Map<String, dynamic> source) async {
    final sourceId = (source['sourceId'] ?? '').toString();
    final interval = TextEditingController(
      text:
          '${int.tryParse('${source['sourceRefreshIntervalM'] ?? 0}') ?? 1440}',
    );
    var autoRefresh = source['sourceAutoRefresh'] == true;
    var fetchProxyId = (source['sourceFetchProxyId'] ?? '').toString();
    var saving = false;
    final saved = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => PrismDialog(
          title: const Text('订阅源设置'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrismSwitchTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动刷新'),
                  value: autoRefresh,
                  onChanged: (value) => setDialog(() => autoRefresh = value),
                ),
                if (autoRefresh) ...[
                  const SizedBox(height: 10),
                  PrismTextField(
                    controller: interval,
                    keyboardType: TextInputType.number,
                    decoration: const PrismInputDecoration(
                      labelText: '刷新间隔（分钟，5–1440）',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                PrismDropdownField<String>(
                  value: fetchProxyId,
                  decoration: const PrismInputDecoration(
                    labelText: '拉取订阅使用的代理',
                  ),
                  items: [
                    const PrismDropdownItem(value: '', child: Text('直连')),
                    if (fetchProxyId.isNotEmpty &&
                        !_proxies.any(
                          (proxy) =>
                              (proxy['proxyId'] ?? '').toString() ==
                              fetchProxyId,
                        ))
                      PrismDropdownItem(
                        value: fetchProxyId,
                        child: const Text('当前拉取代理已不存在'),
                      ),
                    for (final proxy in _proxies)
                      if ((proxy['proxyId'] ?? '').toString().isNotEmpty &&
                          proxy['proxyConfig'] != 'direct://')
                        PrismDropdownItem(
                          value: proxy['proxyId'].toString(),
                          child: Text(
                            (proxy['proxyName'] ?? '未命名代理').toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      setDialog(() => fetchProxyId = value ?? ''),
                ),
              ],
            ),
          ),
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            prism.FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final intervalM = autoRefresh
                          ? (int.tryParse(interval.text) ?? 1440).clamp(5, 1440)
                          : 0;
                      setDialog(() => saving = true);
                      try {
                        await AppBridge.call('BrowserProxyUpdateSourceConfig', [
                          sourceId,
                          autoRefresh,
                          intervalM,
                          fetchProxyId,
                        ]);
                        if (context.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (context.mounted) {
                          showPrismNotice(context, '保存订阅源设置失败：$error');
                          setDialog(() => saving = false);
                        }
                      }
                    },
              child: Text(saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
    interval.dispose();
    if (saved == true && mounted) {
      await _load();
      if (mounted) showPrismNotice(context, '订阅源设置已保存');
    }
  }

  Future<void> _refreshAllSources() async {
    final sources = _sources;
    if (sources.isEmpty || _busy.isNotEmpty) return;
    setState(() => _busy = 'all');
    var succeeded = 0;
    final failed = <String>[];
    try {
      for (final source in sources) {
        final id = (source['sourceId'] ?? '').toString();
        try {
          await AppBridge.call('BrowserProxyRefreshSource', [
            id,
            source['sourceFetchProxyId'] ?? '',
          ]);
          succeeded++;
        } catch (_) {
          failed.add(
            (source['sourceNamePrefix'] ?? source['sourceUrl'] ?? id)
                .toString(),
          );
        }
      }
      await _load();
      if (mounted) {
        showPrismNotice(
          context,
          failed.isEmpty
              ? '已刷新 $succeeded 个订阅源'
              : '刷新完成：成功 $succeeded 个，失败 ${failed.length} 个',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAlignmentNodes(
    Map<String, dynamic> source,
  ) async {
    final url = (source['sourceUrl'] ?? '').toString();
    final fetchProxyId = (source['sourceFetchProxyId'] ?? '').toString();
    final fetched = await AppBridge.call(
      fetchProxyId.isEmpty
          ? 'BrowserProxyFetchClashByURL'
          : 'BrowserProxyFetchClashByURLWithProxy',
      fetchProxyId.isEmpty ? [url] : [url, fetchProxyId],
    );
    return _parseClashNodes(
      ((fetched as Map)['content'] ?? '').toString(),
      (source['sourceNamePrefix'] ?? '').toString(),
    );
  }

  Future<void> _refreshSource(
    Map<String, dynamic> source, {
    List<Map<String, dynamic>> manualPairs = const [],
  }) async {
    final id = source['sourceId'].toString();
    final originalIds = _proxies
        .where((proxy) => (proxy['sourceId'] ?? '').toString() == id)
        .map((proxy) => (proxy['proxyId'] ?? '').toString())
        .toSet();
    setState(() => _busy = id);
    try {
      final result = await AppBridge.call('BrowserProxyRefreshSource', [
        id,
        source['sourceFetchProxyId'] ?? '',
      ]);
      final value = Map<String, dynamic>.from(result as Map);
      if (manualPairs.isNotEmpty) {
        final current = await AppBridge.call('BrowserProxyList');
        final next = (current as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final now = DateTime.now().toUtc().toIso8601String();
        for (final pair in manualPairs) {
          final oldId = (pair['oldProxyId'] ?? '').toString();
          final nodeConfig = (pair['newNodeConfig'] ?? '').toString();
          final nodeName = (pair['newNodeName'] ?? '').toString();
          final newType = _proxyProtocol({'proxyConfig': nodeConfig});
          final oldIndex = next.indexWhere(
            (proxy) => (proxy['proxyId'] ?? '').toString() == oldId,
          );
          if (oldIndex < 0 || nodeConfig.isEmpty) continue;
          next.removeWhere(
            (proxy) =>
                (proxy['sourceId'] ?? '').toString() == id &&
                !originalIds.contains((proxy['proxyId'] ?? '').toString()) &&
                (proxy['proxyConfig'] ?? '').toString() == nodeConfig,
          );
          final index = next.indexWhere(
            (proxy) => (proxy['proxyId'] ?? '').toString() == oldId,
          );
          if (index < 0) continue;
          final old = next[index];
          final updated = <String, dynamic>{
            ...old,
            'proxyName': nodeName,
            'proxyConfig': nodeConfig,
            'sourceMissing': false,
            'sourceMissingSince': '',
            'sourceLastRefreshAt': now,
            'sourceLastRefreshError': '',
          };
          final oldType = _proxyProtocol(old);
          _applyPreferredKernel(
            updated,
            oldType == newType
                ? _normalizeKernel(old['preferredKernel'])
                : 'auto',
          );
          next[index] = updated;
        }
        await AppBridge.call('SaveBrowserProxies', [next]);
        value['manualMatched'] = manualPairs.length;
      }
      final alignmentSummary = manualPairs.isEmpty
          ? ''
          : '手动匹配 ${value['manualMatched'] ?? 0}，';
      if (mounted) {
        showPrismNotice(
          context,
          '刷新完成：$alignmentSummary新增 ${value['added'] ?? 0}，标记异常 ${value['markedMissing'] ?? 0}',
        );
      }
      await _load();
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _openManualAlign(Map<String, dynamic> source) async {
    final sourceId = source['sourceId'].toString();
    final oldProxies = _proxies
        .where((proxy) => (proxy['sourceId'] ?? '').toString() == sourceId)
        .toList();
    if (oldProxies.isEmpty || _busy.isNotEmpty) return;
    setState(() => _busy = 'preview:$sourceId');
    try {
      final nodes = await _fetchAlignmentNodes(source);
      if (!mounted) return;
      if (nodes.isEmpty) throw StateError('订阅中没有可匹配的节点');
      final pairs = await showPrismDialog<List<Map<String, dynamic>>>(
        context: context,
        useRootNavigator: false,
        builder: (context) => _ProxyManualAlignmentDialog(
          oldProxies: oldProxies,
          newNodes: nodes,
        ),
      );
      if (!mounted || pairs == null || pairs.isEmpty) return;
      await _refreshSource(source, manualPairs: pairs);
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted && _busy == 'preview:$sourceId') setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _sources
        .where((item) => item['sourceId'] == _sourceId)
        .firstOrNull;
    final theme = prism.Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: prism.IconButton(
                  tooltip: '返回代理池',
                  onPressed: widget.onBack,
                  icon: const PrismGlyph(AntGlyphs.arrowBack, size: 18),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: PrismPageContextBar(
                  glyph: AntGlyphs.compare,
                  title: '订阅源管理与对齐记录',
                  subtitle: '刷新订阅前后对比节点变化，手动维护新旧节点对应关系。',
                  actions: [
                    prism.IconButton(
                      tooltip: '刷新记录',
                      onPressed: _load,
                      icon: const PrismGlyph(AntGlyphs.refresh, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_sources.isNotEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: PrismDropdownField<String>(
                    value: _sourceId,
                    decoration: const PrismInputDecoration(labelText: '订阅来源'),
                    items: [
                      for (final item in _sources)
                        PrismDropdownItem(
                          value: item['sourceId'].toString(),
                          child: Text(
                            (item['sourceNamePrefix']?.toString().isNotEmpty ==
                                        true
                                    ? item['sourceNamePrefix']
                                    : _subscriptionHost(
                                        (item['sourceUrl'] ?? '').toString(),
                                      ))
                                .toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() {
                        _sourceId = value;
                        _loading = true;
                      });
                      try {
                        await _loadRecords();
                      } catch (error) {
                        if (mounted) showPrismNotice(context, error.toString());
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    },
                  ),
                ),
                prism.TonalButtonGroup(
                  size: prism.TonalButtonSize.section,
                  children: [
                    prism.IconButton(
                      tooltip: '手动匹配',
                      onPressed: source == null || _busy.isNotEmpty
                          ? null
                          : () => _openManualAlign(source),
                      icon: const PrismGlyph(AntGlyphs.compare, size: 18),
                    ),
                    prism.IconButton(
                      tooltip: '编辑当前订阅源设置',
                      onPressed: source == null || _busy.isNotEmpty
                          ? null
                          : () => _editSourceSettings(source),
                      icon: const PrismGlyph(AntGlyphs.settings, size: 18),
                    ),
                    prism.IconButton(
                      tooltip: '刷新全部订阅源',
                      onPressed: _busy.isNotEmpty || _sources.isEmpty
                          ? null
                          : _refreshAllSources,
                      icon: _busy == 'all'
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: PrismProgressIndicator(size: 18),
                            )
                          : const PrismGlyph(AntGlyphs.sync, size: 18),
                    ),
                  ],
                ),
                PrismHoverMotion(
                  enabled: source != null && _busy.isEmpty,
                  child: prism.FilledButton.icon(
                    onPressed: source == null || _busy.isNotEmpty
                        ? null
                        : () => _refreshSource(source),
                    icon: const PrismGlyph(AntGlyphs.sync, size: 16),
                    label: Text(_busy.isNotEmpty ? '处理中…' : '刷新订阅'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: PrismProgressIndicator())
                : _sources.isEmpty
                ? const PrismEmptyState(
                    title: '还没有订阅来源',
                    subtitle: '在代理池中通过“导入订阅”添加订阅 URL 后即可管理与对齐。',
                    glyph: AntGlyphs.link,
                  )
                : _records.isEmpty
                ? const PrismEmptyState(
                    title: '还没有对齐记录',
                    subtitle: '点击“手动匹配”可在刷新前指定新旧节点对应关系。',
                    glyph: AntGlyphs.compare,
                  )
                : ListView.separated(
                    padding: kPrismListPadding,
                    itemCount: _records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final record = _records[index];
                      final isAuto = record['mode'] == 'auto';
                      return PrismCard(
                        margin: EdgeInsets.zero,
                        child: PrismListTile(
                          leading: PrismGlyph(
                            isAuto ? AntGlyphs.sync : AntGlyphs.compare,
                            size: 18,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isAuto ? '自动刷新记录' : '手动匹配记录',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              PrismBadge(
                                label: isAuto ? '自动' : '手动',
                                tone: isAuto
                                    ? PrismTone.info
                                    : PrismTone.primary,
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Text(
                                '${_formatShortTime((record['at'] ?? '').toString())} · 新增 ${record['added'] ?? 0} · 保留异常 ${record['keptMissing'] ?? 0}',
                              ),
                              for (final pair
                                  in (record['pairs'] as List? ?? [])
                                      .whereType<Map>())
                                Text(
                                  '${pair['oldName'] ?? ''} → ${pair['newName'] ?? ''} · ${pair['match'] ?? ''}',
                                  style: prism.AppTextStyle.footnote
                                      .of(context)
                                      .copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProxyManualAlignmentDialog extends StatefulWidget {
  const _ProxyManualAlignmentDialog({
    required this.oldProxies,
    required this.newNodes,
  });

  final List<Map<String, dynamic>> oldProxies;
  final List<Map<String, dynamic>> newNodes;

  @override
  State<_ProxyManualAlignmentDialog> createState() =>
      _ProxyManualAlignmentDialogState();
}

class _ProxyManualAlignmentDialogState
    extends State<_ProxyManualAlignmentDialog> {
  final Map<String, int> _selectedNodes = {};

  String _nodeLabel(Map<String, dynamic> node) {
    final endpoint = [
      '${node['server'] ?? ''}:${node['port'] ?? ''}',
      '${node['type'] ?? ''}',
    ].where((part) => part.replaceAll(':', '').trim().isNotEmpty).join(' · ');
    return endpoint.isEmpty
        ? '${node['name'] ?? '未命名节点'}'
        : '${node['name'] ?? '未命名节点'} · $endpoint';
  }

  @override
  Widget build(BuildContext context) {
    final theme = prism.Theme.of(context);
    return PrismDialog(
      title: const Text('手动匹配订阅节点'),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '为需要保留实例绑定的旧代理选择新的订阅节点。未选择的代理仍按自动规则刷新。',
              style: prism.AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: kPrismListPadding,
                itemCount: widget.oldProxies.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final proxy = widget.oldProxies[index];
                  final proxyId = (proxy['proxyId'] ?? '').toString();
                  final selected = _selectedNodes[proxyId];
                  final options = widget.newNodes.where((node) {
                    final nodeIndex = node['index'] as int;
                    final usedByOther = _selectedNodes.entries.any(
                      (entry) =>
                          entry.key != proxyId && entry.value == nodeIndex,
                    );
                    return !usedByOther || selected == nodeIndex;
                  }).toList();
                  return PrismCard(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (proxy['proxyName'] ?? '未命名代理').toString(),
                            style: prism.AppTextStyle.subheadline.of(
                              context,
                              emphasized: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          PrismDropdownField<int>(
                            value: selected,
                            isExpanded: true,
                            decoration: const PrismInputDecoration(
                              labelText: '对应的新节点',
                              isDense: true,
                            ),
                            items: [
                              for (final node in options)
                                PrismDropdownItem(
                                  value: node['index'] as int,
                                  child: Text(
                                    _nodeLabel(node),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              if (value == null) {
                                _selectedNodes.remove(proxyId);
                              } else {
                                _selectedNodes[proxyId] = value;
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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
          onPressed: _selectedNodes.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final entry in _selectedNodes.entries)
                    {
                      'oldProxyId': entry.key,
                      'newNodeIndex': entry.value,
                      'newNodeKey': widget.newNodes.firstWhere(
                        (node) => node['index'] == entry.value,
                      )['key'],
                      'newNodeName': widget.newNodes.firstWhere(
                        (node) => node['index'] == entry.value,
                      )['name'],
                      'newNodeConfig': widget.newNodes.firstWhere(
                        (node) => node['index'] == entry.value,
                      )['config'],
                    },
                ]),
          child: Text('应用并刷新（${_selectedNodes.length}）'),
        ),
      ],
    );
  }
}

class ProxyGroupsPage extends StatefulWidget {
  const ProxyGroupsPage({super.key, this.onBack});
  final VoidCallback? onBack;
  @override
  State<ProxyGroupsPage> createState() => _ProxyGroupsPageState();
}

class _ProxyGroupsPageState extends State<ProxyGroupsPage> {
  static const Map<String, List<String>> _regionKeywords = {
    'US': ['us', 'usa', 'united states', '美国', '美区', '洛杉矶', '圣何塞', '西雅图'],
    'JP': ['jp', 'japan', '日本', '东京', '大阪'],
    'HK': ['hk', 'hong kong', 'hongkong', '香港'],
    'TW': ['tw', 'taiwan', '台湾', '台北'],
    'SG': ['sg', 'singapore', '新加坡', '狮城'],
    'KR': ['kr', 'korea', '韩国', '首尔'],
    'UK': ['uk', 'gb', 'britain', 'london', '英国', '伦敦'],
    'DE': ['de', 'germany', 'frankfurt', '德国', '法兰克福'],
    'FR': ['fr', 'france', 'paris', '法国', '巴黎'],
    'CA': ['ca', 'canada', '加拿大'],
    'AU': ['au', 'australia', '澳大利亚', '澳洲'],
  };

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _proxies = [];
  List<Map<String, dynamic>> _health = [];
  final Map<String, Map<String, dynamic>> _speedCache = {};
  bool _loading = true;
  String _busy = '';
  String _query = '';
  String _filter = 'all';
  final List<void Function()> _eventUnsubscribers = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _eventUnsubscribers.add(
      AppBridge.onEvent('proxy:virtual-group:health', (_) {
        if (mounted) _refresh();
      }),
    );
    _eventUnsubscribers.add(
      AppBridge.onEvent('proxy:speed:result', (payload) {
        if (!mounted || payload is! Map) return;
        final row = Map<String, dynamic>.from(payload);
        final id = (row['proxyId'] ?? '').toString().trim();
        if (id.isNotEmpty) {
          setState(() => _speedCache[id] = row);
        }
      }),
    );
  }

  @override
  void dispose() {
    for (final remove in _eventUnsubscribers) {
      remove();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        AppBridge.call('BrowserProxyVirtualGroupList'),
        AppBridge.call('BrowserProxyList'),
        AppBridge.call('BrowserProxyVirtualGroupHealthList'),
      ]);
      _groups = (values[0] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _proxies = (values[1] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _health = (values[2] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      for (final proxy in _proxies) {
        final id = (proxy['proxyId'] ?? '').toString();
        final testedAt = (proxy['lastTestedAt'] ?? '').toString();
        if (id.isNotEmpty && testedAt.isNotEmpty) {
          _speedCache[id] = {
            'proxyId': id,
            'ok': proxy['lastTestOk'] == true,
            'latencyMs': proxy['lastLatencyMs'] ?? 0,
            'error': proxy['lastTestError'] ?? '',
          };
        }
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _candidateProxies => _proxies.where((proxy) {
    final id = (proxy['proxyId'] ?? '').toString().trim();
    final cfg = (proxy['proxyConfig'] ?? '').toString().trim();
    return id.isNotEmpty && id != '__direct__' && cfg != 'direct://';
  }).toList();

  bool _matchesRegion(Map<String, dynamic> proxy, String region) {
    if (region.isEmpty) return true;
    final keywords = _regionKeywords[region];
    if (keywords == null) return true;
    final haystack = [
      proxy['proxyName'],
      proxy['groupName'],
      _proxyServer(proxy),
    ].join(' ').toLowerCase();
    return keywords.any(haystack.contains);
  }

  Future<void> _edit([Map<String, dynamic>? group]) async {
    final name = TextEditingController(
      text: (group?['groupName'] ?? '').toString(),
    );
    final search = TextEditingController();
    var strategy = (group?['strategy'] ?? 'round_robin').toString();
    final candidates = _candidateProxies;
    final validCandidateIds = candidates
        .map((p) => (p['proxyId'] ?? '').toString())
        .toSet();
    final selected = _resolveMemberProxyIds(group ?? const <String, dynamic>{})
        .where(validCandidateIds.contains)
        .toSet();

    var entityGroupFilter = 'all';
    var onlySelected = false;
    var onlyAvailable = false;
    var regionFilter = '';
    String testingProxyId = '';

    final entityGroups =
        candidates
            .map((p) => (p['groupName'] ?? '').toString().trim())
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final result = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          final query = search.text.trim().toLowerCase();
          final filtered = candidates.where((proxy) {
            final id = (proxy['proxyId'] ?? '').toString();
            if (onlySelected && !selected.contains(id)) return false;
            if (onlyAvailable && _speedCache[id]?['ok'] != true) return false;
            if (entityGroupFilter != 'all' &&
                (proxy['groupName'] ?? '').toString().trim() !=
                    entityGroupFilter) {
              return false;
            }
            if (!_matchesRegion(proxy, regionFilter)) return false;
            if (query.isNotEmpty) {
              final text = [
                proxy['proxyName'],
                proxy['groupName'],
                _proxyServer(proxy),
              ].join(' ').toLowerCase();
              if (!text.contains(query)) return false;
            }
            return true;
          }).toList();

          return PrismDialog(
            title: Text(group == null ? '新建虚拟分组' : '编辑虚拟分组'),
            content: SizedBox(
              width: 660,
              height: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: PrismTextField(
                          controller: name,
                          decoration: const PrismInputDecoration(
                            labelText: '分组名称',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrismDropdownField<String>(
                          value: strategy,
                          decoration: const PrismInputDecoration(
                            labelText: '分配方式',
                          ),
                          items: const [
                            PrismDropdownItem(
                              value: 'round_robin',
                              child: Text('轮询'),
                            ),
                            PrismDropdownItem(
                              value: 'sticky',
                              child: Text('固定节点'),
                            ),
                          ],
                          onChanged: (value) => setDialog(
                            () => strategy = value ?? 'round_robin',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: PrismSearchBar(
                          controller: search,
                          hintText: '搜索成员代理名称、服务器或分组',
                          onChanged: (_) => setDialog(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 170,
                        child: PrismDropdownField<String>(
                          value: entityGroupFilter,
                          decoration: const PrismInputDecoration(
                            isDense: true,
                            hintText: '实体分组',
                          ),
                          items: [
                            const PrismDropdownItem(
                              value: 'all',
                              child: Text('全部实体分组'),
                            ),
                            for (final g in entityGroups)
                              PrismDropdownItem(value: g, child: Text(g)),
                          ],
                          onChanged: (value) => setDialog(
                            () => entityGroupFilter = value ?? 'all',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PrismChip(
                        label: Text('仅显示已选（${selected.length}）'),
                        selected: onlySelected,
                        onSelected: (v) => setDialog(() => onlySelected = v),
                      ),
                      PrismChip(
                        label: const Text('仅显示可选'),
                        selected: onlyAvailable,
                        onSelected: (v) => setDialog(() => onlyAvailable = v),
                      ),
                      for (final code in _regionKeywords.keys)
                        PrismChip(
                          label: Text(code),
                          selected: regionFilter == code,
                          onSelected: (v) =>
                              setDialog(() => regionFilter = v ? code : ''),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const PrismEmptyState(
                            title: '没有符合条件的候选代理',
                            glyph: AntGlyphs.search,
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final proxy = filtered[index];
                              final id = (proxy['proxyId'] ?? '').toString();
                              final speed = _speedCache[id];
                              final speedText = speed == null
                                  ? '未测速'
                                  : speed['ok'] == true
                                  ? '${speed['latencyMs'] ?? 0}ms'
                                  : '失败';
                              final speedTone = speed == null
                                  ? PrismTone.neutral
                                  : speed['ok'] == true
                                  ? PrismTone.success
                                  : PrismTone.danger;
                              return PrismListTile(
                                dense: true,
                                leading: prism.Checkbox(
                                  value: selected.contains(id),
                                  onChanged: (value) => setDialog(() {
                                    if (value == true) {
                                      selected.add(id);
                                    } else {
                                      selected.remove(id);
                                    }
                                  }),
                                ),
                                title: Text(
                                  (proxy['proxyName'] ?? id).toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${_proxyProtocol(proxy).toUpperCase()} · ${_proxyEndpointSummary(proxy)}${(proxy['groupName'] ?? '').toString().isNotEmpty ? ' · ${proxy['groupName']}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PrismBadge(
                                      label: speedText,
                                      tone: speedTone,
                                    ),
                                    const SizedBox(width: 4),
                                    prism.IconButton(
                                      tooltip: '测速',
                                      onPressed: testingProxyId.isNotEmpty
                                          ? null
                                          : () async {
                                              setDialog(
                                                () => testingProxyId = id,
                                              );
                                              try {
                                                final res =
                                                    await AppBridge.call(
                                                      'BrowserProxyTestSpeed',
                                                      [id],
                                                    );
                                                if (res is Map) {
                                                  _speedCache[id] =
                                                      Map<String, dynamic>.from(
                                                        res,
                                                      );
                                                }
                                              } catch (error) {
                                                if (context.mounted) {
                                                  showPrismNotice(
                                                    context,
                                                    '测速失败：$error',
                                                  );
                                                }
                                              } finally {
                                                if (context.mounted) {
                                                  setDialog(
                                                    () => testingProxyId = '',
                                                  );
                                                }
                                              }
                                            },
                                      icon: testingProxyId == id
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: PrismProgressIndicator(
                                                size: 14,
                                              ),
                                            )
                                          : const PrismGlyph(
                                              AntGlyphs.speed,
                                              size: 15,
                                            ),
                                    ),
                                  ],
                                ),
                                onTap: () => setDialog(() {
                                  if (selected.contains(id)) {
                                    selected.remove(id);
                                  } else {
                                    selected.add(id);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              prism.TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              prism.FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) {
                    showPrismNotice(context, '请填写虚拟分组名称');
                    return;
                  }
                  if (selected.isEmpty) {
                    showPrismNotice(context, '请至少选择一个成员代理');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: Text('保存（${selected.length}）'),
              ),
            ],
          );
        },
      ),
    );
    if (result == true && name.text.trim().isNotEmpty && selected.isNotEmpty) {
      final id =
          (group?['groupId'] ??
                  'group-${DateTime.now().millisecondsSinceEpoch}')
              .toString();
      final value = <String, dynamic>{
        ...?group,
        'groupId': id,
        'groupName': name.text.trim(),
        'strategy': strategy,
        'memberProxyIds': selected.toList(),
        'memberGroupNames': <String>[],
      };
      if (strategy != 'sticky') {
        value['selectedProxyId'] = '';
      }
      await AppBridge.call('SaveBrowserProxyVirtualGroup', [value]);
      await _refresh();
    }
    name.dispose();
    search.dispose();
  }

  Future<void> _probe(Map<String, dynamic> group) async {
    final id = (group['groupId'] ?? '').toString();
    setState(() => _busy = id);
    try {
      final raw = await AppBridge.call('BrowserProxyVirtualGroupProbe', [id]);
      await _refresh();
      if (mounted) {
        if (raw is Map) {
          final tested = raw['tested'] ?? 0;
          final healthy = raw['healthy'] ?? 0;
          final degraded = raw['degraded'] ?? 0;
          showPrismNotice(
            context,
            '巡检完成：检测 $tested 个，健康 $healthy 个，降级 $degraded 个',
          );
        } else {
          showPrismNotice(context, '分组巡检完成');
        }
      }
    } catch (error) {
      if (mounted) showPrismNotice(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _resetHealth(Map<String, dynamic> group) async {
    final id = (group['groupId'] ?? '').toString();
    if (id.isEmpty) return;
    final confirmed = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text('重置健康 · ${group['groupName'] ?? id}'),
        content: const Text('将清除该分组的降级与异常记录，恢复全部成员参与调度。'),
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = id);
    try {
      await AppBridge.call('BrowserProxyVirtualGroupResetHealth', [id]);
      await _refresh();
      if (mounted) showPrismNotice(context, '分组健康状态已重置');
    } catch (error) {
      if (mounted) showPrismNotice(context, '重置健康失败：$error');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Set<String> _resolveMemberProxyIds(Map<String, dynamic> group) {
    final selected = (group['memberProxyIds'] as List? ?? [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty && value != '__direct__')
        .toSet();
    final groupNames = (group['memberGroupNames'] as List? ?? [])
        .map((value) => value.toString().trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final proxy in _candidateProxies) {
      final proxyGroup = (proxy['groupName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (proxyGroup.isNotEmpty && groupNames.contains(proxyGroup)) {
        selected.add((proxy['proxyId'] ?? '').toString());
      }
    }
    return selected;
  }

  Future<void> _showMembers(Map<String, dynamic> group) async {
    final id = (group['groupId'] ?? '').toString();
    final memberIds = _resolveMemberProxyIds(group);
    final healthRows = _health.where((row) => row['groupId'] == id);
    final health = healthRows.isEmpty ? null : healthRows.first;
    final memberHealth = (health?['members'] as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    await showPrismDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: Text('关联代理 · ${group['groupName'] ?? id}'),
        content: SizedBox(
          width: 680,
          height: 500,
          child: memberIds.isEmpty
              ? const PrismEmptyState(
                  title: '此虚拟分组还没有关联代理',
                  glyph: AntGlyphs.hub,
                )
              : ListView.separated(
                  padding: kPrismListPadding,
                  itemCount: memberIds.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final proxyId = memberIds.elementAt(index);
                    final proxy = _proxies
                        .where((p) => p['proxyId'] == proxyId)
                        .firstOrNull;
                    final state = memberHealth
                        .where((row) => row['proxyId'] == proxyId)
                        .firstOrNull;
                    final (statusLabel, statusTone) = _localizedMemberState(
                      (state?['state'] ?? '').toString(),
                    );
                    final latency = state?['latencyMs'];
                    final lastError = (state?['lastError'] ?? '')
                        .toString()
                        .trim();
                    final endpoint = proxy == null
                        ? proxyId
                        : '${_proxyProtocol(proxy).toUpperCase()} · ${_proxyEndpointSummary(proxy)}';
                    return PrismCard(
                      margin: EdgeInsets.zero,
                      child: PrismListTile(
                        leading: PrismGlyph(
                          state?['active'] == true
                              ? AntGlyphs.checkCircle
                              : AntGlyphs.circle,
                          size: 18,
                          color: PrismToneColors.of(context, statusTone).fg,
                        ),
                        title: Text(
                          (proxy?['proxyName'] ??
                                  state?['proxyName'] ??
                                  proxyId)
                              .toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$endpoint${latency is num && latency > 0 ? ' · ${latency}ms' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (lastError.isNotEmpty)
                              Text(
                                lastError,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: prism.AppTextStyle.caption1
                                    .of(context)
                                    .copyWith(
                                      color: PrismToneColors.of(
                                        context,
                                        PrismTone.danger,
                                      ).fg,
                                    ),
                              ),
                          ],
                        ),
                        trailing: PrismBadge(
                          label: statusLabel,
                          tone: statusTone,
                          dot: true,
                        ),
                      ),
                    );
                  },
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

  Future<void> _delete(Map<String, dynamic> group) async {
    final yes = await showPrismDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PrismDialog(
        title: const Text('删除虚拟分组？'),
        content: Text((group['groupName'] ?? '').toString()),
        destructive: true,
        actions: [
          prism.TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          prism.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await AppBridge.call('DeleteBrowserProxyVirtualGroup', [
        group['groupId'],
      ]);
      await _refresh();
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _filter = 'all';
    });
  }

  Map<String, dynamic>? _groupHealth(Map<String, dynamic> group) {
    final id = (group['groupId'] ?? '').toString();
    return _health.where((row) => row['groupId'] == id).firstOrNull;
  }

  List<Map<String, dynamic>> _filteredGroups() {
    final query = _query.trim().toLowerCase();
    return _groups.where((group) {
      final strategy = (group['strategy'] ?? 'round_robin').toString();
      final health = _groupHealth(group);
      final isDegraded = health != null && health['allDegraded'] == true;
      final filterOk = switch (_filter) {
        'round_robin' => strategy != 'sticky',
        'sticky' => strategy == 'sticky',
        'degraded' => isDegraded,
        _ => true,
      };
      if (!filterOk) return false;
      if (query.isEmpty) return true;
      final memberNames = _resolveMemberProxyIds(group)
          .map(
            (id) =>
                (_proxies
                            .where((p) => p['proxyId'] == id)
                            .firstOrNull?['proxyName'] ??
                        id)
                    .toString(),
          )
          .join(' ');
      final haystack = [
        group['groupName'],
        group['groupId'],
        strategy == 'sticky' ? '固定节点' : '轮询',
        memberNames,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Widget _buildOverviewStrip(BuildContext context) {
    final totalGroups = _groups.length;
    final stickyCount = _groups.where((g) => g['strategy'] == 'sticky').length;
    final roundRobinCount = totalGroups - stickyCount;
    final uniqueMemberIds = <String>{};
    var healthyGroups = 0;
    var degradedGroups = 0;
    for (final group in _groups) {
      uniqueMemberIds.addAll(_resolveMemberProxyIds(group));
      final health = _groupHealth(group);
      if (health != null) {
        if (health['allDegraded'] == true) {
          degradedGroups++;
        } else {
          healthyGroups++;
        }
      }
    }
    final unprobedGroups = totalGroups - healthyGroups - degradedGroups;

    final tiles = [
      PrismMetricTile(
        label: '虚拟分组',
        value: '$totalGroups',
        subtitle: totalGroups == 0
            ? '支持轮询调度与故障转移'
            : '轮询 $roundRobinCount · 固定 $stickyCount',
        glyph: AntGlyphs.hub,
        tone: PrismTone.primary,
        onPressed: _filter != 'all' || _query.isNotEmpty ? _clearFilters : null,
        staggerIndex: 0,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '调度节点',
        value: '${uniqueMemberIds.length}',
        subtitle: '候选代理 ${_candidateProxies.length} 个',
        glyph: AntGlyphs.globe,
        tone: PrismTone.info,
        staggerIndex: 1,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '健康分组',
        value: '$healthyGroups/$totalGroups',
        subtitle: degradedGroups > 0
            ? '全部降级 $degradedGroups 组 · 点击筛选'
            : (unprobedGroups > 0 ? '待探测 $unprobedGroups 组' : '健康探测全部正常'),
        glyph: AntGlyphs.health,
        tone: degradedGroups > 0
            ? PrismTone.danger
            : (healthyGroups > 0 ? PrismTone.success : PrismTone.neutral),
        onPressed: degradedGroups > 0
            ? () => setState(
                () => _filter = _filter == 'degraded' ? 'all' : 'degraded',
              )
            : null,
        staggerIndex: 2,
        staggerDelay: const Duration(milliseconds: 45),
      ),
      PrismMetricTile(
        label: '调度策略',
        value: stickyCount > 0
            ? '$roundRobinCount / $stickyCount'
            : '轮询 $roundRobinCount',
        subtitle: _filter == 'sticky' ? '正在筛选固定节点组' : '点击筛选固定节点组',
        glyph: AntGlyphs.tune,
        tone: _filter == 'sticky' ? PrismTone.primary : PrismTone.neutral,
        onPressed: stickyCount > 0
            ? () => setState(
                () => _filter = _filter == 'sticky' ? 'all' : 'sticky',
              )
            : null,
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

  Widget _buildToolbar(BuildContext context, VoidCallback? backAction) {
    final filterControl = SizedBox(
      width: 248,
      child: prism.SegmentedControl<String>(
        value: _filter,
        onChanged: (value) => setState(() => _filter = value),
        segments: const [
          ('all', '全部'),
          ('round_robin', '轮询'),
          ('sticky', '固定'),
          ('degraded', '降级'),
        ],
      ),
    );

    final actionWidgets = <Widget>[
      PrismHoverMotion(
        child: prism.FilledButton.icon(
          onPressed: () => _edit(),
          icon: const PrismGlyph(AntGlyphs.add, size: 15),
          label: const Text('新建分组'),
        ),
      ),
      prism.IconButton(
        tooltip: '刷新',
        onPressed: _loading ? null : _refresh,
        icon: const PrismGlyph(AntGlyphs.refresh, size: 17),
      ),
    ];

    return PrismHoverCard(
      staggerIndex: 4,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          if (wide) {
            return Row(
              children: [
                if (backAction != null) ...[
                  prism.IconButton(
                    tooltip: '返回代理池',
                    onPressed: backAction,
                    icon: const PrismGlyph(AntGlyphs.arrowBack, size: 18),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: PrismSearchBar(
                    controller: _searchController,
                    hintText: '搜索分组名称、策略或成员节点…',
                    height: 36,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                const SizedBox(width: 12),
                filterControl,
                const SizedBox(width: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actionWidgets,
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (backAction != null) ...[
                    prism.IconButton(
                      tooltip: '返回代理池',
                      onPressed: backAction,
                      icon: const PrismGlyph(AntGlyphs.arrowBack, size: 18),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: PrismSearchBar(
                      controller: _searchController,
                      hintText: '搜索分组名称、策略或成员节点…',
                      height: 36,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  filterControl,
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actionWidgets,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupRow(BuildContext context, Map<String, dynamic> group) {
    final id = (group['groupId'] ?? '').toString();
    final health = _groupHealth(group);
    final members = _resolveMemberProxyIds(group).length;
    final healthTone = health == null
        ? PrismTone.neutral
        : health['allDegraded'] == true
        ? PrismTone.danger
        : PrismTone.success;
    final healthLabel = health == null
        ? '待检测'
        : health['allDegraded'] == true
        ? '全部降级'
        : '可用 ${health['healthy'] ?? 0}/${health['total'] ?? 0}';
    return PrismCard(
      margin: EdgeInsets.zero,
      child: PrismListTile(
        onTap: () => _showMembers(group),
        title: Row(
          children: [
            Expanded(
              child: Text(
                (group['groupName'] ?? id).toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: prism.AppTextStyle.subheadline.of(
                  context,
                  emphasized: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            PrismBadge(
              label: group['strategy'] == 'sticky' ? '固定节点' : '轮询',
              tone: PrismTone.primary,
            ),
            const SizedBox(width: 10),
            PrismBadge(label: healthLabel, tone: healthTone, dot: true),
          ],
        ),
        subtitle: Text('$members 个成员'),
        trailing: prism.TonalButtonGroup(
          size: prism.TonalButtonSize.section,
          children: [
            prism.IconButton(
              tooltip: '探测',
              onPressed: _busy == id ? null : () => _probe(group),
              icon: _busy == id
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: PrismProgressIndicator(size: 18),
                    )
                  : const PrismGlyph(AntGlyphs.health, size: 18),
            ),
            prism.IconButton(
              tooltip: '重置健康',
              onPressed: _busy.isEmpty ? () => _resetHealth(group) : null,
              icon: const PrismGlyph(AntGlyphs.restart, size: 18),
            ),
            prism.IconButton(
              tooltip: '编辑',
              onPressed: () => _edit(group),
              icon: const PrismGlyph(AntGlyphs.edit, size: 18),
            ),
            prism.IconButton(
              tooltip: '删除',
              onPressed: () => _delete(group),
              icon: const PrismGlyph(AntGlyphs.delete, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupsSection(
    BuildContext context,
    List<Map<String, dynamic>> filteredGroups,
  ) {
    final hasActiveFilters = _query.trim().isNotEmpty || _filter != 'all';
    return PrismHoverCard(
      staggerIndex: 5,
      staggerDelay: const Duration(milliseconds: 45),
      radius: prism.AppCorner.xl,
      lift: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          prism.InfoHeader(
            info: const prism.Info(label: '虚拟分组列表', glyph: AntGlyphs.hub),
            actions: [
              if (hasActiveFilters)
                prism.TextButton(
                  onPressed: _clearFilters,
                  child: const Text('清除筛选'),
                ),
              PrismBadge(
                label: '${filteredGroups.length} 组',
                tone: filteredGroups.isEmpty
                    ? PrismTone.neutral
                    : PrismTone.primary,
              ),
            ],
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
          ),
          const prism.Divider(height: 1),
          Expanded(
            child: prism.PageTransitionSwitcher(
              duration: PrismMotionSpec.current.pageDuration,
              transitionBuilder: PrismSlideThroughTransition.builder,
              child: KeyedSubtree(
                key: ValueKey(
                  '$_filter-${_query.trim()}-$_loading-${filteredGroups.isEmpty}',
                ),
                child: _loading
                    ? const Center(child: PrismProgressIndicator())
                    : filteredGroups.isEmpty
                    ? (_groups.isEmpty
                          ? PrismEmptyState(
                              title: '还没有虚拟分组',
                              subtitle: '将多个代理节点组合为虚拟分组，支持轮询调度、自动健康探测与故障转移。',
                              glyph: AntGlyphs.hub,
                              action: PrismHoverMotion(
                                child: prism.FilledButton.icon(
                                  onPressed: () => _edit(),
                                  icon: const PrismGlyph(
                                    AntGlyphs.add,
                                    size: 16,
                                  ),
                                  label: const Text('新建分组'),
                                ),
                              ),
                            )
                          : PrismEmptyState(
                              title: '没有匹配的虚拟分组',
                              subtitle: '尝试调整搜索关键词或切换策略筛选条件。',
                              glyph: AntGlyphs.search,
                              action: prism.OutlinedButton(
                                onPressed: _clearFilters,
                                child: const Text('重置筛选'),
                              ),
                            ))
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: ListView.separated(
                          padding: kPrismListPadding,
                          itemCount: filteredGroups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) =>
                              _buildGroupRow(context, filteredGroups[index]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final backAction =
        widget.onBack ??
        (canPop ? () => Navigator.of(context).maybePop() : null);
    final filteredGroups = _filteredGroups();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewStrip(context),
          const SizedBox(height: 16),
          _buildToolbar(context, backAction),
          const SizedBox(height: 16),
          Expanded(child: _buildGroupsSection(context, filteredGroups)),
        ],
      ),
    );
  }
}
