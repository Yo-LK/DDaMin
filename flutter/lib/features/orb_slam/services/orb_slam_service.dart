import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

class OrbSlamService {
  WebSocketChannel? _channel;
  bool _isStreaming = false;
  DateTime? _lastFrameTime;
  static const int _frameIntervalMs = 100;

  int _frameNumber = 0;

  final List<_ImuSample> _imuBuffer = [];
  double _gx = 0, _gy = 0, _gz = 0;
  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;

  Stream<dynamic>? get resultStream => _channel?.stream;

  Future<void> connect(String wsUrl) async {
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await _channel!.ready;
  }

  void _startImu() {
    _gyroSub = gyroscopeEventStream(samplingPeriod: const Duration(milliseconds: 20),).listen(
      (e) {
        _gx = e.x; _gy = e.y; _gz = e.z;
      },
      onError: (e) => print('[IMU] gyro error: $e'),
    );
    _accelSub = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 20),).listen(
      (e) {
        _imuBuffer.add(_ImuSample(
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
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
    _startImu();
    controller.startImageStream(_onFrame);
  }

  void stopStreaming(CameraController controller) {
    if (!_isStreaming) return;
    _isStreaming = false;
    _stopImu();
    if (controller.value.isStreamingImages) {
      controller.stopImageStream();
    }
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_lastFrameTime != null &&
        now.difference(_lastFrameTime!).inMilliseconds < _frameIntervalMs) {
      return;
    }
    _lastFrameTime = now;

    final jpeg = _convertToJpeg(image);
    if (jpeg != null) {
      final payload = _buildPayload(jpeg: jpeg);
      _channel?.sink.add(payload);
    }
  }

  /// 패킷 구조:
  /// [2B: IMU 개수 N (uint16)]
  /// [N × 32B: IMU 엔트리 (float64 ts, float32 ax,ay,az, float32 gx,gy,gz)]
  /// [나머지: JPEG bytes]
  // _buildPayload 교체
/// [4B: frame_number (uint32)][2B: IMU count N][N × 32B IMU entries][JPEG]
  Uint8List _buildPayload({required Uint8List jpeg}) {
    print('[Frame] frameNumber=$_frameNumber, imuBufferSize=${_imuBuffer.length}');
    final samples = List<_ImuSample>.from(_imuBuffer);
    _imuBuffer.clear();

    final imuCount  = samples.length;
    final headerSize = 4 + 2 + imuCount * 32;
    final result    = Uint8List(headerSize + jpeg.length);
    final bd        = ByteData.view(result.buffer);

    bd.setUint32(0, _frameNumber, Endian.little);
    bd.setUint16(4, imuCount,     Endian.little);

    int offset = 6;
    for (final s in samples) {
      bd.setFloat64(offset, s.timestampMs, Endian.little); offset += 8;
      bd.setFloat32(offset, s.ax,          Endian.little); offset += 4;
      bd.setFloat32(offset, s.ay,          Endian.little); offset += 4;
      bd.setFloat32(offset, s.az,          Endian.little); offset += 4;
      bd.setFloat32(offset, s.gx,          Endian.little); offset += 4;
      bd.setFloat32(offset, s.gy,          Endian.little); offset += 4;
      bd.setFloat32(offset, s.gz,          Endian.little); offset += 4;
    }

    result.setRange(headerSize, result.length, jpeg);
    _frameNumber++;
    return result;
  }

  Uint8List? _convertToJpeg(CameraImage cameraImage) {
    try {
      final plane  = cameraImage.planes[0];
      final width  = cameraImage.width;
      final height = cameraImage.height;
      final bytesPerRow = plane.bytesPerRow;
      // print('[CAM] planes=${cameraImage.planes.length}, w=$width, h=$height, bytesPerRow=$bytesPerRow, expected=${width * 4}');

      Uint8List bytes;
      if (bytesPerRow == width * 4) {
        bytes = plane.bytes;
      } else {
        bytes = Uint8List(width * height * 4);
        for (int i = 0; i < height; i++) {
          bytes.setRange(
            i * width * 4,
            (i + 1) * width * 4,
            plane.bytes,
            i * bytesPerRow,
          );
        }
      }

      // BGRA → RGBA 명시적 채널 스왑
      final rgbaBytes = Uint8List(width * height * 4);
      for (int i = 0; i < width * height; i++) {
        rgbaBytes[i * 4 + 0] = bytes[i * 4 + 2]; // R
        rgbaBytes[i * 4 + 1] = bytes[i * 4 + 1]; // G
        rgbaBytes[i * 4 + 2] = bytes[i * 4 + 0]; // B
        rgbaBytes[i * 4 + 3] = bytes[i * 4 + 3]; // A
      }

      final imgFrame = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaBytes.buffer,
        format: img.Format.uint8,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return img.encodeJpg(imgFrame, quality: 70);
    } catch (e, st) {
      print('[CAM] convert error: $e\n$st');
      return null;
    }
  }

  Future<void> disconnect() async {
    _isStreaming = false;
    _stopImu();
    await _channel?.sink.close();
    _channel = null;
  }
}