// lib/network/upload_client.dart
import 'dart:io';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import 'dio_client.dart';

const int _chunkSize = 2 * 1024 * 1024; // 2MB

class UploadClient {
  final Dio _dio = DioClient.instance;

  /// mp4 + gps json을 청크 단위로 업로드
  /// [onProgress]: uploadedBytes, totalBytes
  Future<void> uploadSession({
    required String sessionId,
    required String mp4Path,
    required String gpsJsonPath,
    required void Function(int uploaded, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final mp4File = File(mp4Path);
    final gpsFile = File(gpsJsonPath);

    final mp4Size = await mp4File.length();
    final gpsSize = await gpsFile.length();
    final totalBytes = mp4Size + gpsSize;
    int uploadedBytes = 0;

    // 1. GPS json 먼저 전송 (작은 파일, 단일 요청)
    await _dio.post(
      ApiConstants.uploadChunk,
      data: FormData.fromMap({
        'session_id': sessionId,
        'file_type': 'gps',
        'file': await MultipartFile.fromFile(gpsJsonPath, filename: 'gps.json'),
      }),
      cancelToken: cancelToken,
    );
    uploadedBytes += gpsSize;
    onProgress(uploadedBytes, totalBytes);

    // 2. mp4 청크 단위 전송
    final mp4Stream = mp4File.openRead();
    int offset = 0;
    final buffer = <int>[];

    await for (final chunk in mp4Stream) {
      buffer.addAll(chunk);

      while (buffer.length >= _chunkSize) {
        final chunkData = buffer.sublist(0, _chunkSize);
        buffer.removeRange(0, _chunkSize);

        await _sendChunk(
          sessionId: sessionId,
          chunkData: chunkData,
          offset: offset,
          isLast: false,
          cancelToken: cancelToken,
        );
        offset += chunkData.length;
        uploadedBytes += chunkData.length;
        onProgress(uploadedBytes, totalBytes);
      }
    }

    // 남은 데이터 마지막 청크로 전송
    if (buffer.isNotEmpty) {
      await _sendChunk(
        sessionId: sessionId,
        chunkData: buffer,
        offset: offset,
        isLast: true,
        cancelToken: cancelToken,
      );
      uploadedBytes += buffer.length;
      onProgress(uploadedBytes, totalBytes);
    }

    // 3. 업로드 완료 신호
    await _dio.post(
      ApiConstants.uploadFinalize,
      data: {'session_id': sessionId},
      cancelToken: cancelToken,
    );
  }

  Future<void> _sendChunk({
    required String sessionId,
    required List<int> chunkData,
    required int offset,
    required bool isLast,
    CancelToken? cancelToken,
  }) async {
    await _dio.post(
      ApiConstants.uploadChunk,
      data: FormData.fromMap({
        'session_id': sessionId,
        'file_type': 'mp4',
        'offset': offset,
        'is_last': isLast,
        'chunk': MultipartFile.fromBytes(chunkData, filename: 'chunk'),
      }),
      cancelToken: cancelToken,
    );
  }
}
