// lib/data/remote/video_remote_datasource.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const int _chunkSize = 5 * 1024 * 1024; // 5MB

class VideoRemoteDatasource {
  String get _baseUrl => dotenv.env['BASE_URL'] ?? '';
  String get _uploadUrl => '$_baseUrl/api/video/upload';

  // 통파일 업로드
  Future<void> uploadVideoSingle({
    required String filePath,
    required void Function(int sent, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    final totalBytes = await file.length();
    final fileName = filePath.split('/').last;

    print('요청 URL: $_uploadUrl (통파일)');
    print('파일 크기: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)}MB');

    final boundary = '----FlutterBoundary${DateTime.now().millisecondsSinceEpoch}';
    final uri = Uri.parse(_uploadUrl);
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final request = await httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      request.headers.set('ngrok-skip-browser-warning', 'true');

      final header = [
        '--$boundary\r\n',
        'Content-Disposition: form-data; name="chunk_index"\r\n\r\n',
        '0\r\n',
        '--$boundary\r\n',
        'Content-Disposition: form-data; name="total_chunks"\r\n\r\n',
        '1\r\n',
        '--$boundary\r\n',
        'Content-Disposition: form-data; name="file_name"\r\n\r\n',
        '$fileName\r\n',
        '--$boundary\r\n',
        'Content-Disposition: form-data; name="is_last"\r\n\r\n',
        'true\r\n',
        '--$boundary\r\n',
        'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n',
        'Content-Type: application/octet-stream\r\n\r\n',
      ].join().codeUnits;

      final footer = '\r\n--$boundary--\r\n'.codeUnits;
      final contentLength = header.length + totalBytes + footer.length;
      request.headers.contentLength = contentLength;

      // 헤더 전송
      request.add(header);

      // 파일 스트리밍 전송
      int sent = 0;
      await for (final chunk in file.openRead()) {
        if (cancelToken?.isCancelled == true) break;
        request.add(chunk);
        sent += chunk.length;
        onProgress(sent, totalBytes);
      }

      // 푸터 전송
      request.add(footer);

      final response = await request.close();

      if (response.statusCode != 200) {
        final body = await response.transform(const SystemEncoding().decoder).join();
        print('업로드 실패: ${response.statusCode} $body');
        throw Exception('업로드 실패: ${response.statusCode}');
      }

      await response.drain<void>();
    } finally {
      httpClient.close();
    }
  }

  // 청크 업로드
  Future<void> uploadVideoChunked({
    required String filePath,
    required void Function(int sent, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    final totalBytes = await file.length();
    final fileName = filePath.split('/').last;

    print('요청 URL: $_uploadUrl (청크)');
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
          final respBody = await response.transform(const SystemEncoding().decoder).join();
          print('청크 $chunkIndex 실패: ${response.statusCode} $respBody');
          throw Exception('업로드 실패: ${response.statusCode}');
        }

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

    for (final entry in fields.entries) {
      parts.addAll('--$boundary\r\n'.codeUnits);
      parts.addAll(
          'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'.codeUnits);
      parts.addAll('${entry.value}\r\n'.codeUnits);
    }

    parts.addAll('--$boundary\r\n'.codeUnits);
    parts.addAll(
        'Content-Disposition: form-data; name="$fileField"; filename="$fileName"\r\n'.codeUnits);
    parts.addAll('Content-Type: application/octet-stream\r\n\r\n'.codeUnits);
    parts.addAll(fileBytes);
    parts.addAll('\r\n'.codeUnits);
    parts.addAll('--$boundary--\r\n'.codeUnits);

    return parts;
  }
}
