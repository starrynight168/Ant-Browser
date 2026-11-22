export 'wails_bridge_stub.dart'
    if (dart.library.io) 'wails_bridge_native.dart'
    if (dart.library.js_interop) 'wails_bridge_web.dart';
