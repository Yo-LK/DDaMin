// lib/features/history/providers/history_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/recording_storage.dart';
import '../../../data/models/recording_session_model.dart';
import '../../../network/upload_client.dart';

class HistoryNotifier extends StateNotifier<AsyncValue<List<RecordingSession>>> {
  HistoryNotifier() : super(const AsyncValue.loading()) {
    loadSessions();
  }

  Future<void> loadSessions() async {
    state = const AsyncValue.loading();
    try {
      final sessionIds = await RecordingStorage.pendingSessions();
      final sessions = sessionIds.map((id) {
        return RecordingSession(
          sessionId: id,
          startedAt: _parseTimestampFromId(id),
          mp4Path: null,
          gpsJsonPath: null,
          uploadStatus: UploadStatus.buffering,
        );
      }).toList();
      state = AsyncValue.data(sessions);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> uploadSession(String sessionId) async {
    _updateSession(sessionId, UploadStatus.uploading, 0, 0);

    try {
      final mp4 = await RecordingStorage.mp4Path(sessionId);
      final gps = await RecordingStorage.gpsJsonPath(sessionId);

      await UploadClient().uploadSession(
        sessionId: sessionId,
        mp4Path: mp4,
        gpsJsonPath: gps,
        onProgress: (uploaded, total) {
          _updateSession(sessionId, UploadStatus.uploading, uploaded, total);
        },
      );

      await RecordingStorage.deleteSession(sessionId);
      _updateSession(sessionId, UploadStatus.done, 0, 0);
    } catch (_) {
      _updateSession(sessionId, UploadStatus.error, 0, 0);
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await RecordingStorage.deleteSession(sessionId);
    final sessions = state.value ?? [];
    state = AsyncValue.data(
      sessions.where((s) => s.sessionId != sessionId).toList(),
    );
  }

  void _updateSession(
    String sessionId,
    UploadStatus status,
    int uploaded,
    int total,
  ) {
    final sessions = state.value ?? [];
    state = AsyncValue.data(
      sessions.map((s) {
        if (s.sessionId != sessionId) return s;
        return s.copyWith(
          uploadStatus: status,
          uploadedBytes: uploaded,
          totalBytes: total,
        );
      }).toList(),
    );
  }

  /// 세션 ID에서 생성 시각 파싱 (UUID v4는 타임스탬프 없음 → 파일 stat으로 대체 불가시 현재 시각)
  DateTime _parseTimestampFromId(String id) => DateTime.now();
}

final historyProvider = StateNotifierProvider<HistoryNotifier,
    AsyncValue<List<RecordingSession>>>((ref) {
  return HistoryNotifier();
});
