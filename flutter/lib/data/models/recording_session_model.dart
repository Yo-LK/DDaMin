// lib/data/models/recording_session_model.dart

enum UploadStatus { idle, streaming, buffering, pendingUpload, uploading, done, error }

class GpsPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime timestamp;

  const GpsPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lng': longitude,
        'alt': altitude,
        'ts': timestamp.toIso8601String(),
      };
}

class RecordingSession {
  final String sessionId;
  final DateTime startedAt;
  final String? mp4Path;
  final String? gpsJsonPath;
  final UploadStatus uploadStatus;
  final int uploadedBytes;
  final int totalBytes;

  const RecordingSession({
    required this.sessionId,
    required this.startedAt,
    this.mp4Path,
    this.gpsJsonPath,
    this.uploadStatus = UploadStatus.idle,
    this.uploadedBytes = 0,
    this.totalBytes = 0,
  });

  double get uploadProgress =>
      totalBytes == 0 ? 0 : uploadedBytes / totalBytes;

  RecordingSession copyWith({
    String? mp4Path,
    String? gpsJsonPath,
    UploadStatus? uploadStatus,
    int? uploadedBytes,
    int? totalBytes,
  }) {
    return RecordingSession(
      sessionId: sessionId,
      startedAt: startedAt,
      mp4Path: mp4Path ?? this.mp4Path,
      gpsJsonPath: gpsJsonPath ?? this.gpsJsonPath,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }
}
