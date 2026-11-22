import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class AppBridge {
  static const _channel = MethodChannel('ant_browser/platform');
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  static final Map<int, _EventSubscription> _subscriptions = {};
  static final Map<String, String> _storage = {};
  static int _nextSubscriptionId = 0;
  static bool _eventLoopRunning = false;

  static String get _baseUrl =>
      Platform.environment['ANT_BROWSER_NATIVE_RPC_URL'] ?? '';
  static String get _token =>
      Platform.environment['ANT_BROWSER_NATIVE_RPC_TOKEN'] ?? '';

  static Future<void> initialize() async {
    _loadStorage();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'windowCloseRequested') {
        try {
          final shouldBlock = await AppBridge.call('HandleWindowCloseRequest');
          if (shouldBlock != true) {
            await _channel.invokeMethod<void>('window.close');
          }
        } catch (_) {
          await _channel.invokeMethod<void>('window.close');
        }
      }
      return null;
    });
  }

  static Future<dynamic> call(String method, [List<Object?> arguments = const []]) async {
    final response = await _post('/api/v1/invoke', {
      'method': method,
      'args': arguments,
    });
    final error = response['error'];
    if (error != null) throw StateError(error.toString());
    return response['value'];
  }

  static void Function() onEvent(String eventName, void Function(dynamic) listener) {
    final id = ++_nextSubscriptionId;
    _subscriptions[id] = _EventSubscription(eventName, listener);
    _startEventLoop();
    return () {
      _subscriptions.remove(id);
    };
  }

  static void openExternal(String url) {
    unawaited(_channel.invokeMethod<void>('openExternal', url).catchError((_) {}));
  }

  static void hideWindow() {
    unawaited(_channel.invokeMethod<void>('window.hide').catchError((_) {}));
  }

  static void minimiseWindow() {
    unawaited(_channel.invokeMethod<void>('window.minimize').catchError((_) {}));
  }

  static void quit() {
    unawaited(_channel.invokeMethod<void>('window.close').catchError((_) {}));
  }

  static Future<String> platform() async => 'windows';

  static String readStorage(String key) => _storage[key] ?? '';

  static void writeStorage(String key, String value) {
    _storage[key] = value;
    _saveStorage();
  }

  static void removeStorage(String key) {
    _storage.remove(key);
    _saveStorage();
  }

  static void _loadStorage() {
    final file = _storageFile;
    try {
      if (!file.existsSync()) return;
      final values = jsonDecode(file.readAsStringSync());
      if (values is Map) {
        _storage
          ..clear()
          ..addAll(values.map((key, value) => MapEntry('$key', '$value')));
      }
    } catch (_) {}
  }

  static void _saveStorage() {
    try {
      final file = _storageFile;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(_storage), flush: true);
    } catch (_) {}
  }

  static File get _storageFile {
    final root = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.systemTemp.path;
    return File('$root${Platform.pathSeparator}Ant Browser'
        '${Platform.pathSeparator}ui-preferences.json');
  }

  static void _startEventLoop() {
    if (_eventLoopRunning) return;
    _eventLoopRunning = true;
    unawaited(_readEvents());
  }

  static Future<void> _readEvents() async {
    while (_subscriptions.isNotEmpty) {
      try {
        if (_baseUrl.isEmpty || _token.isEmpty) {
          throw StateError('本地后端未启动');
        }
        final request = await _http.getUrl(Uri.parse('$_baseUrl/api/v1/events'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('事件连接失败：${response.statusCode}');
        }
        String? data;
        await for (final line
            in response.transform(utf8.decoder).transform(const LineSplitter())) {
          if (line.startsWith('data:')) {
            data = line.substring(5).trimLeft();
          } else if (line.isEmpty && data != null) {
            _dispatchEvent(jsonDecode(data));
            data = null;
          }
          if (_subscriptions.isEmpty) break;
        }
      } catch (_) {
        if (_subscriptions.isNotEmpty) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
    _eventLoopRunning = false;
    if (_subscriptions.isNotEmpty) _startEventLoop();
  }

  static void _dispatchEvent(dynamic decoded) {
    if (decoded is! Map) return;
    final name = decoded['name']?.toString() ?? '';
    final arguments = decoded['args'] is List ? decoded['args'] as List : const [];
    if (name == 'native:dialog' && arguments.isNotEmpty) {
      unawaited(_handleDialog(arguments.first));
      return;
    }
    final value = arguments.length == 1 ? arguments.first : arguments;
    for (final subscription in List<_EventSubscription>.of(_subscriptions.values)) {
      if (subscription.eventName == name) subscription.listener(value);
    }
  }

  static Future<void> _handleDialog(dynamic payload) async {
    if (payload is! Map) return;
    final requestId = payload['requestId']?.toString() ?? '';
    final kind = payload['kind']?.toString() ?? '';
    final options = payload['options'] is Map
        ? Map<String, dynamic>.from(payload['options'] as Map)
        : <String, dynamic>{};
    String? value;
    String? error;
    try {
      final method = switch (kind) {
        'openFile' => 'dialog.openFile',
        'openDirectory' => 'dialog.openDirectory',
        'saveFile' => 'dialog.saveFile',
        'message' => 'dialog.message',
        _ => throw StateError('未知的系统对话框类型：$kind'),
      };
      value = await _channel.invokeMethod<String?>(method, options);
    } catch (exception) {
      error = exception.toString();
    }
    try {
      await _post('/api/v1/dialog/complete', {
        'requestId': requestId,
        'value': value ?? '',
        'error': error ?? '',
      });
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _post(
      String path, Map<String, Object?> body) async {
    if (_baseUrl.isEmpty || _token.isEmpty) {
      throw StateError('本地 Go 后端未连接');
    }
    final request = await _http.postUrl(Uri.parse('$_baseUrl$path'));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $_token')
      ..contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.noContent) return {};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('本地后端请求失败：${response.statusCode} $text');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('后端响应格式无效');
    return Map<String, dynamic>.from(decoded);
  }
}

class _EventSubscription {
  const _EventSubscription(this.eventName, this.listener);

  final String eventName;
  final void Function(dynamic) listener;
}
