// lib/data/remote/video_remote_datasource.dart
import 'package:dio/dio.dart';
import '../../network/dio_client.dart';
import '../../core/constants/api_constants.dart';

class VideoRemoteDatasource {
  final Dio _dio = DioClient.instance;

  Future<void> uploadVideo({
    required String filePath,
    required void Function(int sent, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final fileName = filePath.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    print('요청 URL: ${ApiConstants.baseUrl}${ApiConstants.videoUpload}');

    try {
      final response = await _dio.post(
        ApiConstants.videoUpload,
        data: formData,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
            'ngrok-skip-browser-warning': 'true',
          },
          sendTimeout: const Duration(minutes: 30),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      print('업로드 응답: ${response.statusCode} ${response.data}');
    } on DioException catch (e) {
      print('DioException: ${e.type}');
      print('status: ${e.response?.statusCode}');
      print('data: ${e.response?.data}');
      print('message: ${e.message}');
      print('error: ${e.error}');
      print('stackTrace: ${e.stackTrace}');
      rethrow;
    }
  }
}