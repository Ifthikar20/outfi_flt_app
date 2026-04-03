import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'device_info_service.dart';

class AuthService {
  final ApiClient _api;

  AuthService(this._api);

  // ─── Raw HTTP helper (bypasses Dio entirely) ─────
  Future<Map<String, dynamic>> _rawPost(String url, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        'Accept-Encoding': 'identity', // Prevent gzip — avoids decompression issues
        'X-Outfi-Mobile-Key': ApiConfig.mobileApiKey,
        'X-Outfi-Platform': DeviceInfoService.getPlatform(),
        'X-Outfi-App-Version': ApiConfig.appVersion,
      },
      body: jsonEncode(body),
    );

    final bytes = response.bodyBytes;
    debugPrint('📥 Auth ${response.statusCode} (${bytes.length} bytes)');

    // Check if response is gzip despite Accept-Encoding: identity
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      debugPrint('⚠️ Response is GZIP compressed despite identity request!');
      debugPrint('📊 First 10 bytes: ${bytes.sublist(0, min(10, bytes.length))}');
    } else {
      debugPrint('📊 First 6 bytes: ${bytes.sublist(0, min(6, bytes.length))}');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Always decode from raw bytes with UTF-8 (response.body uses Latin-1)
      try {
        final decoded = utf8.decode(bytes, allowMalformed: true);
        final result = jsonDecode(decoded) as Map<String, dynamic>;
        debugPrint('✅ JSON decoded successfully from UTF-8 bytes');
        return result;
      } catch (e) {
        debugPrint('⚠️ UTF-8 jsonDecode failed: $e');
        // Try Latin-1 body as secondary
        try {
          return jsonDecode(response.body) as Map<String, dynamic>;
        } catch (e2) {
          debugPrint('⚠️ Latin-1 jsonDecode also failed: $e2');
          return _extractLoginResponse(bytes);
        }
      }
    } else {
      debugPrint('❌ Auth error: ${response.body}');
      throw Exception('Login failed (${response.statusCode}): ${response.body}');
    }
  }

  /// Extracts login response fields directly from raw bytes,
  /// bypassing JSON decode which fails when tokens are modified in transit.
  Map<String, dynamic> _extractLoginResponse(List<int> bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);

    // Extract each JSON value by finding the key and parsing the value
    String _extractString(String key) {
      // Find "key": and extract the value
      final keyPattern = '"$key":';
      final idx = raw.indexOf(keyPattern);
      if (idx == -1) return '';
      final valueStart = idx + keyPattern.length;
      // Skip whitespace
      var i = valueStart;
      while (i < raw.length && (raw[i] == ' ' || raw[i] == '\t')) i++;
      if (i >= raw.length) return '';
      if (raw[i] == '"') {
        // String value — find closing quote (handle escaped quotes)
        i++;
        final sb = StringBuffer();
        while (i < raw.length && raw[i] != '"') {
          if (raw[i] == '\\' && i + 1 < raw.length) {
            sb.write(raw[i + 1]);
            i += 2;
          } else {
            sb.write(raw[i]);
            i++;
          }
        }
        return sb.toString();
      }
      // Non-string value (number, bool, object)
      final end = raw.indexOf(RegExp(r'[,}]'), i);
      return raw.substring(i, end == -1 ? raw.length : end).trim();
    }

    Map<String, dynamic> _extractObject(String key) {
      final keyPattern = '"$key":';
      final idx = raw.indexOf(keyPattern);
      if (idx == -1) return {};
      final braceStart = raw.indexOf('{', idx + keyPattern.length);
      if (braceStart == -1) return {};
      // Find matching closing brace
      var depth = 0;
      for (var i = braceStart; i < raw.length; i++) {
        if (raw[i] == '{') depth++;
        if (raw[i] == '}') depth--;
        if (depth == 0) {
          final objStr = raw.substring(braceStart, i + 1);
          try {
            return jsonDecode(objStr) as Map<String, dynamic>;
          } catch (_) {
            return {};
          }
        }
      }
      return {};
    }

    final accessToken = _extractString('access_token');
    final refreshToken = _extractString('refresh_token');
    final expiresIn = int.tryParse(_extractString('expires_in')) ?? 3600;
    final user = _extractObject('user');
    final deviceId = _extractString('device_id');
    final preferences = _extractObject('preferences');

    debugPrint('✅ Extracted: access_token=${accessToken.length}chars, '
        'refresh_token=${refreshToken.length}chars, '
        'expires_in=$expiresIn, user_keys=${user.keys.toList()}');

    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_in': expiresIn,
      'user': user,
      'device_id': deviceId,
      'preferences': preferences,
    };
  }

  // ─── Email Auth ────────────────────────────────

  Future<AuthResponse> login({
    required String email,
    required String password,
    String? deviceId,
    String? pushToken,
  }) async {
    final realDeviceId = deviceId ?? await DeviceInfoService.getDeviceId();
    final url = '${ApiConfig.baseUrl}/auth/login/';

    final data = await _rawPost(url, {
      'email': email,
      'password': password,
      'device_id': realDeviceId,
      'platform': DeviceInfoService.getPlatform(),
      'app_version': ApiConfig.appVersion,
      if (pushToken != null) 'push_token': pushToken,
    });

    final authResponse = AuthResponse.fromJson(data);
    await _api.saveTokens(
      accessToken: authResponse.accessToken,
      refreshToken: authResponse.refreshToken,
    );
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
    final url = '${ApiConfig.baseUrl}/auth/register/';

    final data = await _rawPost(url, {
      'email': email,
      'password': password,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      'device_id': realDeviceId,
      'platform': DeviceInfoService.getPlatform(),
      'app_version': ApiConfig.appVersion,
    });

    final authResponse = AuthResponse.fromJson(data);
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
