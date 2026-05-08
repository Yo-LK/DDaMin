// lib/data/local/storage_monitor.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

const int kStorageWarningBytes = 500 * 1024 * 1024;  // 500MB
const int kStorageCriticalBytes = 1024 * 1024 * 1024; // 1GB

class StorageInfo {
  final int usedBytes;
  final int warningThreshold;
  final int criticalThreshold;

  const StorageInfo({
    required this.usedBytes,
    required this.warningThreshold,
    required this.criticalThreshold,
  });

  bool get isWarning => usedBytes >= warningThreshold;
  bool get isCritical => usedBytes >= criticalThreshold;

  String get usedFormatted => _format(usedBytes);
  String get warningFormatted => _format(warningThreshold);

  static String _format(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)}KB';
  }
}

Future<int> _calcSessionsSize() async {
  final base = await getApplicationDocumentsDirectory();
  final sessionsDir = Directory('${base.path}/sessions');
  if (!await sessionsDir.exists()) return 0;

  int total = 0;
  await for (final entity in sessionsDir.list(recursive: true)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}

final storageMonitorProvider = StreamProvider<StorageInfo>((ref) {
  return Stream.periodic(const Duration(seconds: 5))
      .asyncMap((_) async {
    final used = await _calcSessionsSize();
    return StorageInfo(
      usedBytes: used,
      warningThreshold: kStorageWarningBytes,
      criticalThreshold: kStorageCriticalBytes,
    );
  });
});
