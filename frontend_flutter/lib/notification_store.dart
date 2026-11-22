import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_bridge.dart';

class NotificationStore extends ChangeNotifier {
  static const _storageKey = 'ant-browser-notifications';
  static const _maxNotifications = 100;
  final List<Map<String, dynamic>> notifications = [];
  final List<void Function()> _removeListeners = [];

  NotificationStore() {
    _restore();
    _listen('browser:instance:crashed', _onCrash);
    _listen('proxy:bridge:failed', _onBridgeFailed);
    _listen('proxy:bridge:died', _onBridgeDied);
  }

  int get unreadCount =>
      notifications.where((item) => item['read'] != true).length;

  void _restore() {
    try {
      final raw = AppBridge.readStorage(_storageKey);
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      final state = decoded is Map ? decoded['state'] : null;
      final items = state is Map ? state['notifications'] : null;
      if (items is! List) return;
      for (final item in items.take(_maxNotifications)) {
        if (item is Map && '${item['message'] ?? ''}'.trim().isNotEmpty) {
          notifications.add(Map<String, dynamic>.from(item));
        }
      }
    } catch (_) {}
  }

  void _listen(String event, void Function(Map<String, dynamic>) onEvent) {
    _removeListeners.add(
      AppBridge.onEvent(event, (payload) {
        if (payload is Map) onEvent(Map<String, dynamic>.from(payload));
      }),
    );
  }

  void _onCrash(Map<String, dynamic> data) {
    final id = '${data['profileId'] ?? ''}';
    _add(
      type: 'error',
      title: '实例异常退出',
      message: '「${data['profileName'] ?? id}」意外崩溃：${data['error'] ?? ''}',
      source: 'runtime',
      dedupeKey: 'browser:instance:crashed:$id',
      action: id.isEmpty
          ? null
          : {
              'type': 'navigate',
              'label': '查看实例',
              'path': '/browser/detail/$id',
            },
    );
  }

  void _onBridgeFailed(Map<String, dynamic> data) {
    final id = '${data['profileId'] ?? ''}';
    _add(
      type: 'warning',
      title: '代理桥接失败',
      message: '「${data['profileName'] ?? id}」代理桥接失败：${data['error'] ?? ''}',
      source: 'runtime',
      dedupeKey: 'proxy:bridge:failed:$id',
      action: id.isEmpty
          ? null
          : {
              'type': 'navigate',
              'label': '查看实例',
              'path': '/browser/detail/$id',
            },
    );
  }

  void _onBridgeDied(Map<String, dynamic> data) {
    final proxyIds =
        (data['proxyIds'] as List?)
            ?.where((item) => '$item'.isNotEmpty)
            .join('、') ??
        '';
    final profileIds =
        (data['profileIds'] as List?)
            ?.where((item) => '$item'.isNotEmpty)
            .join('、') ??
        '';
    final target = proxyIds.isNotEmpty ? proxyIds : '${data['key'] ?? ''}';
    final profileHint = profileIds.isNotEmpty ? '，影响实例 $profileIds' : '';
    _add(
      type: 'warning',
      title: '连接池节点失效',
      message: '代理节点 $target 连接中断$profileHint，相关实例可能无法访问网络',
      source: 'runtime',
      dedupeKey: 'proxy:bridge:died:${data['key'] ?? ''}',
      action: {
        'type': 'navigate',
        'label': '查看代理池',
        'path': '/browser/proxy-pool',
      },
    );
  }

  void _add({
    required String type,
    required String title,
    required String message,
    required String source,
    String? dedupeKey,
    Map<String, dynamic>? action,
  }) {
    if (!_historyEnabled() || message.trim().isEmpty) return;
    final now = DateTime.now();
    if (dedupeKey != null &&
        notifications.any((item) {
          if (item['dedupeKey'] != dedupeKey) return false;
          final created = DateTime.tryParse('${item['createdAt'] ?? ''}');
          return created != null &&
              now.difference(created).inMilliseconds < 10000;
        }))
      return;
    final time =
        '${now.year}/${_pad(now.month)}/${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';
    notifications.insert(0, {
      'id': now.microsecondsSinceEpoch.toRadixString(36),
      'type': type,
      'title': title,
      'message': message,
      'source': source,
      if (dedupeKey != null) 'dedupeKey': dedupeKey,
      'persistent': true,
      if (action != null) 'action': action,
      'time': time,
      'createdAt': now.toIso8601String(),
      'read': false,
    });
    if (notifications.length > _maxNotifications) {
      notifications.removeRange(_maxNotifications, notifications.length);
    }
    _save();
    notifyListeners();
  }

  bool _historyEnabled() {
    try {
      final raw = AppBridge.readStorage('app_settings');
      if (raw.isEmpty) return true;
      final settings = jsonDecode(raw);
      return settings is! Map || settings['enableNotifications'] != false;
    } catch (_) {
      return true;
    }
  }

  void markRead(String id) {
    for (final item in notifications) {
      if (item['id'] == id) item['read'] = true;
    }
    _save();
    notifyListeners();
  }

  void markAllRead() {
    for (final item in notifications) {
      item['read'] = true;
    }
    _save();
    notifyListeners();
  }

  void clear() {
    notifications.clear();
    _save();
    notifyListeners();
  }

  void _save() {
    try {
      AppBridge.writeStorage(
        _storageKey,
        jsonEncode({
          'state': {'notifications': notifications},
          'version': 1,
        }),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final remove in _removeListeners) {
      remove();
    }
    super.dispose();
  }
}

String _pad(int value) => value.toString().padLeft(2, '0');
