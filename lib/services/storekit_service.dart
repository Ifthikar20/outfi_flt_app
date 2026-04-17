import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_client.dart';

/// Native StoreKit service — manages Apple IAP subscriptions directly.
///
/// Uses Flutter's official `in_app_purchase` package. No third-party
/// service needed. Apple handles payment, receipt validation is done
/// on our backend.
class StoreKitService {
  static final StoreKitService _instance = StoreKitService._();
  factory StoreKitService() => _instance;
  StoreKitService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _initialized = false;
  bool _available = false;

  // Product IDs matching App Store Connect
  static const Set<String> productIds = {
    'com.outfi.outfiApp.premium.monthly',
    'com.outfi.outfiApp.premium.biweekly', // Weekly plan
  };

  // Callbacks
  Function(PurchaseDetails)? onPurchaseSuccess;
  Function(String)? onPurchaseError;

  // Cached products
  List<ProductDetails> products = [];

  // ── Initialization ─────────────────────────────────────────

  /// Initialize StoreKit. Call once in main().
  Future<void> init() async {
    if (_initialized) return;

    _available = await _iap.isAvailable();
    if (!_available) {
      debugPrint('StoreKit: IAP not available on this device');
      return;
    }

    // Listen to purchase stream
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (error) {
        debugPrint('StoreKit: purchase stream error: $error');
      },
    );

    // Pre-fetch products
    await fetchProducts();

    _initialized = true;
    debugPrint('StoreKit: initialized with ${products.length} products');
  }

  /// Fetch available products from App Store.
  Future<List<ProductDetails>> fetchProducts() async {
    if (!_available) return [];

    try {
      final response = await _iap.queryProductDetails(productIds);

      if (response.error != null) {
        debugPrint('StoreKit: product query error: ${response.error}');
        return [];
      }

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('StoreKit: products not found: ${response.notFoundIDs}');
      }

      products = response.productDetails.toList();

      // Sort: monthly first, then weekly
      products.sort((a, b) {
        if (a.id.contains('monthly')) return -1;
        if (b.id.contains('monthly')) return 1;
        return 0;
      });

      return products;
    } catch (e) {
      debugPrint('StoreKit: fetchProducts error: $e');
      return [];
    }
  }

  // ── Purchase ───────────────────────────────────────────────

  /// Purchase a subscription. Shows native iOS subscription sheet.
  Future<void> purchaseProduct(ProductDetails product) async {
    if (!_available) {
      throw Exception('In-app purchases not available');
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    // Subscriptions use buyNonConsumable
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    // Result comes via the purchase stream listener
  }

  // ── Restore ────────────────────────────────────────────────

  /// Restore previous purchases (after reinstall / device switch).
  Future<void> restorePurchases() async {
    if (!_available) {
      throw Exception('In-app purchases not available');
    }
    await _iap.restorePurchases();
    // Results come via the purchase stream listener
  }

  // ── Purchase Stream Handler ────────────────────────────────

  void _onPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _handleSuccessfulPurchase(purchase);
          break;
        case PurchaseStatus.error:
          debugPrint('StoreKit: purchase error: ${purchase.error?.message}');
          onPurchaseError?.call(
              purchase.error?.message ?? 'Purchase failed');
          // Still need to complete the purchase to clear the queue
          if (purchase.pendingCompletePurchase) {
            _iap.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.pending:
          debugPrint('StoreKit: purchase pending');
          break;
        case PurchaseStatus.canceled:
          debugPrint('StoreKit: purchase canceled by user');
          onPurchaseError?.call('canceled');
          break;
      }
    }
  }

  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    try {
      // Send receipt to backend for verification
      final receiptData =
          purchase.verificationData.serverVerificationData;

      final api = ApiClient();
      final hasTokens = await api.hasTokens();
      if (hasTokens) {
        await api.post(
          '/payments/verify-ios/',
          fullUrl: 'https://api.outfi.ai/api/v1/payments/verify-ios/',
          data: {
            'receipt_data': receiptData,
            'product_id': purchase.productID,
            'transaction_id': purchase.purchaseID,
          },
        );
        debugPrint('StoreKit: receipt verified on server');
      }

      onPurchaseSuccess?.call(purchase);
    } catch (e) {
      debugPrint('StoreKit: server verification failed: $e');
      // Still grant access locally — server will sync via notifications
      onPurchaseSuccess?.call(purchase);
    } finally {
      // IMPORTANT: Always complete the purchase
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  // ── Cleanup ────────────────────────────────────────────────

  void dispose() {
    _subscription?.cancel();
  }
}
