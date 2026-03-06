import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/deal.dart';
import 'api_client.dart';

class DealService {
  final ApiClient _api;

  DealService(this._api);

  // ─── Text Search ───────────────────────────────

  Future<SearchResult> search({
    required String query,
    double? minPrice,
    double? maxPrice,
    String sort = 'relevance',
    int limit = 20,
    int offset = 0,
    String? gender,
    List<String>? sources,
  }) async {
    // Retry loop for 429 rate limiting
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _api.post('/deals/search/', data: {
          'query': query.trim(),
          if (minPrice != null) 'min_price': minPrice,
          if (maxPrice != null) 'max_price': maxPrice,
          'sort': sort,
          'limit': limit,
          'offset': offset,
          if (gender != null) 'gender': gender,
          if (sources != null) 'sources': sources,
        });
        return SearchResult.fromJson(response.data);
      } on DioException catch (e) {
        if (e.response?.statusCode == 429 && attempt < 2) {
          // Wait before retrying (exponential backoff: 2s, 4s)
          final wait = Duration(seconds: 2 * (attempt + 1));
          debugPrint('⏳ Rate limited (429), retrying in ${wait.inSeconds}s...');
          await Future.delayed(wait);
          continue;
        }
        rethrow;
      }
    }
    // Should not reach here, but just in case
    throw Exception('Search failed after retries');
  }

  /// Instant search — skipped if endpoint doesn't exist (404).
  /// Returns null on any error so it never blocks the main search.
  Future<SearchResult?> instantSearch(String query) async {
    try {
      final response = await _api.get(
        '/deals/search/',
        params: {'q': query.trim(), 'limit': 10},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && (data['deals'] as List?)?.isNotEmpty == true) {
        return SearchResult.fromJson(data);
      }
      return null;
    } catch (_) {
      return null; // don't block on errors — main search will handle it
    }
  }

  // ─── Trending ──────────────────────────────────

  Future<SearchResult> getTrending({
    int limit = 20,
    String sort = 'relevance',
  }) async {
    final response = await _api.get('/deals/', params: {
      'limit': limit,
      'sort': sort,
    });
    return SearchResult.fromJson(response.data);
  }

  // ─── Image Search (Core Flow) ──────────────────

  Future<SearchResult> imageSearch(File imageFile) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'photo.jpg',
      ),
    });

    final response = await _api.uploadFile('/deals/image-search/', formData);
    return SearchResult.fromJson(response.data);
  }

  // ─── Price Comparison ─────────────────────────

  /// Compare a product's price against similar items via backend.
  /// Returns the full comparison data as a Map.
  Future<Map<String, dynamic>?> comparePrices({
    required String title,
    required double price,
    String source = '',
  }) async {
    try {
      final response = await _api.post('/deals/compare/', data: {
        'title': title,
        'price': price,
        'source': source,
      });
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Price comparison failed: $e');
      return null;
    }
  }
}
