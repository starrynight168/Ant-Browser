String _twoDigits(int n) => n.toString().padLeft(2, '0');

String formatDateTime(
  dynamic raw, {
  bool includeSeconds = true,
  String fallback = '-',
  bool returnRawOnInvalid = false,
}) {
  if (raw is DateTime) {
    final local = raw.toLocal();
    final base =
        '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    return includeSeconds ? '$base:${_twoDigits(local.second)}' : base;
  }
  final text = '${raw ?? ''}'.trim();
  if (text.isEmpty) return fallback;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return returnRawOnInvalid ? text : fallback;
  final local = parsed.toLocal();
  final base =
      '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  return includeSeconds ? '$base:${_twoDigits(local.second)}' : base;
}

String formatShortDateTime(
  dynamic raw, {
  String fallback = '-',
  bool returnRawOnInvalid = false,
}) {
  if (raw is DateTime) {
    final local = raw.toLocal();
    return '${_twoDigits(local.month)}-${_twoDigits(local.day)} '
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  }
  final text = '${raw ?? ''}'.trim();
  if (text.isEmpty) return fallback;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return returnRawOnInvalid ? text : fallback;
  final local = parsed.toLocal();
  return '${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String formatByteSize(dynamic rawBytes, {String fallback = '-'}) {
  if (rawBytes == null) return fallback;
  final bytes = rawBytes is num
      ? rawBytes.toDouble()
      : double.tryParse('$rawBytes'.trim());
  if (bytes == null || bytes.isNaN || bytes.isInfinite || bytes < 0) {
    return fallback;
  }
  if (bytes == 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final digits = unitIndex == 0
      ? 0
      : (value >= 100 ? 0 : (value >= 10 ? 1 : 2));
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String formatDurationMs(dynamic rawMs) {
  final ms = (rawMs is num)
      ? rawMs.toInt()
      : int.tryParse('${rawMs ?? ''}') ?? 0;
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}
