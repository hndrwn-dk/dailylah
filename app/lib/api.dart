import 'package:dio/dio.dart';

/// Base URL of the DailyLah API (Render). Override at build time:
/// flutter run --dart-define=API_URL=http://10.0.2.2:8000
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://dailylah-api.onrender.com',
);

class DailyLahApi {
  DailyLahApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: apiUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final Dio _dio;

  Future<Map<String, dynamic>> weather(String kind) async =>
      (await _dio.get<Map<String, dynamic>>('/v1/weather/$kind')).data!;

  Future<Map<String, dynamic>> trainAlerts() async =>
      (await _dio.get<Map<String, dynamic>>('/v1/train-alerts')).data!;

  Future<Map<String, dynamic>> busArrival(String stopCode) async =>
      (await _dio.get<Map<String, dynamic>>('/v1/bus-arrival/$stopCode')).data!;
}
