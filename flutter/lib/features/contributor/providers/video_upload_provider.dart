// lib/features/contributor/providers/video_upload_provider.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/remote/video_remote_datasource.dart';

enum VideoUploadStatus { idle, picking, uploading, done, error }

enum UploadMode { single, chunked }

class VideoUploadState {
  final VideoUploadStatus status;
  final UploadMode uploadMode;
  final String? filePath;
  final String? fileName;
  final int uploadedBytes;
  final int totalBytes;
  final String? errorMessage;

  const VideoUploadState({
    this.status = VideoUploadStatus.idle,
    this.uploadMode = UploadMode.chunked,
    this.filePath,
    this.fileName,
    this.uploadedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  double get progress => totalBytes == 0 ? 0 : uploadedBytes / totalBytes;

  VideoUploadState copyWith({
    VideoUploadStatus? status,
    UploadMode? uploadMode,
    String? filePath,
    String? fileName,
    int? uploadedBytes,
    int? totalBytes,
    String? errorMessage,
  }) {
    return VideoUploadState(
      status: status ?? this.status,
      uploadMode: uploadMode ?? this.uploadMode,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage,
    );
  }
}

class VideoUploadNotifier extends StateNotifier<VideoUploadState> {
  final VideoRemoteDatasource _datasource;
  CancelToken? _cancelToken;

  VideoUploadNotifier(this._datasource) : super(const VideoUploadState());

  void setUploadMode(UploadMode mode) {
    state = state.copyWith(uploadMode: mode);
  }

  Future<void> pickVideo() async {
    if (state.status == VideoUploadStatus.picking) return;
    state = state.copyWith(status: VideoUploadStatus.picking);
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);

    if (video == null) {
      state = state.copyWith(status: VideoUploadStatus.idle);
      return;
    }

    state = state.copyWith(
      status: VideoUploadStatus.idle,
      filePath: video.path,
      fileName: video.name,
      uploadedBytes: 0,
      totalBytes: 0,
    );
  }

  Future<void> upload() async {
    final filePath = state.filePath;
    if (filePath == null) return;

    _cancelToken = CancelToken();
    state = state.copyWith(
      status: VideoUploadStatus.uploading,
      uploadedBytes: 0,
      totalBytes: 0,
    );

    try {
      if (state.uploadMode == UploadMode.single) {
        await _datasource.uploadVideoSingle(
          filePath: filePath,
          onProgress: (sent, total) {
            state = state.copyWith(uploadedBytes: sent, totalBytes: total);
          },
          cancelToken: _cancelToken,
        );
      } else {
        await _datasource.uploadVideoChunked(
          filePath: filePath,
          onProgress: (sent, total) {
            state = state.copyWith(uploadedBytes: sent, totalBytes: total);
          },
          cancelToken: _cancelToken,
        );
      }
      state = state.copyWith(status: VideoUploadStatus.done);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        state = state.copyWith(status: VideoUploadStatus.idle);
      } else {
        state = state.copyWith(
          status: VideoUploadStatus.error,
          errorMessage: e.message,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: VideoUploadStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void cancelUpload() {
    _cancelToken?.cancel();
  }

  void reset() {
    _cancelToken?.cancel();
    state = const VideoUploadState();
  }
}

final videoUploadProvider =
    StateNotifierProvider<VideoUploadNotifier, VideoUploadState>((ref) {
  return VideoUploadNotifier(VideoRemoteDatasource());
});
