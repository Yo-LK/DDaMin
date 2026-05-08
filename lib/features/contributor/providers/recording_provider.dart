// lib/features/contributor/providers/recording_provider.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../../../data/local/recording_storage.dart';
import '../../../data/models/recording_session_model.dart';
import '../../../network/network_monitor.dart';
import '../../../network/upload_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class RecordingState {
  final bool isRecording;
  final RecordingSession? session;
  final List<GpsPoint> gpsPoints;
  final NetworkType networkType;
  final String? errorMessage;

  const RecordingState({
    this.isRecording = false,
    this.session,
    this.gpsPoints = const [],
    this.networkType = NetworkType.none,
    this.errorMessage,
  });

  RecordingState copyWith({
    bool? isRecording,
    RecordingSession? session,
    List<GpsPoint>? gpsPoints,
    NetworkType? networkType,
    String? errorMessage,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      session: session ?? this.session,
      gpsPoints: gpsPoints ?? this.gpsPoints,
      networkType: networkType ?? this.networkType,
      errorMessage: errorMessage,
    );
  }
}

class RecordingNotifier extends StateNotifier<RecordingState> {
  CameraController? _cameraController;
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<NetworkType>? _networkSub;
  CancelToken? _cancelToken;
  final _uploadClient = UploadClient();

  RecordingNotifier() : super(const RecordingState()) {
    _listenNetwork();
  }

  void _listenNetwork() {
    _networkSub = Connectivity()
        .onConnectivityChanged
        .map(toNetworkType)
        .cast<NetworkType>()
        .listen((networkType) async {
      state = state.copyWith(networkType: networkType);
      if (networkType != NetworkType.none &&
          state.session?.uploadStatus == UploadStatus.buffering) {
        await _startUpload();
      }
    });
  }

  Future<void> initCamera(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _cameraController!.initialize();
  }

  Future<void> startRecording() async {
    if (_cameraController == null || state.isRecording) return;

    final sessionId = const Uuid().v4();
    final mp4Path = await RecordingStorage.mp4Path(sessionId);

    await _cameraController!.startVideoRecording();
    _startGps(sessionId);

    state = state.copyWith(
      isRecording: true,
      gpsPoints: [],
      session: RecordingSession(
        sessionId: sessionId,
        startedAt: DateTime.now(),
        mp4Path: mp4Path,
        uploadStatus: _uploadStatusByNetwork(state.networkType),
      ),
    );
  }

  Future<void> stopRecording() async {
    if (!state.isRecording || _cameraController == null) return;

    final file = await _cameraController!.stopVideoRecording();
    await _gpsSub?.cancel();

    final session = state.session!;
    final gpsPath = await RecordingStorage.gpsJsonPath(session.sessionId);
    await RecordingStorage.saveGpsPoints(session.sessionId, state.gpsPoints);

    final updatedSession = session.copyWith(
      mp4Path: file.path,
      gpsJsonPath: gpsPath,
      uploadStatus: state.networkType != NetworkType.none
          ? UploadStatus.pendingUpload
          : UploadStatus.buffering,
    );

    state = state.copyWith(isRecording: false, session: updatedSession);

    if (state.networkType != NetworkType.none) {
      await _startUpload();
    }
  }

  Future<void> _startUpload() async {
    final session = state.session;
    if (session?.mp4Path == null || session?.gpsJsonPath == null) return;

    _cancelToken = CancelToken();
    state = state.copyWith(
      session: session!.copyWith(uploadStatus: UploadStatus.uploading),
    );

    try {
      await _uploadClient.uploadSession(
        sessionId: session.sessionId,
        mp4Path: session.mp4Path!,
        gpsJsonPath: session.gpsJsonPath!,
        onProgress: (uploaded, total) {
          state = state.copyWith(
            session: state.session?.copyWith(
              uploadedBytes: uploaded,
              totalBytes: total,
            ),
          );
        },
        cancelToken: _cancelToken,
      );

      await RecordingStorage.deleteSession(session.sessionId);
      state = state.copyWith(
        session: state.session?.copyWith(uploadStatus: UploadStatus.done),
      );
    } catch (e) {
      state = state.copyWith(
        session: state.session?.copyWith(uploadStatus: UploadStatus.error),
        errorMessage: e.toString(),
      );
    }
  }

  void _startGps(String sessionId) {
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      final point = GpsPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(gpsPoints: [...state.gpsPoints, point]);
    });
  }

  UploadStatus _uploadStatusByNetwork(NetworkType network) {
    return network != NetworkType.none
        ? UploadStatus.streaming
        : UploadStatus.buffering;
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _gpsSub?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }
}

final recordingProvider =
    StateNotifierProvider<RecordingNotifier, RecordingState>((ref) {
  return RecordingNotifier();
});
