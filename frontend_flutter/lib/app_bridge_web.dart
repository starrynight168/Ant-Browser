import 'dart:convert';
import 'dart:js_interop';

@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external _DateTimeFormat();
  external _DateTimeFormatOptions resolvedOptions();
}

extension type _DateTimeFormatOptions(JSObject _) implements JSObject {
  external JSString get timeZone;
}

@JS('antWailsBridge.invoke')
external JSPromise<JSString> _invoke(JSString method, JSString arguments);

@JS('antWailsBridge.openExternal')
external void _openExternal(JSString url);

@JS('antWailsBridge.subscribe')
external JSNumber _subscribe(JSString eventName, JSFunction callback);

@JS('antWailsBridge.unsubscribe')
external void _unsubscribe(JSNumber subscriptionId);

@JS('antWailsBridge.windowHide')
external void _windowHide();

@JS('antWailsBridge.windowMinimise')
external void _windowMinimise();

@JS('antWailsBridge.quit')
external void _quit();

@JS('antWailsBridge.platform')
external JSPromise<JSString> _platform();

@JS('antWailsBridge.storageGet')
external JSString _storageGet(JSString key);

@JS('antWailsBridge.storageSet')
external void _storageSet(JSString key, JSString value);

@JS('antWailsBridge.storageRemove')
external void _storageRemove(JSString key);

@JS('window.history.replaceState')
external void _replaceHistoryState(JSAny? data, JSString title, JSString url);

class AppBridge {
  static Future<void> initialize() async {}

  static Future<dynamic> call(String method, [List<Object?> arguments = const []]) async {
    final payload = await _invoke(method.toJS, jsonEncode(arguments).toJS).toDart;
    final response = jsonDecode(payload.toDart) as Map<String, dynamic>;
    final error = response['error'];
    if (error != null) throw StateError(error.toString());
    return response['value'];
  }

  static void openExternal(String url) => _openExternal(url.toJS);

  static void Function() onEvent(String eventName, void Function(dynamic) listener) {
    final callback = ((JSString arguments) {
      final values = jsonDecode(arguments.toDart);
      listener(values is List && values.length == 1 ? values.first : values);
    }).toJS;
    final id = _subscribe(eventName.toJS, callback);
    return () => _unsubscribe(id);
  }

  static void hideWindow() => _windowHide();

  static void minimiseWindow() => _windowMinimise();

  static void quit() => _quit();

  static Future<String> platform() async => (await _platform().toDart).toDart;

  static Future<String> systemTimezone() async =>
      _DateTimeFormat().resolvedOptions().timeZone.toDart;

  static void replaceBrowserUrl(Uri uri) =>
      _replaceHistoryState(null, ''.toJS, uri.toString().toJS);

  static String readStorage(String key) => _storageGet(key.toJS).toDart;

  static void writeStorage(String key, String value) => _storageSet(key.toJS, value.toJS);

  static void removeStorage(String key) => _storageRemove(key.toJS);
}
