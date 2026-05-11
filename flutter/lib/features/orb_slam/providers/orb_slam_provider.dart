import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/orb_slam_service.dart';

enum OrbSlamStatus { idle, connecting, streaming, error }

class OrbSlamState {
  final OrbSlamStatus status;
  final String? errorMessage;
  final Uint8List? lastResult;

  const OrbSlamState({
    this.status = OrbSlamStatus.idle,
    this.errorMessage,
    this.lastResult,
  });

  OrbSlamState copyWith({
    OrbSlamStatus? status,
    String? errorMessage,
    Uint8List? lastResult,
  }) =>
      OrbSlamState(
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        lastResult: lastResult ?? this.lastResult,
      );
}

class OrbSlamNotifier extends StateNotifier<OrbSlamState> {
  final OrbSlamService _service = OrbSlamService();
  StreamSubscription? _resultSub;

  OrbSlamNotifier() : super(const OrbSlamState());

  Future<void> startSession(CameraController controller, String wsUrl) async {
    state = state.copyWith(status: OrbSlamStatus.connecting);
    try {
      await _service.connect(wsUrl);

      // 변경 후
      _resultSub = _service.resultStream?.listen(
        (data) {
          if (!mounted) return;
          if (data is List<int>) {
            state = state.copyWith(
              lastResult: Uint8List.fromList(data),
              status: OrbSlamStatus.streaming,
            );
          } else {
            state = state.copyWith(status: OrbSlamStatus.streaming);
          }
        },
        onError: (e) {
          if (!mounted) return;
          state = state.copyWith(
            status: OrbSlamStatus.error,
            errorMessage: '연결 오류: $e',
          );
        },
        onDone: () {
          if (!mounted) return;
          state = state.copyWith(status: OrbSlamStatus.idle);
        },
      );

      _service.startStreaming(controller);
      if (!mounted) return;
      state = state.copyWith(status: OrbSlamStatus.streaming);
    } catch (e) {
      state = state.copyWith(
        status: OrbSlamStatus.error,
        errorMessage: '연결 실패: $e',
      );
    }
  }

  Future<void> stopSession(CameraController controller) async {
    _service.stopStreaming(controller);
    await _resultSub?.cancel();
    await _service.disconnect();
    state = state.copyWith(status: OrbSlamStatus.idle);
  }

  @override
  void dispose() {
    _resultSub?.cancel();
    _service.disconnect();
    super.dispose();
  }
}

final orbSlamProvider =
    StateNotifierProvider<OrbSlamNotifier, OrbSlamState>(
  (ref) => OrbSlamNotifier(),
);