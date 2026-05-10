// lib/features/contributor/screens/recording_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/video_upload_provider.dart';
import 'package:go_router/go_router.dart';

class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadState = ref.watch(videoUploadProvider);
    final notifier = ref.read(videoUploadProvider.notifier);

    ref.listen(videoUploadProvider, (_, next) {
      if (next.status == VideoUploadStatus.error &&
          next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('영상 업로드'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilePickerCard(
              state: uploadState,
              onPick: notifier.pickVideo,
            ),
            const SizedBox(height: 16),

            // 업로드 방식 선택
            _UploadModeSelector(
              mode: uploadState.uploadMode,
              enabled: uploadState.status != VideoUploadStatus.uploading,
              onChanged: notifier.setUploadMode,
            ),

            const SizedBox(height: 16),

            if (uploadState.status == VideoUploadStatus.uploading ||
                uploadState.status == VideoUploadStatus.done)
              _UploadProgressCard(state: uploadState),

            const Spacer(),
            _ActionButtons(
              state: uploadState,
              onUpload: notifier.upload,
              onCancel: notifier.cancelUpload,
              onReset: notifier.reset,
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadModeSelector extends StatelessWidget {
  final UploadMode mode;
  final bool enabled;
  final void Function(UploadMode) onChanged;

  const _UploadModeSelector({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('전송 방식', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 16),
        Expanded(
          child: SegmentedButton<UploadMode>(
            segments: const [
              ButtonSegment(
                value: UploadMode.single,
                label: Text('통파일'),
                icon: Icon(Icons.file_upload_outlined),
              ),
              ButtonSegment(
                value: UploadMode.chunked,
                label: Text('청크'),
                icon: Icon(Icons.dataset_outlined),
              ),
            ],
            selected: {mode},
            onSelectionChanged: enabled
                ? (selected) => onChanged(selected.first)
                : null,
          ),
        ),
      ],
    );
  }
}

class _FilePickerCard extends StatelessWidget {
  final VideoUploadState state;
  final VoidCallback onPick;

  const _FilePickerCard({required this.state, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final hasFile = state.filePath != null;

    return GestureDetector(
      onTap: state.status == VideoUploadStatus.uploading ? null : onPick,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          border: Border.all(
            color: hasFile
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            width: hasFile ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: hasFile
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
              : Colors.grey.shade50,
        ),
        child: Center(
          child: hasFile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.video_file,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      state.fileName ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text('탭하여 다시 선택',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.video_library_outlined,
                        size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text('갤러리에서 영상 선택',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _UploadProgressCard extends StatelessWidget {
  final VideoUploadState state;
  const _UploadProgressCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isDone = state.status == VideoUploadStatus.done;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDone
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDone ? Icons.check_circle : Icons.cloud_upload,
                color: isDone ? Colors.green : Colors.blue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isDone ? '업로드 완료' : '업로드 중...',
                style: TextStyle(
                  color: isDone ? Colors.green : Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (!isDone)
                Text('${(state.progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 13)),
            ],
          ),
          if (!isDone) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: state.progress,
              backgroundColor: Colors.blue.withValues(alpha: 0.2),
              color: Colors.blue,
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatBytes(state.uploadedBytes)} / ${_formatBytes(state.totalBytes)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)}KB';
  }
}

class _ActionButtons extends StatelessWidget {
  final VideoUploadState state;
  final VoidCallback onUpload;
  final VoidCallback onCancel;
  final VoidCallback onReset;

  const _ActionButtons({
    required this.state,
    required this.onUpload,
    required this.onCancel,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      VideoUploadStatus.uploading => ElevatedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('취소'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade100,
            foregroundColor: Colors.red,
          ),
        ),
      VideoUploadStatus.done => ElevatedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.refresh),
          label: const Text('새 영상 업로드'),
        ),
      _ => ElevatedButton.icon(
          onPressed: state.filePath != null &&
                  state.status != VideoUploadStatus.picking
              ? onUpload
              : null,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('서버로 전송'),
        ),
    };
  }
}
