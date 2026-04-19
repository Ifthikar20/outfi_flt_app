import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'payment_service.dart';
import 'api_client.dart';
import 'storekit_service.dart';

/// Hybrid freemium gate that checks server-side subscription status
/// and falls back to local counters when offline.
///
/// Rules:
///   - Buy Now: 1 free redirect, 2nd click → paywall
///   - Image search: 3 free per day, then → paywall
///   - Fashion boards, saves, alerts: always free
///   - Premium users: no gates
class FreemiumGateService {
  static final FreemiumGateService _instance = FreemiumGateService._();
  factory FreemiumGateService() => _instance;
  FreemiumGateService._();

  static const _storage = FlutterSecureStorage();

  // Storage keys
  static const _keyBuyCount = 'freemium_buy_count';
  static const _keyImageSearchCount = 'freemium_img_search_count';
  static const _keyImageSearchDate = 'freemium_img_search_date';

  // Free tier limits
  static const int maxFreeBuys = 1;
  static const int maxFreeImageSearchesPerDay = 3;

  // Cached premium status — refreshed on each gate check
  bool? _isPremiumCached;
  DateTime? _premiumCacheTime;

  StreamSubscription? _purchaseSub;

  /// Wire up cache invalidation so a successful purchase anywhere in the app
  /// drops the 5-minute TTL immediately. Call once from main() after
  /// `StoreKitService().init()`.
  void attachToStoreKit() {
    _purchaseSub?.cancel();
    _purchaseSub = StoreKitService().purchaseSuccessStream.listen((_) {
      clearPremiumCache();
      // Warm the cache so the next gate check is instant.
      unawaited(isPremium());
    });
  }

  /// Check whether the user has an active premium subscription.
  ///
  /// Checks server API → cached value → false.
  /// Caches for 5 minutes to avoid hammering on every tap.
  Future<bool> isPremium() async {
    // Refresh cache every 5 minutes
    if (_isPremiumCached != null &&
        _premiumCacheTime != null &&
        DateTime.now().difference(_premiumCacheTime!).inMinutes < 5) {
      return _isPremiumCached!;
    }

    // Server-side check (synced via App Store Server Notifications)
    try {
      final status = await PaymentService(ApiClient()).getStatus();
      _isPremiumCached = status['is_premium'] == true;
      _premiumCacheTime = DateTime.now();
    } catch (_) {
      // Offline — use last known value, or default to false
      _isPremiumCached ??= false;
    }
    return _isPremiumCached!;
  }

  /// Force-refresh premium status (call after a successful purchase).
  void clearPremiumCache() {
    _isPremiumCached = null;
    _premiumCacheTime = null;
  }

  // ─── Buy Now gate ──────────────────────────────

  /// Returns true if the user can proceed with a Buy redirect.
  /// First click is free; second click requires premium.
  Future<bool> canBuy() async {
    if (await isPremium()) return true;

    // Try server-side check first
    final serverQuota = await _fetchServerQuota();
    if (serverQuota != null) {
      return (serverQuota['buy_remaining'] as int? ?? 0) > 0;
    }

    // Offline fallback: local counter
    final count = int.tryParse(await _storage.read(key: _keyBuyCount) ?? '') ?? 0;
    return count < maxFreeBuys;
  }

  /// Call AFTER a successful buy redirect to record usage.
  Future<void> recordBuyClick() async {
    final count = int.tryParse(await _storage.read(key: _keyBuyCount) ?? '') ?? 0;
    await _storage.write(key: _keyBuyCount, value: '${count + 1}');

    // Sync to server (fire-and-forget)
    _syncUsageToServer('buy');
  }

  // ─── Image search gate ─────────────────────────

  /// Returns true if the user can perform an image search today.
  /// 3 free per calendar day; resets at midnight.
  Future<bool> canImageSearch() async {
    if (await isPremium()) return true;

    // Try server-side check first
    final serverQuota = await _fetchServerQuota();
    if (serverQuota != null) {
      return (serverQuota['image_search_remaining'] as int? ?? 0) > 0;
    }

    // Offline fallback: local counter
    final today = _todayString();
    final storedDate = await _storage.read(key: _keyImageSearchDate) ?? '';
    if (storedDate != today) return true; // new day → fresh quota
    final count = int.tryParse(await _storage.read(key: _keyImageSearchCount) ?? '') ?? 0;
    return count < maxFreeImageSearchesPerDay;
  }

  /// Call AFTER a successful image search to record usage.
  Future<void> recordImageSearch() async {
    final today = _todayString();
    final storedDate = await _storage.read(key: _keyImageSearchDate) ?? '';
    int count;
    if (storedDate != today) {
      // New day — reset counter
      count = 0;
      await _storage.write(key: _keyImageSearchDate, value: today);
    } else {
      count = int.tryParse(await _storage.read(key: _keyImageSearchCount) ?? '') ?? 0;
    }
    await _storage.write(key: _keyImageSearchCount, value: '${count + 1}');

    // Sync to server (fire-and-forget)
    _syncUsageToServer('image_search');
  }

  /// Remaining free image searches today (for UI display).
  Future<int> remainingImageSearches() async {
    if (await isPremium()) return 999;

    // Try server first
    final serverQuota = await _fetchServerQuota();
    if (serverQuota != null) {
      return serverQuota['image_search_remaining'] as int? ?? 0;
    }

    // Offline fallback
    final today = _todayString();
    final storedDate = await _storage.read(key: _keyImageSearchDate) ?? '';
    if (storedDate != today) return maxFreeImageSearchesPerDay;
    final count = int.tryParse(await _storage.read(key: _keyImageSearchCount) ?? '') ?? 0;
    return (maxFreeImageSearchesPerDay - count).clamp(0, maxFreeImageSearchesPerDay);
  }

  // ─── Server sync helpers ───────────────────────

  /// Fetch server-side quota status. Returns null if offline or endpoint
  /// doesn't exist yet (backwards compatible).
  Future<Map<String, dynamic>?> _fetchServerQuota() async {
    try {
      final api = ApiClient();
      if (!await api.hasTokens()) return null;
      final response = await api.get('/usage/status/');
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
    } catch (e) {
      debugPrint('Freemium: server quota check unavailable — using local: $e');
    }
    return null;
  }

  /// Notify server of a usage event (fire-and-forget).
  void _syncUsageToServer(String action) {
    Future(() async {
      try {
        final api = ApiClient();
        if (!await api.hasTokens()) return;
        await api.post('/usage/record/', data: {'action': action});
      } catch (e) {
        debugPrint('Freemium: usage sync failed — will re-sync later: $e');
      }
    });
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
