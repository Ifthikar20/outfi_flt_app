import 'dart:async';
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
  // Singleton — every `ApiClient()` call returns the same instance so all
  // screens share one CacheInterceptor. Without this, each screen has its
  // own cache and invalidations don't propagate (e.g. saving a fashion
  // board would leave the board list screen showing a stale result).
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final CacheInterceptor _cacheInterceptor = CacheInterceptor();

  /// Completer-based refresh queue: all concurrent 401s wait on the
  /// same future instead of each triggering their own refresh.
  Completer<bool>? _refreshCompleter;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  ApiClient._internal() {
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

  // Track request timing
  final _requestTimers = <String, DateTime>{};

  Future<void> _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: _accessTokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    options.headers['X-Device-Id'] = await DeviceInfoService.getDeviceId();

    // ── Detailed request log ──
    _requestTimers[options.path] = DateTime.now();

    if (kDebugMode) {
      debugPrint('');
      debugPrint('┌─── REQUEST ──────────────────────────────────');
      debugPrint('│ ${options.method} ${options.uri}');
      debugPrint('│ Auth: ${token != null && token.isNotEmpty ? "Bearer ${token.substring(0, token.length.clamp(0, 20))}..." : "NONE"}');
      debugPrint('│ Host: ${options.uri.host}');
      if (options.data != null) {
        final dataStr = options.data.toString();
        if (dataStr.length > 500) {
          debugPrint('│ Body: ${dataStr.substring(0, 500)}...(${dataStr.length} chars)');
        } else {
          debugPrint('│ Body: $dataStr');
        }
      }
      debugPrint('└──────────────────────────────────────────────');
    }

    handler.next(options);
  }

  void _onResponse(
      Response response, ResponseInterceptorHandler handler) {
    final elapsed = _requestTimers.containsKey(response.requestOptions.path)
        ? DateTime.now().difference(_requestTimers[response.requestOptions.path]!).inMilliseconds
        : -1;
    _requestTimers.remove(response.requestOptions.path);

    try {
      response.data = _decodeResponseBytes(response.data);
    } catch (e) {
      debugPrint('❌ Response decode error for ${response.requestOptions.path}: $e');
      if (response.data is List<int>) {
        final bytes = response.data as List<int>;
        debugPrint('   Raw bytes: ${bytes.length} bytes, first 50: ${bytes.take(50).toList()}');
      }
    }

    // ── Detailed response log ──
    if (kDebugMode) {
      debugPrint('');
      debugPrint('┌─── RESPONSE ${response.statusCode} ─── ${elapsed}ms ──────');
      debugPrint('│ ${response.requestOptions.method} ${response.requestOptions.path}');
      if (response.data is Map) {
        final map = response.data as Map;
        debugPrint('│ Keys: ${map.keys.toList()}');
        for (final key in map.keys.take(8)) {
          final val = map[key].toString();
          debugPrint('│   $key: ${val.length > 100 ? "${val.substring(0, 100)}..." : val}');
        }
        if (map.keys.length > 8) debugPrint('│   ...and ${map.keys.length - 8} more keys');
      } else if (response.data is List) {
        debugPrint('│ Array: ${(response.data as List).length} items');
      } else {
        debugPrint('│ Data: ${response.data.toString().substring(0, 200.clamp(0, response.data.toString().length))}');
      }
      debugPrint('└──────────────────────────────────────────────');
    }

    handler.next(response);
  }

  Future<void> _onError(
      DioException error, ErrorInterceptorHandler handler) async {
    final elapsed = _requestTimers.containsKey(error.requestOptions.path)
        ? DateTime.now().difference(_requestTimers[error.requestOptions.path]!).inMilliseconds
        : -1;
    _requestTimers.remove(error.requestOptions.path);

    // Try to decode error response body
    if (error.response?.data != null) {
      try {
        error.response!.data = _decodeResponseBytes(error.response!.data);
      } catch (_) {}
    }

    // ── Detailed error log ──
    if (kDebugMode) {
      debugPrint('');
      debugPrint('┌─── ERROR ${error.response?.statusCode ?? "NO_RESPONSE"} ─── ${elapsed}ms ──');
      debugPrint('│ ${error.requestOptions.method} ${error.requestOptions.uri}');
      debugPrint('│ Type: ${error.type}');
      debugPrint('│ Message: ${error.message}');
      if (error.response?.data != null) {
        debugPrint('│ Server response: ${error.response!.data}');
      }
      if (error.error != null) {
        debugPrint('│ Inner error: ${error.error}');
      }
      debugPrint('└──────────────────────────────────────────────');
    }

    // Only attempt refresh for 401 on non-auth endpoints
    if (error.response?.statusCode == 401 &&
        !error.requestOptions.path.contains('/auth/')) {
      // If a refresh is already in progress, wait for its result
      if (_refreshCompleter != null) {
        final refreshed = await _refreshCompleter!.future;
        if (refreshed) {
          final opts = error.requestOptions;
          final token = await _storage.read(key: _accessTokenKey);
          opts.headers['Authorization'] = 'Bearer $token';
          try {
            final response = await _dio.fetch(opts);
            return handler.resolve(response);
          } catch (_) {
            return handler.next(error);
          }
        }
        return handler.next(error);
      }

      // First 401 — initiate the refresh
      _refreshCompleter = Completer<bool>();
      if (kDebugMode) debugPrint('🔄 Token expired — attempting refresh...');
      try {
        final refreshed = await _refreshToken();
        _refreshCompleter!.complete(refreshed);
        _refreshCompleter = null;

        if (refreshed) {
          if (kDebugMode) debugPrint('🔄 Token refreshed — retrying request');
          final opts = error.requestOptions;
          final token = await _storage.read(key: _accessTokenKey);
          opts.headers['Authorization'] = 'Bearer $token';
          try {
            final response = await _dio.fetch(opts);
            return handler.resolve(response);
          } catch (e) {
            if (kDebugMode) debugPrint('🔄 Retry failed: $e');
            return handler.next(error);
          }
        } else {
          if (kDebugMode) debugPrint('🔄 Token refresh failed — clearing tokens');
          await clearTokens();
        }
      } catch (e) {
        _refreshCompleter?.complete(false);
        _refreshCompleter = null;
        if (kDebugMode) debugPrint('🔄 Token refresh threw: $e');
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

  Future<Response> get(String path, {Map<String, dynamic>? params, String? fullUrl}) {
    return _dio.get(fullUrl ?? path, queryParameters: params);
  }

  Future<Response> post(String path, {dynamic data, String? fullUrl}) {
    return _dio.post(fullUrl ?? path, data: data);
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
