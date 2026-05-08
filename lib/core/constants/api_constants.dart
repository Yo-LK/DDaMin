// lib/core/constants/api_constants.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  static String get baseUrl => dotenv.env['BASE_URL'] ?? '';

  // Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String refresh = '/auth/refresh';

  // Upload
  static const String uploadChunk = '/upload/chunk';
  static const String uploadFinalize = '/upload/finalize';
  static const String videoUpload = '/api/video/upload';

  // Map
  static const String mapList = '/maps';
  static const String mapDownload = '/maps/download';
  static const String mapVersion = '/maps/version';
}
