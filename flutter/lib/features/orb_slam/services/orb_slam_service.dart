import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:web_socket_channel/web_socket_channel.dart';

class OrbSlamService {
  WebSocketChannel? _channel;
  bool _isStreaming = false;
  DateTime? _lastFrameTime;
  static const int _frameIntervalMs = 100; // 10fps

  Stream<dynamic>? get resultStream => _channel?.stream;

  Future<void> connect(String wsUrl) async {
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await _channel!.ready;
  }

  void startStreaming(CameraController controller) {
    if (_isStreaming) return;
    _isStreaming = true;
    controller.startImageStream(_onFrame);
  }

  void stopStreaming(CameraController controller) {
    if (!_isStreaming) return;
    _isStreaming = false;
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
      _channel?.sink.add(jpeg);
    }
  }

  Uint8List? _convertToJpeg(CameraImage cameraImage) {
    try {
      final plane = cameraImage.planes[0];
      final imgFrame = img.Image.fromBytes(
        width: cameraImage.width,
        height: cameraImage.height,
        bytes: plane.bytes.buffer,
        format: img.Format.uint8,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      return img.encodeJpg(imgFrame, quality: 70);
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnect() async {
    _isStreaming = false;
    await _channel?.sink.close();
    _channel = null;
  }
}