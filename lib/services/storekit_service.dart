import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  // Broadcast streams — multiple listeners are safe, nothing is overwritten
  // when a new screen mounts. Events keep flowing even if no one is
  // currently listening (e.g. app backgrounded mid-purchase).
  final StreamController<PurchaseDetails> _successController =
      StreamController<PurchaseDetails>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<PurchaseDetails> get purchaseSuccessStream => _successController.stream;
  Stream<String> get purchaseErrorStream => _errorController.stream;

  // Cached products — exposed read-only so callers can't mutate the list.
  final List<ProductDetails> _products = [];
  List<ProductDetails> get products => List.unmodifiable(_products);

  // Pending-receipt persistence: if /payments/verify-ios/ fails we queue the
  // receipt here and retry on the next app launch / explicit flush. Without
  // this the backend can miss the purchase and leave the user looking
  // premium locally but free server-side.
  static const _pendingReceiptsKey = 'pending_ios_receipts';
  static const _storage = FlutterSecureStorage();

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
    debugPrint('StoreKit: initialized with ${_products.length} products');

    // Fire-and-forget: retry any receipts that failed to verify last run.
    unawaited(flushPendingReceipts());
  }

  /// Fetch available products from App Store.
  Future<List<ProductDetails>> fetchProducts() async {
    if (!_available) return [];

    try {
      final response = await _iap.queryProductDetails(productIds);

      if (response.error != null) {
        debugPrint('StoreKit: product query error: ${response.error}');
        return products;
      }

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('StoreKit: products not found: ${response.notFoundIDs}');
      }

      _products
        ..clear()
        ..addAll(response.productDetails);

      // Sort: monthly first, then weekly
      _products.sort((a, b) {
        if (a.id.contains('monthly')) return -1;
        if (b.id.contains('monthly')) return 1;
        return 0;
      });

      return products;
    } catch (e) {
      debugPrint('StoreKit: fetchProducts error: $e');
      return products;
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
          final code = purchase.error?.code ?? '';
          final msg = purchase.error?.message ?? '';
          debugPrint('StoreKit: purchase error: $code $msg');
          // Emit a structured code so UI can differentiate.
          _errorController.add(code.isNotEmpty ? code : (msg.isNotEmpty ? msg : 'error'));
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
          _errorController.add('canceled');
          break;
      }
    }
  }

  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    final receiptData = purchase.verificationData.serverVerificationData;
    final payload = {
      'receipt_data': receiptData,
      'product_id': purchase.productID,
      'transaction_id': purchase.purchaseID,
    };

    bool verified = false;
    try {
      final api = ApiClient();
      if (await api.hasTokens()) {
        await api.post(
          '/payments/verify-ios/',
          fullUrl: 'https://api.outfi.ai/api/v1/payments/verify-ios/',
          data: payload,
        );
        verified = true;
        debugPrint('StoreKit: receipt verified on server');
      }
    } catch (e) {
      debugPrint('StoreKit: server verification failed — queuing for retry: $e');
      await _queuePendingReceipt(payload);
    }

    // Grant access locally regardless — server will eventually sync (either
    // via the queued retry above or App Store Server Notifications).
    _successController.add(purchase);

    // Mark this purchase as handled with StoreKit so it doesn't replay.
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }

    if (!verified) {
      // Try again immediately in the background — one quick retry covers
      // transient blips without waiting for the next cold start.
      unawaited(flushPendingReceipts());
    }
  }

  // ── Pending receipt queue ──────────────────────────────────

  Future<void> _queuePendingReceipt(Map<String, dynamic> payload) async {
    try {
      final raw = await _storage.read(key: _pendingReceiptsKey);
      final List<dynamic> list = raw == null ? [] : (jsonDecode(raw) as List);
      // De-dupe by transaction_id so a repeated retry of the same receipt
      // doesn't grow the queue unbounded.
      final txId = payload['transaction_id'];
      list.removeWhere((e) => e is Map && e['transaction_id'] == txId);
      list.add(payload);
      await _storage.write(key: _pendingReceiptsKey, value: jsonEncode(list));
    } catch (e) {
      debugPrint('StoreKit: failed to persist pending receipt: $e');
    }
  }

  /// Retry any receipts that previously failed server verification.
  /// Safe to call multiple times — it no-ops when the queue is empty.
  Future<void> flushPendingReceipts() async {
    List<dynamic> list;
    try {
      final raw = await _storage.read(key: _pendingReceiptsKey);
      if (raw == null) return;
      list = jsonDecode(raw) as List;
    } catch (e) {
      debugPrint('StoreKit: pending queue read failed: $e');
      return;
    }
    if (list.isEmpty) return;

    final api = ApiClient();
    if (!await api.hasTokens()) return;

    final remaining = <dynamic>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      try {
        await api.post(
          '/payments/verify-ios/',
          fullUrl: 'https://api.outfi.ai/api/v1/payments/verify-ios/',
          data: Map<String, dynamic>.from(entry),
        );
        debugPrint('StoreKit: flushed pending receipt ${entry['transaction_id']}');
      } catch (e) {
        debugPrint('StoreKit: flush failed for ${entry['transaction_id']}: $e');
        remaining.add(entry);
      }
    }

    try {
      if (remaining.isEmpty) {
        await _storage.delete(key: _pendingReceiptsKey);
      } else {
        await _storage.write(
            key: _pendingReceiptsKey, value: jsonEncode(remaining));
      }
    } catch (e) {
      debugPrint('StoreKit: pending queue write failed: $e');
    }
  }

  // ── Cleanup ────────────────────────────────────────────────

  void dispose() {
    _subscription?.cancel();
    _successController.close();
    _errorController.close();
  }
}
