// lib/data/remote/video_remote_datasource.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const int _chunkSize = 10 * 1024 * 1024; // 10MB

class VideoRemoteDatasource {
  String get _baseUrl => dotenv.env['BASE_URL'] ?? '';
  String get _uploadUrl => '$_baseUrl/api/video/upload';

  Future<void> uploadVideo({
    required String filePath,
    required void Function(int sent, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    final totalBytes = await file.length();
    final fileName = filePath.split('/').last;

    print('요청 URL: $_uploadUrl');
    print('파일 크기: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)}MB');

    final totalChunks = (totalBytes / _chunkSize).ceil();
    int offset = 0;
    int chunkIndex = 0;

    final raf = await file.open(mode: FileMode.read);

    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      while (offset < totalBytes) {
        if (cancelToken?.isCancelled == true) break;

        final remaining = totalBytes - offset;
        final currentChunkSize =
            remaining < _chunkSize ? remaining.toInt() : _chunkSize;
        final isLast = (offset + currentChunkSize) >= totalBytes;

        final Uint8List buffer = await raf.read(currentChunkSize);

        final boundary = '----FlutterBoundary${DateTime.now().millisecondsSinceEpoch}';
        final uri = Uri.parse(_uploadUrl);

        final request = await httpClient.postUrl(uri);
        request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
        request.headers.set('ngrok-skip-browser-warning', 'true');

        final body = _buildMultipartBody(
          boundary: boundary,
          fields: {
            'chunk_index': chunkIndex.toString(),
            'total_chunks': totalChunks.toString(),
            'file_name': fileName,
            'is_last': isLast.toString(),
          },
          fileField: 'file',
          fileName: fileName,
          fileBytes: buffer,
        );

        request.headers.contentLength = body.length;
        request.add(body);

        final response = await request.close();

        if (response.statusCode != 200) {
          final body = await response.transform(
            const SystemEncoding().decoder,
          ).join();
          print('청크 $chunkIndex 실패: ${response.statusCode} $body');
          throw Exception('업로드 실패: ${response.statusCode}');
        }

        // 응답 소비
        await response.drain<void>();

        offset += currentChunkSize;
        chunkIndex++;
        onProgress(offset, totalBytes);
      }
    } finally {
      await raf.close();
      httpClient.close();
    }
  }

  List<int> _buildMultipartBody({
    required String boundary,
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required Uint8List fileBytes,
  }) {
    final parts = <int>[];

    // 텍스트 필드
    for (final entry in fields.entries) {
      parts.addAll('--$boundary\r\n'.codeUnits);
      parts.addAll(
          'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'.codeUnits);
      parts.addAll('${entry.value}\r\n'.codeUnits);
    }

    // 파일 필드
    parts.addAll('--$boundary\r\n'.codeUnits);
    parts.addAll(
        'Content-Disposition: form-data; name="$fileField"; filename="$fileName"\r\n'.codeUnits);
    parts.addAll('Content-Type: application/octet-stream\r\n\r\n'.codeUnits);
    parts.addAll(fileBytes);
    parts.addAll('\r\n'.codeUnits);

    // 종료
    parts.addAll('--$boundary--\r\n'.codeUnits);

    return parts;
  }
}
