import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';
import 'cache_interceptor.dart';
import 'device_info_service.dart';

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final CacheInterceptor _cacheInterceptor = CacheInterceptor();
  bool _isRefreshing = false;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      // Use bytes to get raw response data — we decode UTF-8 + JSON manually
      // to avoid Dio's internal decoder issues with gzip + charset
      responseType: ResponseType.bytes,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // ── Security headers for APIGuardMiddleware ──
        'X-Outfi-Mobile-Key': ApiConfig.mobileApiKey,
        'X-Outfi-Platform': DeviceInfoService.getPlatform(),
        'X-Outfi-App-Version': ApiConfig.appVersion,
      },
    ));

    // ── Response caching (GET only, 2min TTL) ─────
    _dio.interceptors.add(_cacheInterceptor);

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
      onError: _onError,
    ));

    // ── Debug logging ─────────────────────────────
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: false, // We log manually to avoid token leaks
        requestHeader: false,
        responseHeader: false,
        error: true,
        logPrint: (s) => debugPrint('🌐 $s'),
      ));
    }

    // ── Certificate Pinning ───────────────────────
    _configureCertificatePinning();
  }

  Dio get dio => _dio;

  // ─── Certificate Pinning ──────────────────────

  /// Pins TLS connections to the SHA-256 fingerprints defined in [ApiConfig].
  void _configureCertificatePinning() {
    if (ApiConfig.certificatePins.isEmpty || kDebugMode) {
      return;
    }

    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        if (host != ApiConfig.apiHost) return true;
        final digest = sha256.convert(cert.der);
        final certHash = base64Encode(digest.bytes);
        final isPinned = ApiConfig.certificatePins.contains(certHash);
        if (!isPinned) {
          debugPrint(
            '⚠️ Certificate pinning failed for $host — '
            'got $certHash but expected one of ${ApiConfig.certificatePins}',
          );
        }
        return isPinned;
      };
      return client;
    };
  }

  // ─── Decode raw bytes → JSON Map ──────────────

  /// Decodes response bytes into a JSON object.
  /// Handles gzip decompression (done by Dio) and UTF-8 decoding manually.
  static dynamic _decodeResponseBytes(dynamic data) {
    if (data is Map) return data; // Already decoded JSON object
    // Check for raw bytes BEFORE the generic List check
    // (Uint8List is a subtype of List, so `data is List` would match bytes!)
    if (data is Uint8List) {
      // Strip UTF-8 BOM if present
      final offset = (data.length >= 3 &&
              data[0] == 0xEF &&
              data[1] == 0xBB &&
              data[2] == 0xBF)
          ? 3
          : 0;
      final jsonStr = utf8.decode(data.sublist(offset), allowMalformed: true);
      debugPrint('📦 Decoded ${data.length} bytes → ${jsonStr.length} chars');
      if (jsonStr.trim().isEmpty) return <String, dynamic>{};
      return jsonDecode(jsonStr);
    }
    if (data is List<int>) {
      final bytes = Uint8List.fromList(data);
      final jsonStr = utf8.decode(bytes, allowMalformed: true);
      if (jsonStr.trim().isEmpty) return <String, dynamic>{};
      return jsonDecode(jsonStr);
    }
    if (data is List) return data; // Already decoded JSON array
    if (data is String) {
      if (data.trim().isEmpty) return <String, dynamic>{};
      return jsonDecode(data);
    }
    return data;
  }

  // ─── Interceptors ─────────────────────────────

  Future<void> _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: _accessTokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    // Always send device ID for anonymous board tracking
    options.headers['X-Device-Id'] = await DeviceInfoService.getDeviceId();
    debugPrint('📤 ${options.method} ${options.path}');
    handler.next(options);
  }

  /// Decode the raw bytes response into a JSON Map/List.
  void _onResponse(
      Response response, ResponseInterceptorHandler handler) {
    try {
      response.data = _decodeResponseBytes(response.data);
      debugPrint('📥 ${response.statusCode} ${response.requestOptions.path} '
          '(${response.data is Map ? (response.data as Map).length : '?'} keys)');
    } catch (e) {
      debugPrint('❌ Response decode error for ${response.requestOptions.path}: $e');
      // Log raw byte info for debugging
      if (response.data is List<int>) {
        final bytes = response.data as List<int>;
        debugPrint('   Raw bytes length: ${bytes.length}');
        debugPrint('   First 50 bytes: ${bytes.take(50).toList()}');
      }
    }
    handler.next(response);
  }

  Future<void> _onError(
      DioException error, ErrorInterceptorHandler handler) async {
    debugPrint('❌ Error ${error.response?.statusCode} ${error.requestOptions.path}: '
        '${error.message}');

    // Try to decode error response body
    if (error.response?.data != null) {
      try {
        error.response!.data = _decodeResponseBytes(error.response!.data);
      } catch (_) {}
    }

    // Only attempt refresh for 401 on non-auth endpoints (guard against loop)
    if (error.response?.statusCode == 401 &&
        !error.requestOptions.path.contains('/auth/') &&
        !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshed = await _refreshToken();
        if (refreshed) {
          final opts = error.requestOptions;
          final token = await _storage.read(key: _accessTokenKey);
          opts.headers['Authorization'] = 'Bearer $token';
          try {
            final response = await _dio.fetch(opts);
            return handler.resolve(response);
          } catch (e) {
            return handler.next(error);
          }
        } else {
          await clearTokens();
        }
      } finally {
        _isRefreshing = false;
      }
    }
    handler.next(error);
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (refreshToken == null) return false;

      final refreshDio = Dio(BaseOptions(
        responseType: ResponseType.bytes,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Outfi-Mobile-Key': ApiConfig.mobileApiKey,
          'X-Outfi-Platform': DeviceInfoService.getPlatform(),
        },
      ));

      final response = await refreshDio.post(
        '${ApiConfig.baseUrl.replaceAll('/mobile', '')}/auth/token/refresh/',
        data: {'refresh': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = _decodeResponseBytes(response.data);
        if (data is Map) {
          await saveTokens(
            accessToken: data['access'] ?? '',
            refreshToken: refreshToken,
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint('Token refresh failed: $e');
    }
    return false;
  }

  // ─── Token Storage ────────────────────────────

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    _cacheInterceptor.clear(); // Wipe cached responses on logout
  }

  /// Clears all cached GET responses.
  void clearCache() => _cacheInterceptor.clear();

  /// Invalidates cached responses matching [pathPattern].
  void invalidateCache(String pathPattern) =>
      _cacheInterceptor.invalidate(pathPattern);

  Future<bool> hasTokens() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null;
  }

  // ─── HTTP Methods ──────────────────────────────

  Future<Response> get(String path, {Map<String, dynamic>? params}) {
    return _dio.get(path, queryParameters: params);
  }

  Future<Response> post(String path, {dynamic data}) {
    return _dio.post(path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) {
    return _dio.patch(path, data: data);
  }

  Future<Response> put(String path, {dynamic data}) {
    return _dio.put(path, data: data);
  }

  Future<Response> delete(String path) {
    return _dio.delete(path);
  }

  Future<Response> uploadFile(String path, FormData formData) {
    return _dio.post(
      path,
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        receiveTimeout: ApiConfig.imageUploadTimeout,
      ),
    );
  }
}
