class WailsBridge {
  static Future<void> initialize() async {}

  static Future<dynamic> call(String method, [List<Object?> arguments = const []]) async {
    throw UnsupportedError('桌面后端尚未连接');
  }

  static void Function() onEvent(String eventName, void Function(dynamic) listener) =>
      () {};

  static void openExternal(String url) {}

  static void hideWindow() {}

  static void minimiseWindow() {}

  static void quit() {}

  static Future<String> platform() async => 'unknown';

  static String readStorage(String key) => '';

  static void writeStorage(String key, String value) {}

  static void removeStorage(String key) {}
}
