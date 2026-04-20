import 'dart:async';
import 'package:dio/dio.dart';

/// In-memory LRU cache for GET responses.
///
/// Caches successful GET responses for [defaultTtl] to avoid
/// repeated identical network requests. POST/PATCH/DELETE bypass the cache.
/// Also deduplicates concurrent identical GETs: a second request arriving
/// while the first is still in flight waits on the first's result instead
/// of firing a duplicate network call.
class CacheInterceptor extends Interceptor {
  final int maxEntries;
  final Duration defaultTtl;

  /// Per-path TTL overrides. Matching is substring against `options.path`.
  /// First matching entry wins — more specific paths first.
  final Map<String, Duration> pathTtl;

  final _cache = <String, _CacheEntry>{};
  final _inflight = <String, Completer<Response>>{};

  CacheInterceptor({
    this.maxEntries = 100,
    this.defaultTtl = const Duration(minutes: 2),
    Map<String, Duration>? pathTtl,
  }) : pathTtl = pathTtl ?? const {
          // Featured brands / search prompts change ~weekly; cache for a day.
          '/featured/': Duration(hours: 24),
          // User preferences rarely change mid-session.
          '/preferences/': Duration(minutes: 30),
        };

  Duration _ttlFor(String path) {
    for (final entry in pathTtl.entries) {
      if (path.contains(entry.key)) return entry.value;
    }
    return defaultTtl;
  }

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Only cache/dedup GET requests
    if (options.method != 'GET') {
      handler.next(options);
      return;
    }

    final key = _cacheKey(options);
    final entry = _cache[key];

    if (entry != null && !entry.isExpired) {
      // Cache HIT — return cached response without hitting network
      handler.resolve(
        Response(
          requestOptions: options,
          data: entry.data,
          statusCode: entry.statusCode,
          headers: entry.headers,
        ),
        true, // call next interceptor
      );
      return;
    }

    // Dedup: another identical request is already in flight — await it.
    final pending = _inflight[key];
    if (pending != null) {
      try {
        final shared = await pending.future;
        handler.resolve(
          Response(
            requestOptions: options,
            data: shared.data,
            statusCode: shared.statusCode,
            headers: shared.headers,
          ),
          true,
        );
      } catch (e) {
        handler.reject(
          e is DioException
              ? DioException(
                  requestOptions: options,
                  error: e.error,
                  response: e.response,
                  type: e.type,
                )
              : DioException(requestOptions: options, error: e),
          true,
        );
      }
      return;
    }

    // Cache MISS — track this as the in-flight request and proceed.
    _inflight[key] = Completer<Response>();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final opts = response.requestOptions;
    if (opts.method == 'GET') {
      final key = _cacheKey(opts);

      // Only cache successful responses
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        // Evict oldest entry if cache is full
        if (_cache.length >= maxEntries) {
          _cache.remove(_cache.keys.first);
        }
        _cache[key] = _CacheEntry(
          data: response.data,
          statusCode: response.statusCode!,
          headers: response.headers,
          expiresAt: DateTime.now().add(_ttlFor(opts.path)),
        );
      }

      // Release any waiters (success or non-2xx, so they don't hang).
      _inflight.remove(key)?.complete(response);
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final opts = err.requestOptions;
    if (opts.method == 'GET') {
      _inflight.remove(_cacheKey(opts))?.completeError(err);
    }
    handler.next(err);
  }

  /// Clears the entire cache (e.g. on logout).
  void clear() => _cache.clear();

  /// Invalidates a specific path pattern from the cache.
  void invalidate(String pathPattern) {
    _cache.removeWhere((key, _) => key.contains(pathPattern));
  }

  String _cacheKey(RequestOptions options) {
    final params = options.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final paramStr = params.map((e) => '${e.key}=${e.value}').join('&');
    return '${options.path}?$paramStr';
  }
}

class _CacheEntry {
  final dynamic data;
  final int statusCode;
  final Headers headers;
  final DateTime expiresAt;

  _CacheEntry({
    required this.data,
    required this.statusCode,
    required this.headers,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
