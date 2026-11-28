bool isProxySpeedFresh(DateTime? testedAt, Duration maxAge) {
  if (testedAt == null) return false;
  final age = DateTime.now().difference(testedAt);
  return age >= const Duration(minutes: -1) && age <= maxAge;
}

class ProxySpeedResults {
  final _results =
      <String, ({DateTime testedAt, int? latency, String? error})>{};
  Duration maxAge = const Duration(minutes: 30);

  void record(String key, Map result) {
    final testedAt =
        DateTime.tryParse('${result['testedAt'] ?? ''}') ?? DateTime.now();
    if (_results[key]?.testedAt.isAfter(testedAt) == true) return;
    final latency = result['latencyMs'];
    final ok = result['ok'] == true && latency is num;
    final error = '${result['error'] ?? ''}'.trim();
    _results[key] = (
      testedAt: testedAt,
      latency: ok ? latency.toInt() : null,
      error: ok
          ? null
          : error.isEmpty
          ? '连接失败'
          : error,
    );
  }

  ({int? latency, String? error}) current(String key) {
    final result = _results[key];
    if (result == null || !isProxySpeedFresh(result.testedAt, maxAge)) {
      return (latency: null, error: null);
    }
    return (latency: result.latency, error: result.error);
  }
}
