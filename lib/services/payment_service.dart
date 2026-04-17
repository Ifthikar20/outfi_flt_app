import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_client.dart';
import 'storekit_service.dart';

/// Payment service — uses native Apple StoreKit for IAP subscriptions.
///
/// Purchases go through Apple's native StoreKit. The backend is notified
/// via receipt verification and App Store Server Notifications.
class PaymentService {
  final ApiClient _api;
  final StoreKitService _storeKit = StoreKitService();

  PaymentService(this._api);

  /// Fetch current subscription status from server.
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final resp = await _api.get(_paymentsPath('/status/'),
          fullUrl: _paymentsUrl('/status/'));
      final data = resp.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('PaymentService: status check failed: $e');
    }
    return _defaults;
  }

  /// Check if user is premium.
  Future<bool> isPremium() async {
    final status = await getStatus();
    return status['is_premium'] == true;
  }

  /// Get available subscription products from App Store.
  Future<List<ProductDetails>> getProducts() async {
    return await _storeKit.fetchProducts();
  }

  /// Purchase a product via Apple IAP.
  ///
  /// Shows the native iOS subscription confirmation sheet.
  /// Results are delivered via StoreKitService callbacks.
  Future<void> subscribe(ProductDetails product) async {
    await _storeKit.purchaseProduct(product);
  }

  /// Cancel subscription.
  ///
  /// Apple subscriptions are managed by the user in iOS Settings.
  Future<Map<String, dynamic>> cancel() async {
    return {'message': 'To cancel, go to Settings → Apple ID → Subscriptions.'};
  }

  /// Restore previous purchases.
  Future<void> restore() async {
    await _storeKit.restorePurchases();
  }

  /// Payment history (from server).
  Future<List<dynamic>> getHistory() async {
    try {
      final resp = await _api.get(_paymentsPath('/history/'),
          fullUrl: _paymentsUrl('/history/'));
      final data = resp.data;
      if (data is Map) return (data['payments'] as List?) ?? [];
    } catch (_) {}
    return [];
  }

  // ── Helpers ─────────────────────────────────────────────────

  static const _paymentsBase = 'https://api.outfi.ai/api/v1/payments';

  String _paymentsUrl(String path) => '$_paymentsBase$path';
  String _paymentsPath(String path) => '/payments$path';

  static const _defaults = {
    'plan': 'free',
    'is_premium': false,
    'limits': {
      'daily_image_searches': 5,
      'daily_price_alerts': 10,
      'saved_deals_max': 50,
      'storyboards_max': 5,
      'ad_free': false,
    },
  };
}
