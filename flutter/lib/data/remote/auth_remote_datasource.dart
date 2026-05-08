// lib/data/remote/auth_remote_datasource.dart
import '../models/auth_token_model.dart';
import '../../network/dio_client.dart';
import '../../core/constants/api_constants.dart';

class AuthRemoteDatasource {
  final _dio = DioClient.instance;

  Future<AuthTokenModel> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      ApiConstants.login,
      data: {'email': email, 'password': password},
    );
    return AuthTokenModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AuthTokenModel> register({
    required String email,
    required String password,
    required String username,
  }) async {
    final response = await _dio.post(
      ApiConstants.register,
      data: {'email': email, 'password': password, 'username': username},
    );
    return AuthTokenModel.fromJson(response.data as Map<String, dynamic>);
  }
}
