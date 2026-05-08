// lib/features/history/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/history_provider.dart';
import '../../../data/local/storage_monitor.dart';
import '../../../data/models/recording_session_model.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(historyProvider);
    final storageAsync = ref.watch(storageMonitorProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('내 기록')),
      body: Column(
        children: [
          // 저장 용량 상태
          storageAsync.when(
            data: (info) => _StorageBanner(info: info),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // 세션 목록
          Expanded(
            child: sessionsAsync.when(
              data: (sessions) => sessions.isEmpty
                  ? const Center(child: Text('기록된 등산이 없습니다.'))
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        return _SessionTile(
                          session: session,
                          onUpload: () => ref
                              .read(historyProvider.notifier)
                              .uploadSession(session.sessionId),
                          onDelete: () => ref
                              .read(historyProvider.notifier)
                              .deleteSession(session.sessionId),
                        );
                      },
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('오류: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageBanner extends StatelessWidget {
  final StorageInfo info;
  const _StorageBanner({required this.info});

  @override
  Widget build(BuildContext context) {
    if (!info.isWarning) return const SizedBox.shrink();

    final color = info.isCritical ? Colors.red : Colors.orange;
    final message = info.isCritical
        ? '저장 공간 부족 (${info.usedFormatted}) — 데이터를 업로드하거나 삭제하세요'
        : '저장 공간 경고 (${info.usedFormatted} / ${info.warningFormatted})';

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final RecordingSession session;
  final VoidCallback onUpload;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${session.startedAt.year}.${session.startedAt.month.toString().padLeft(2, '0')}.${session.startedAt.day.toString().padLeft(2, '0')} '
        '${session.startedAt.hour.toString().padLeft(2, '0')}:${session.startedAt.minute.toString().padLeft(2, '0')}';

    return ListTile(
      leading: _StatusIcon(status: session.uploadStatus),
      title: Text(dateStr),
      subtitle: _UploadSubtitle(session: session),
      trailing: _ActionButtons(
        status: session.uploadStatus,
        onUpload: onUpload,
        onDelete: onDelete,
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final UploadStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      UploadStatus.done => (Icons.check_circle, Colors.green),
      UploadStatus.uploading => (Icons.cloud_upload, Colors.blue),
      UploadStatus.buffering => (Icons.save, Colors.orange),
      UploadStatus.pendingUpload => (Icons.schedule, Colors.amber),
      UploadStatus.error => (Icons.error, Colors.red),
      _ => (Icons.fiber_manual_record, Colors.grey),
    };
    return Icon(icon, color: color);
  }
}

class _UploadSubtitle extends StatelessWidget {
  final RecordingSession session;
  const _UploadSubtitle({required this.session});

  @override
  Widget build(BuildContext context) {
    if (session.uploadStatus == UploadStatus.uploading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${(session.uploadProgress * 100).toStringAsFixed(1)}% 업로드 중'),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: session.uploadProgress),
        ],
      );
    }

    final label = switch (session.uploadStatus) {
      UploadStatus.done => '업로드 완료',
      UploadStatus.buffering => '로컬 저장됨 (신호 없음)',
      UploadStatus.pendingUpload => '업로드 대기 중',
      UploadStatus.error => '업로드 실패',
      _ => '',
    };

    return label.isEmpty ? const SizedBox.shrink() : Text(label);
  }
}

class _ActionButtons extends StatelessWidget {
  final UploadStatus status;
  final VoidCallback onUpload;
  final VoidCallback onDelete;

  const _ActionButtons({
    required this.status,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == UploadStatus.buffering ||
            status == UploadStatus.pendingUpload ||
            status == UploadStatus.error)
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: onUpload,
            tooltip: '업로드',
          ),
        if (status == UploadStatus.done)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
            tooltip: '삭제',
          ),
      ],
    );
  }
}
