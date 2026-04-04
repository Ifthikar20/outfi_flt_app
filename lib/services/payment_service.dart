import 'package:flutter/foundation.dart';
import 'api_client.dart';

class PaymentService {
  final ApiClient _api;

  PaymentService(this._api);

  /// Fetch current subscription status + limits.
  Future<Map<String, dynamic>> getStatus() async {
    try {
      // Payments endpoints are under /api/v1/payments/, not /api/v1/mobile/
      final resp = await _api.dio.get(
        _paymentsUrl('/status/'),
      );
      return _decode(resp.data);
    } catch (e) {
      debugPrint('PaymentService.getStatus error: $e');
      return {
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
  }

  /// Create a PaymentIntent for Apple Pay / card.
  /// Returns client_secret, ephemeral_key, customer_id, publishable_key.
  Future<Map<String, dynamic>> subscribe({
    required String plan,
    String paymentMethod = 'apple_pay',
  }) async {
    final resp = await _api.dio.post(
      _paymentsUrl('/subscribe/'),
      data: {
        'plan': plan,
        'payment_method': paymentMethod,
      },
    );
    return _decode(resp.data);
  }

  /// Cancel subscription at end of billing period.
  Future<Map<String, dynamic>> cancel() async {
    final resp = await _api.dio.post(_paymentsUrl('/cancel/'));
    return _decode(resp.data);
  }

  /// Restore subscription (after reinstall / device switch).
  Future<Map<String, dynamic>> restore() async {
    final resp = await _api.dio.post(_paymentsUrl('/restore/'));
    return _decode(resp.data);
  }

  /// Payment history.
  Future<List<dynamic>> getHistory() async {
    final resp = await _api.dio.get(_paymentsUrl('/history/'));
    final data = _decode(resp.data);
    return data['payments'] ?? [];
  }

  /// Confirm a payment succeeded (poll after Apple Pay sheet dismisses).
  Future<Map<String, dynamic>> confirmPayment(String paymentIntentId) async {
    // After Apple Pay succeeds, the webhook handles activation.
    // This just re-fetches status to check if it's been activated.
    return getStatus();
  }

  // Payments lives at /api/v1/payments/, not under /mobile/
  String _paymentsUrl(String path) {
    // ApiClient baseUrl is .../api/v1/mobile — go up one level
    return '../payments$path';
  }

  Map<String, dynamic> _decode(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }
}
