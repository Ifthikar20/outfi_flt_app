import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'device_info_service.dart';

class AuthService {
  final ApiClient _api;

  AuthService(this._api);

  // ─── Email Auth ────────────────────────────────

  Future<AuthResponse> login({
    required String email,
    required String password,
    String? deviceId,
    String? pushToken,
  }) async {
    final realDeviceId = deviceId ?? await DeviceInfoService.getDeviceId();

    final response = await _api.post('/auth/login/', data: {
      'email': email,
      'password': password,
      'device_id': realDeviceId,
      'platform': DeviceInfoService.getPlatform(),
      'app_version': ApiConfig.appVersion,
      if (pushToken != null) 'push_token': pushToken,
    });

    final data = response.data as Map<String, dynamic>;
    final authResponse = AuthResponse.fromJson(data);

    await _api.saveTokens(
      accessToken: authResponse.accessToken,
      refreshToken: authResponse.refreshToken,
    );
    if (kDebugMode) debugPrint('🔑 Login successful');

    return authResponse;
  }

  Future<AuthResponse> register({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    String? deviceId,
  }) async {
    final realDeviceId = deviceId ?? await DeviceInfoService.getDeviceId();

    final response = await _api.post('/auth/register/', data: {
      'email': email,
      'password': password,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      'device_id': realDeviceId,
      'platform': DeviceInfoService.getPlatform(),
      'app_version': ApiConfig.appVersion,
    });

    final authResponse = AuthResponse.fromJson(response.data as Map<String, dynamic>);
    await _api.saveTokens(
      accessToken: authResponse.accessToken,
      refreshToken: authResponse.refreshToken,
    );
    return authResponse;
  }

  // ─── OAuth ─────────────────────────────────────

  Future<AuthResponse> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      serverClientId: ApiConfig.googleClientId,
    );

    final account = await googleSignIn.signIn();
    if (account == null) throw Exception('Google sign-in cancelled');

    final auth = await account.authentication;
    final code = auth.serverAuthCode ?? auth.idToken ?? '';

    final deviceId = await DeviceInfoService.getDeviceId();

    final response = await _api.post('/auth/oauth/', data: {
      'provider': 'google',
      'code': code,
      'redirect_uri': 'com.outfi.app:/oauth/callback',
      'device_id': deviceId,
      'platform': DeviceInfoService.getPlatform(),
    });

    final authResponse = AuthResponse.fromJson(response.data);
    await _api.saveTokens(
      accessToken: authResponse.accessToken,
      refreshToken: authResponse.refreshToken,
    );
    return authResponse;
  }

  Future<AuthResponse> signInWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final deviceId = await DeviceInfoService.getDeviceId();

    final response = await _api.post('/auth/oauth/', data: {
      'provider': 'apple',
      'code': credential.authorizationCode,
      'id_token': credential.identityToken,
      'user': {
        'name': {
          'firstName': credential.givenName ?? '',
          'lastName': credential.familyName ?? '',
        }
      },
      'device_id': deviceId,
      'platform': 'ios',
    });

    final authResponse = AuthResponse.fromJson(response.data);
    await _api.saveTokens(
      accessToken: authResponse.accessToken,
      refreshToken: authResponse.refreshToken,
    );
    return authResponse;
  }

  // ─── Logout ────────────────────────────────────

  Future<void> logout() async {
    try {
      final deviceId = await DeviceInfoService.getDeviceId();
      await _api.post('/auth/logout/', data: {
        'device_id': deviceId,
      });
    } catch (_) {
      // Logout even if server call fails
    }
    await _api.clearTokens();
  }

  // ─── Health Check ──────────────────────────────

  Future<Map<String, dynamic>> healthCheck() async {
    final response = await _api.get('/health/', params: {
      'platform': DeviceInfoService.getPlatform(),
    });
    return response.data;
  }

  Future<bool> isLoggedIn() => _api.hasTokens();
}
