import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'payment_service.dart';
import 'api_client.dart';

/// Lightweight freemium gate that tracks usage counters and decides
/// whether to let the user through or show the paywall.
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

  // Cached premium status (refreshed on each check)
  bool? _isPremiumCached;

  /// Check with backend whether the user has an active premium subscription.
  /// Caches the result in memory for the session.
  Future<bool> isPremium() async {
    if (_isPremiumCached != null) return _isPremiumCached!;
    try {
      final status = await PaymentService(ApiClient()).getStatus();
      _isPremiumCached = status['is_premium'] == true;
    } catch (_) {
      _isPremiumCached = false;
    }
    return _isPremiumCached!;
  }

  /// Force-refresh premium status (call after a successful purchase).
  void clearPremiumCache() => _isPremiumCached = null;

  // ─── Buy Now gate ──────────────────────────────

  /// Returns true if the user can proceed with a Buy redirect.
  /// First click is free; second click requires premium.
  Future<bool> canBuy() async {
    if (await isPremium()) return true;
    final count = int.tryParse(await _storage.read(key: _keyBuyCount) ?? '') ?? 0;
    return count < maxFreeBuys;
  }

  /// Call AFTER a successful buy redirect to record usage.
  Future<void> recordBuyClick() async {
    final count = int.tryParse(await _storage.read(key: _keyBuyCount) ?? '') ?? 0;
    await _storage.write(key: _keyBuyCount, value: '${count + 1}');
  }

  // ─── Image search gate ─────────────────────────

  /// Returns true if the user can perform an image search today.
  /// 3 free per calendar day; resets at midnight.
  Future<bool> canImageSearch() async {
    if (await isPremium()) return true;
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
  }

  /// Remaining free image searches today (for UI display).
  Future<int> remainingImageSearches() async {
    if (await isPremium()) return 999;
    final today = _todayString();
    final storedDate = await _storage.read(key: _keyImageSearchDate) ?? '';
    if (storedDate != today) return maxFreeImageSearchesPerDay;
    final count = int.tryParse(await _storage.read(key: _keyImageSearchCount) ?? '') ?? 0;
    return (maxFreeImageSearchesPerDay - count).clamp(0, maxFreeImageSearchesPerDay);
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
