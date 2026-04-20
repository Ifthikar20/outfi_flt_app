import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/freemium_gate_service.dart';
import '../services/payment_service.dart';
import '../services/storekit_service.dart';
import '../theme/app_theme.dart';

/// Shows the Outfi Premium paywall as a bottom sheet modal.
///
/// Replaces the old full-page `/premium` route. Keeps the same IAP flow
/// (StoreKit products + purchase stream) but presents it as a compact
/// sheet with a Weekly / Monthly toggle.
///
/// Returns `true` when the user completes a purchase (or restore that
/// succeeds), `false` otherwise.
Future<bool> showPaywallSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    useRootNavigator: true,
    builder: (_) => const _PaywallSheet(),
  );
  return result ?? false;
}

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet();

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  final _storeKit = StoreKitService();
  late final PaymentService _payments;

  List<ProductDetails> _products = [];
  ProductDetails? _selected;
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  bool _success = false;

  StreamSubscription<PurchaseDetails>? _successSub;
  StreamSubscription<String>? _errorSub;

  static const _red = Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _payments = PaymentService(ApiClient());
    _successSub = _storeKit.purchaseSuccessStream.listen(_onSuccess);
    _errorSub = _storeKit.purchaseErrorStream.listen(_onError);
    _loadProducts();
  }

  @override
  void dispose() {
    _successSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    // Fast path: StoreKitService warms products in main().
    final cached = _storeKit.products;
    if (cached.isNotEmpty) {
      _applyProducts(cached);
      return;
    }
    try {
      final products =
          await _payments.getProducts().timeout(const Duration(seconds: 5));
      if (!mounted) return;
      _applyProducts(products);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load plans. Check your connection.';
      });
    }
  }

  void _applyProducts(List<ProductDetails> products) {
    // Prefer the monthly plan by default — higher conversion in the mock.
    ProductDetails? monthly;
    for (final p in products) {
      if (p.id.toLowerCase().contains('monthly')) {
        monthly = p;
        break;
      }
    }
    setState(() {
      _products = products;
      _selected = monthly ?? (products.isNotEmpty ? products.first : null);
      _loading = false;
      if (products.isEmpty) {
        _error = 'Plans are taking longer than usual. Try again.';
      }
    });
  }

  void _onSuccess(PurchaseDetails _) {
    FreemiumGateService().clearPremiumCache();
    if (!mounted) return;
    setState(() {
      _success = true;
      _purchasing = false;
    });
    // Pop with `true` after a short celebration.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  void _onError(String code) {
    if (!mounted) return;
    setState(() {
      _purchasing = false;
      _error = _errorCopy(code);
    });
  }

  String? _errorCopy(String code) {
    final c = code.toLowerCase();
    if (c == 'canceled') return null;
    if (c.contains('network') || c.contains('timeout')) {
      return 'Network issue. Check your connection and try again.';
    }
    if (c.contains('already') || c.contains('owned')) {
      return "You're already subscribed. Try Restore Purchase.";
    }
    if (c.contains('payment') || c.contains('declined') || c.contains('invalid')) {
      return 'Payment was declined. Try another method in Apple ID.';
    }
    return 'Purchase failed. Please try again.';
  }

  Future<void> _subscribe() async {
    if (_selected == null || _purchasing) return;
    setState(() {
      _purchasing = true;
      _error = null;
    });
    FreemiumGateService().clearPremiumCache();
    try {
      await _payments.subscribe(_selected!);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _purchasing = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _restore() async {
    if (_purchasing) return;
    setState(() {
      _purchasing = true;
      _error = null;
    });
    try {
      await _payments.restore();
      // Give the purchase stream a moment. If nothing restored, re-check.
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted || _success) return;
      final status = await _payments.getStatus();
      if (!mounted) return;
      if (status['is_premium'] == true) {
        _onSuccess(PurchaseDetails(
          productID: _selected?.id ?? '',
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'app_store',
          ),
          transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
          status: PurchaseStatus.restored,
        ));
      } else {
        setState(() {
          _purchasing = false;
          _error = 'No subscription found.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _purchasing = false;
        _error = 'Could not restore.';
      });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── UI ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.45,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: _success ? _buildSuccess() : _buildContent(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Close button (top right).
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 24),
            splashRadius: 20,
          ),
        ),

        // Mascot.
        Center(
          child: Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_offer_rounded,
                size: 48, color: _red),
          ),
        ),
        const SizedBox(height: 20),

        // Title.
        const Text(
          'Limited time offer',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),

        // Price (selected plan).
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(color: _red)),
          )
        else if (selected != null)
          _priceRow(selected)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              _error ?? 'Plans unavailable.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14),
            ),
          ),

        const SizedBox(height: 16),

        // Primary CTA.
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: (selected == null || _purchasing) ? null : _subscribe,
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _red.withValues(alpha: 0.4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _purchasing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.4),
                  )
                : const Text(
                    'Redeem Offer',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Weekly / Monthly toggle at the bottom.
        if (_products.length >= 2) _planToggle(),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.error, fontSize: 13),
          ),
        ],

        const SizedBox(height: 10),

        // Legal footer.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => _openUrl('https://outfi.ai/terms'),
              child: const Text(
                'TERMS OF USE',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Text('·',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            TextButton(
              onPressed: () => _openUrl('https://outfi.ai/privacy'),
              child: const Text(
                'PRIVACY POLICY',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),

        Center(
          child: TextButton(
            onPressed: _purchasing ? null : _restore,
            child: Text(
              'Restore Purchase',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _priceRow(ProductDetails selected) {
    final isMonthly = selected.id.toLowerCase().contains('monthly');
    final period = isMonthly ? '/mo' : '/wk';
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // Strike-through "was" price — show opposite plan if present.
            _strikePriceForOppositePlan(isMonthly),
            const SizedBox(width: 10),
            Text(
              '${selected.price}$period',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: -0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Billed as ${selected.price} per ${isMonthly ? 'month' : 'week'}',
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _strikePriceForOppositePlan(bool currentIsMonthly) {
    ProductDetails? other;
    for (final p in _products) {
      final m = p.id.toLowerCase().contains('monthly');
      if (m != currentIsMonthly) {
        other = p;
        break;
      }
    }
    if (other == null) return const SizedBox.shrink();
    return Text(
      other.price,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppTheme.textMuted,
        decoration: TextDecoration.lineThrough,
        decorationColor: AppTheme.textMuted.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _planToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: _products.map((p) {
          final active = _selected?.id == p.id;
          final isMonthly = p.id.toLowerCase().contains('monthly');
          final label = isMonthly ? 'Monthly' : 'Weekly';
          return Expanded(
            child: GestureDetector(
              onTap: _purchasing ? null : () => setState(() => _selected = p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSuccess() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: AppTheme.success,
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.check_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          const Text(
            "You're in.",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Premium is active. Enjoy unlimited deals.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
