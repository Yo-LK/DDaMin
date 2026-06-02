import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'frame_filter_service.dart';

class _ImuSample {
  final double timestampMs;
  final double ax, ay, az;
  final double gx, gy, gz;

  _ImuSample({
    required this.timestampMs,
    required this.ax, required this.ay, required this.az,
    required this.gx, required this.gy, required this.gz,
  });
}

class _FrameEntry {
  final DateTime timestamp;
  final Uint8List grayBytes; // 320×240 grayscale — 블러 점수 계산용
  final Uint8List bgraBytes; // 원본 BGRA — JPEG 변환용
  final int width;
  final int height;

  _FrameEntry({
    required this.timestamp,
    required this.grayBytes,
    required this.bgraBytes,
    required this.width,
    required this.height,
  });
}

class OrbSlamService {
  WebSocketChannel? _channel;
  bool _isStreaming = false;
  int _frameNumber = 0;

  // IMU
  final List<_ImuSample> _imuBuffer = [];
  double _gx = 0, _gy = 0, _gz = 0;
  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;

  // 프레임 버퍼 파이프라인
  final List<_FrameEntry> _frameQueue = [];
  Timer? _sendTimer;
  Uint8List? _lastSentGray;
  DateTime? _streamingStartTime;

  static const int _maxQueueSize = 15;
  static const int _sendIntervalMs = 66;

  Stream<dynamic>? get resultStream => _channel?.stream;

  Future<void> connect(String wsUrl) async {
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await _channel!.ready;
  }

  void _startImu() {
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(
      (e) { _gx = e.x; _gy = e.y; _gz = e.z; },
      onError: (e) => print('[IMU] gyro error: $e'),
    );
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(
      (e) {
        _imuBuffer.add(_ImuSample(
          timestampMs: DateTime.now().microsecondsSinceEpoch / 1000.0,
          ax: e.x, ay: e.y, az: e.z,
          gx: _gx, gy: _gy, gz: _gz,
        ));
      },
      onError: (e) => print('[IMU] accel error: $e'),
    );
  }

  void _stopImu() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _imuBuffer.clear();
  }

  void startStreaming(CameraController controller) {
    if (_isStreaming) return;
    _isStreaming = true;
    _lastSentGray = null;
    _frameQueue.clear();
    _streamingStartTime = DateTime.now();
    _startImu();
    _sendTimer = Timer.periodic(
      const Duration(milliseconds: _sendIntervalMs),
      (_) => _processBuffer(),
    );
    controller.startImageStream(_onFrame);
  }

  void stopStreaming(CameraController controller) {
    if (!_isStreaming) return;
    _isStreaming = false;
    _sendTimer?.cancel();
    _sendTimer = null;
    _stopImu();
    _frameQueue.clear();
    if (controller.value.isStreamingImages) {
      controller.stopImageStream();
    }
  }

  // ── ① 프레임 수집 ──────────────────────────────────────────────
  void _onFrame(CameraImage image) {
    if (!_isStreaming) return;

    final plane = image.planes[0];
    final w = image.width;
    final h = image.height;
    final bpr = plane.bytesPerRow;

    // CameraImage 데이터는 콜백 반환 후 재사용될 수 있으므로 즉시 복사
    final Uint8List bgraBytes;
    if (bpr == w * 4) {
      bgraBytes = Uint8List.fromList(plane.bytes);
    } else {
      bgraBytes = Uint8List(w * h * 4);
      for (int i = 0; i < h; i++) {
        bgraBytes.setRange(i * w * 4, (i + 1) * w * 4, plane.bytes, i * bpr);
      }
    }

    final grayBytes = FrameFilterService.extractGrayBytes(
      bgraBytes: bgraBytes,
      srcWidth: w,
      srcHeight: h,
    );
    if (grayBytes == null) return;

    _frameQueue.add(_FrameEntry(
      timestamp: DateTime.now(),
      grayBytes: grayBytes,
      bgraBytes: bgraBytes,
      width: w,
      height: h,
    ));

    if (_frameQueue.length > _maxQueueSize) _frameQueue.removeAt(0);
  }

  // ── ② 검사 및 폐기 ─────────────────────────────────────────────
  void _processBuffer() {
    if (!_isStreaming) return;

    final buffer = List<_FrameEntry>.from(_frameQueue);
    _frameQueue.clear();

    if (buffer.isEmpty) return;

    final bool isInitializing = 
        DateTime.now().difference(_streamingStartTime!).inSeconds < 15;

    // Step 1: 라플라시안 분산 → 블러 임계값 미달 제거
    final candidates = <({_FrameEntry entry, double score})>[];
    for (final entry in buffer) {
      final score = FrameFilterService.laplacianVariance(entry.grayBytes);

      final threshold = isInitializing ? 0.0 : kBlurThreshold;
      if (score >= threshold) {
        candidates.add((entry: entry, score: score));
      }
    }

    if (candidates.isEmpty) {
      print('[Filter] ${buffer.length}장 전부 블러 탈락');
      return;
    }

    // Step 2: 가장 선명한 프레임 선택
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;

    // Step 3: 이전 전송 프레임과 히스토그램 유사도 비교
    if (!isInitializing && _lastSentGray != null) {
      final sim = FrameFilterService.histogramSimilarity(
          best.entry.grayBytes, _lastSentGray!);
      if (sim >= kSimilarityThreshold) {
        print('[Filter] 중복 탈락 (유사도: ${sim.toStringAsFixed(3)})');
        return;
      }
    }

    _lastSentGray = best.entry.grayBytes;

    // _processBuffer 내부 전송부 수정
    final jpeg =
        _bgraToJpeg(best.entry.bgraBytes, best.entry.width, best.entry.height);
    if (jpeg != null) {
      // ⭕ 타임스탬프 파라미터 삭제, jpeg만 보냅니다.
      _channel?.sink.add(_buildPayload(jpeg: jpeg));

      final modeTag = isInitializing ? "[Init Mode]" : "[Filter]";
      print('$modeTag 전송 #$_frameNumber | '
          'score=${best.score.toStringAsFixed(1)} | '
          '통과 ${candidates.length}/${buffer.length}장');
    }
  }

  // ⭕ 깔끔한 6바이트 헤더 구조로 원상 복구
  Uint8List _buildPayload({required Uint8List jpeg}) {
    final samples = List<_ImuSample>.from(_imuBuffer);
    _imuBuffer.clear();

    final imuCount = samples.length;
    // 🔥 8이 빠진 정확한 6바이트 베이스 할당
    final headerSize = 4 + 2 + imuCount * 32;
    final result = Uint8List(headerSize + jpeg.length);
    final bd = ByteData.view(result.buffer);

    bd.setUint32(0, _frameNumber, Endian.little);
    bd.setUint16(4, imuCount, Endian.little);

    int offset = 6;
    for (final s in samples) {
      bd.setFloat64(offset, s.timestampMs, Endian.little); offset += 8;
      bd.setFloat32(offset, s.ax, Endian.little); offset += 4;
      bd.setFloat32(offset, s.ay, Endian.little); offset += 4;
      bd.setFloat32(offset, s.az, Endian.little); offset += 4;
      bd.setFloat32(offset, s.gx, Endian.little); offset += 4;
      bd.setFloat32(offset, s.gy, Endian.little); offset += 4;
      bd.setFloat32(offset, s.gz, Endian.little); offset += 4;
    }

    result.setRange(headerSize, result.length, jpeg);
    _frameNumber++;
    return result;
  }

  Uint8List? _bgraToJpeg(Uint8List bgraBytes, int width, int height) {
    try {
      final rgbaBytes = Uint8List(width * height * 4);
      for (int i = 0; i < width * height; i++) {
        rgbaBytes[i * 4 + 0] = bgraBytes[i * 4 + 2]; // R
        rgbaBytes[i * 4 + 1] = bgraBytes[i * 4 + 1]; // G
        rgbaBytes[i * 4 + 2] = bgraBytes[i * 4 + 0]; // B
        rgbaBytes[i * 4 + 3] = bgraBytes[i * 4 + 3]; // A
      }

      final imgFrame = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaBytes.buffer,
        format: img.Format.uint8,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return img.encodeJpg(imgFrame, quality: 50);
    } catch (e, st) {
      print('[CAM] convert error: $e\n$st');
      return null;
    }
  }

  Future<void> disconnect() async {
    _isStreaming = false;
    _sendTimer?.cancel();
    _sendTimer = null;
    _stopImu();
    _frameQueue.clear();
    _lastSentGray = null;
    await _channel?.sink.close();
    _channel = null;
  }
}