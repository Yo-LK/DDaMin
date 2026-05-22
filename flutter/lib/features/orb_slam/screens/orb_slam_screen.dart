import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/orb_slam_provider.dart';

class OrbSlamScreen extends ConsumerStatefulWidget {
  const OrbSlamScreen({super.key});

  @override
  ConsumerState<OrbSlamScreen> createState() => _OrbSlamScreenState();
}

class _OrbSlamScreenState extends ConsumerState<OrbSlamScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  String? _errorMessage;
  OrbSlamNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(orbSlamProvider.notifier);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMessage = '카메라를 찾을 수 없습니다.');
        return;
      }
      _controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _errorMessage = '카메라 초기화 실패: $e');
    }
  }

  @override
  void dispose() {
    if (_controller != null && _notifier != null) {
      _notifier!.stopSession(_controller!);
    }
    _controller?.dispose();
    super.dispose();
  }

  void _toggleStreaming() {
    final status = ref.read(orbSlamProvider).status;
    final notifier = ref.read(orbSlamProvider.notifier);
    final wsUrl = dotenv.env['ORB_SLAM_WS_URL'] ?? '';
    if (_controller == null) return;

    if (status == OrbSlamStatus.streaming) {
      notifier.stopSession(_controller!);
    } else {
      notifier.startSession(_controller!, wsUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orbState = ref.watch(orbSlamProvider);

    ref.listen(orbSlamProvider, (_, next) {
      if (next.status == OrbSlamStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 촬영'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_controller != null &&
                orbState.status == OrbSlamStatus.streaming) {
              ref.read(orbSlamProvider.notifier).stopSession(_controller!);
            }
            context.go('/home');
          },
        ),
        actions: [
          if (_isInitialized)
            IconButton(
              icon: Icon(
                orbState.status == OrbSlamStatus.streaming
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outlined,
              ),
              onPressed: _toggleStreaming,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildCameraView()),
          Expanded(child: _buildResultView(orbState)),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }
    if (!_isInitialized || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return CameraPreview(_controller!);
  }

  Widget _buildResultView(OrbSlamState state) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: switch (state.status) {
          OrbSlamStatus.idle => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, size: 48, color: Colors.white38),
                SizedBox(height: 12),
                Text('▶ 버튼을 눌러 스트리밍 시작',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ],
            ),
          OrbSlamStatus.connecting => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white54),
                SizedBox(height: 12),
                Text('서버 연결 중...',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          OrbSlamStatus.streaming => state.lastResult != null
              ? Image.memory(state.lastResult!, fit: BoxFit.contain)
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.greenAccent),
                    SizedBox(height: 12),
                    Text('프레임 전송 중...',
                        style:
                            TextStyle(color: Colors.greenAccent, fontSize: 14)),
                  ],
                ),
          OrbSlamStatus.error => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text(
                  state.errorMessage ?? '오류 발생',
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
        },
      ),
    );
  }
}