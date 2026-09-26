import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/models/health.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:friends/core/api/generated/models/health.dart';
export 'package:friends/core/api/generated/models/health_db.dart';
export 'package:friends/core/api/generated/models/health_status.dart';

part 'health_repository.g.dart';

/// `GET /health` (public). A degraded API answers 503, which surfaces as an
/// error.
@riverpod
Future<Health> apiHealth(Ref ref) =>
    apiCall(ref.watch(healthClientProvider).getHealth);
