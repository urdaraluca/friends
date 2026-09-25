import 'package:dio/dio.dart';
import 'package:friends/core/config/env.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'health_repository.g.dart';

class ApiHealth {
  const new({required this.status, required this.version});

  factory fromJson(Map<String, dynamic> json) => ApiHealth(
    status: json['status'] as String,
    version: json['version'] as String,
  );

  final String status;
  final String version;
}

@Riverpod(keepAlive: true)
Dio healthDio(Ref ref) => Dio(
  BaseOptions(
    baseUrl: Env.apiBaseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ),
);

@riverpod
Future<ApiHealth> apiHealth(Ref ref) async {
  final response = await ref
      .watch(healthDioProvider)
      .get<Map<String, dynamic>>('/api/v1/health');
  return ApiHealth.fromJson(response.data!);
}
