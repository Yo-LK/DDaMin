// lib/data/local/recording_storage.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/recording_session_model.dart';

class RecordingStorage {
  static Future<String> _sessionDir(String sessionId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sessions/$sessionId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> mp4Path(String sessionId) async {
    final dir = await _sessionDir(sessionId);
    return '$dir/video.mp4';
  }

  static Future<String> gpsJsonPath(String sessionId) async {
    final dir = await _sessionDir(sessionId);
    return '$dir/gps.json';
  }

  static Future<void> saveGpsPoints(
    String sessionId,
    List<GpsPoint> points,
  ) async {
    final path = await gpsJsonPath(sessionId);
    final file = File(path);
    final data = json.encode(points.map((p) => p.toJson()).toList());
    await file.writeAsString(data);
  }

  static Future<int> sessionSize(String sessionId) async {
    final dir = await _sessionDir(sessionId);
    final mp4 = File('$dir/video.mp4');
    final gps = File('$dir/gps.json');
    int size = 0;
    if (await mp4.exists()) size += await mp4.length();
    if (await gps.exists()) size += await gps.length();
    return size;
  }

  static Future<void> deleteSession(String sessionId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sessions/$sessionId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<List<String>> pendingSessions() async {
    final base = await getApplicationDocumentsDirectory();
    final sessionsDir = Directory('${base.path}/sessions');
    if (!await sessionsDir.exists()) return [];
    return sessionsDir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split('/').last)
        .toList();
  }
}
