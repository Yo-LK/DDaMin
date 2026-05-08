// lib/network/dio_client.dart
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../data/local/token_storage.dart';

class DioClient {
  static Dio? _instance;

  static Dio get instance {
    _instance ??= _create();
    return _instance!;
  }

  static Dio _create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(_AuthInterceptor(dio));
    return dio;
  }
}

class _AuthInterceptor extends Interceptor {
  final Dio dio;
  _AuthInterceptor(this.dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await TokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        // 원래 요청 재시도
        final opts = err.requestOptions;
        final token = await TokenStorage.getAccessToken();
        opts.headers['Authorization'] = 'Bearer $token';
        try {
          final response = await dio.fetch(opts);
          handler.resolve(response);
          return;
        } catch (_) {}
      }
      // refresh 실패 → 토큰 삭제
      await TokenStorage.clear();
    }
    handler.next(err);
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await TokenStorage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await Dio().post(
        '${ApiConstants.baseUrl}${ApiConstants.refresh}',
        data: {'refresh_token': refreshToken},
      );
      final newAccess = response.data['access_token'] as String?;
      final newRefresh = response.data['refresh_token'] as String?;
      if (newAccess != null && newRefresh != null) {
        await TokenStorage.saveTokens(
          accessToken: newAccess,
          refreshToken: newRefresh,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }
}
