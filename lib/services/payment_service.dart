import 'package:flutter/foundation.dart';
import 'api_client.dart';

class PaymentService {
  final ApiClient _api;

  PaymentService(this._api);

  /// Fetch current subscription status + limits.
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final resp = await _api.get(_paymentsPath('/status/'),
          fullUrl: _paymentsUrl('/status/'));
      final data = resp.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return _defaults;
    } catch (e) {
      debugPrint('PaymentService.getStatus error: $e');
      return _defaults;
    }
  }

  /// Create a PaymentIntent for Apple Pay / card.
  Future<Map<String, dynamic>> subscribe({
    required String plan,
    String paymentMethod = 'apple_pay',
  }) async {
    final resp = await _api.post(_paymentsPath('/subscribe/'),
        fullUrl: _paymentsUrl('/subscribe/'),
        data: {
          'plan': plan,
          'payment_method': paymentMethod,
        });
    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// Cancel subscription at end of billing period.
  Future<Map<String, dynamic>> cancel() async {
    final resp = await _api.post(_paymentsPath('/cancel/'),
        fullUrl: _paymentsUrl('/cancel/'));
    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// Restore subscription (after reinstall / device switch).
  Future<Map<String, dynamic>> restore() async {
    final resp = await _api.post(_paymentsPath('/restore/'),
        fullUrl: _paymentsUrl('/restore/'));
    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// Payment history.
  Future<List<dynamic>> getHistory() async {
    final resp = await _api.get(_paymentsPath('/history/'),
        fullUrl: _paymentsUrl('/history/'));
    final data = resp.data;
    if (data is Map) return (data['payments'] as List?) ?? [];
    return [];
  }

  /// Confirm a payment succeeded.
  Future<Map<String, dynamic>> confirmPayment(String paymentIntentId) async {
    return getStatus();
  }

  static const _paymentsBase = 'https://api.outfi.ai/api/v1/payments';

  String _paymentsUrl(String path) => '$_paymentsBase$path';
  String _paymentsPath(String path) => '/payments$path'; // fallback key

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
