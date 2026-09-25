// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/auth_session.dart';
import '../models/login_request.dart';
import '../models/refresh_request.dart';
import '../models/register_request.dart';
import '../models/token_pair.dart';

part 'auth_client.g.dart';

@RestApi()
abstract class AuthClient {
  factory AuthClient(Dio dio, {String? baseUrl}) = _AuthClient;

  /// Register.
  ///
  /// Creates an account. Needs an invite code unless registration is open; with a code the.
  /// new user also joins that group (`joined_group`).
  @POST('/api/v1/auth/register')
  Future<AuthSession> register({
    @Body() required RegisterRequest body,
  });

  /// Login
  @POST('/api/v1/auth/login')
  Future<AuthSession> login({
    @Body() required LoginRequest body,
  });

  /// Refresh Tokens
  @POST('/api/v1/auth/refresh')
  Future<TokenPair> refreshTokens({
    @Body() required RefreshRequest body,
  });

  /// Logout.
  ///
  /// Ends the session that owns this refresh token. Always succeeds (idempotent).
  @POST('/api/v1/auth/logout')
  Future<void> logout({
    @Body() required RefreshRequest body,
  });

  /// Logout All.
  ///
  /// Ends every session of the current user, including this one.
  @POST('/api/v1/auth/logout-all')
  Future<void> logoutAll();
}
