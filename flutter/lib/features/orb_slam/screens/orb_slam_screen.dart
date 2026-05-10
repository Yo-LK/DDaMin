import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OrbSlamScreen extends StatefulWidget {
  const OrbSlamScreen({super.key});

  @override
  State<OrbSlamScreen> createState() => _OrbSlamScreenState();
}

class _OrbSlamScreenState extends State<OrbSlamScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _errorMessage = '카메라 초기화 실패: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 촬영'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildCameraView()),
          Expanded(child: _buildMapPlaceholder()),
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

  Widget _buildMapPlaceholder() {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: Colors.white38),
            SizedBox(height: 12),
            Text(
              'ORB-SLAM 맵 준비 중',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}