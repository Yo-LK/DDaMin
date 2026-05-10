import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OrbSlamScreen extends StatelessWidget {
  const OrbSlamScreen({super.key});

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
      body: const Center(
        child: Text('ORB-SLAM 준비 중'),
      ),
    );
  }
}