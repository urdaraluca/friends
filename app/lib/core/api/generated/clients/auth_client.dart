// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/auth_session.dart';
import '../models/email_verification.dart';
import '../models/login_request.dart';
import '../models/password_reset.dart';
import '../models/password_reset_request.dart';
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
  /// new user also joins that group (`joined_group`). Emails a verification link.
  @POST('/api/v1/auth/register')
  Future<AuthSession> register({
    @Body() required RegisterRequest body,
  });

  /// Login
  @POST('/api/v1/auth/login')
  Future<AuthSession> login({
    @Body() required LoginRequest body,
  });

  /// Refresh Tokens.
  ///
  /// Rotates the refresh token. In cookie mode (``X-Refresh-Token-Transport: cookie``) the.
  /// token comes from the refresh cookie and the new one goes back into it.
  @POST('/api/v1/auth/refresh')
  Future<TokenPair> refreshTokens({
    @Body() required RefreshRequest body,
  });

  /// Logout.
  ///
  /// Ends the session that owns this refresh token (or the refresh cookie's). Always.
  /// succeeds (idempotent).
  @POST('/api/v1/auth/logout')
  Future<void> logout({
    @Body() required RefreshRequest body,
  });

  /// Logout All.
  ///
  /// Ends every session of the current user, including this one.
  @POST('/api/v1/auth/logout-all')
  Future<void> logoutAll();

  /// Request Password Reset.
  ///
  /// Emails a reset link if the address is a verified one of an account. Always 202: the.
  /// response doesn't say whether it was.
  @POST('/api/v1/auth/password-reset/request')
  Future<void> requestPasswordReset({
    @Body() required PasswordResetRequest body,
  });

  /// Reset Password.
  ///
  /// Sets a new password with the emailed link's token, and signs out every session.
  @POST('/api/v1/auth/password-reset')
  Future<void> resetPassword({
    @Body() required PasswordReset body,
  });

  /// Verify Email.
  ///
  /// Confirms the address with the emailed link's token. Works signed out.
  @POST('/api/v1/auth/verify-email')
  Future<void> verifyEmail({
    @Body() required EmailVerification body,
  });
}
