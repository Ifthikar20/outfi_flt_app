import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/freemium_gate_service.dart';
import '../services/payment_service.dart';
import '../services/storekit_service.dart';

/// Outfi Premium paywall — Apple IAP only (StoreKit).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  bool _success = false;

  late final PaymentService _paymentService;
  final StoreKitService _storeKit = StoreKitService();
  List<ProductDetails> _products = [];
  ProductDetails? _selectedProduct;

  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _paymentService = PaymentService(ApiClient());
    _storeKit.onPurchaseSuccess = _onPurchaseSuccess;
    _storeKit.onPurchaseError = _onPurchaseError;

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _loadProducts();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _paymentService.getProducts();
      if (mounted) {
        setState(() {
          _products = products;
          _selectedProduct = products.isNotEmpty ? products.first : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load plans. Check your connection.';
        });
      }
    }
  }

  void _onPurchaseSuccess(PurchaseDetails purchase) {
    FreemiumGateService().clearPremiumCache();
    if (mounted) setState(() { _success = true; _purchasing = false; });
  }

  void _onPurchaseError(String error) {
    if (mounted) {
      setState(() {
        _purchasing = false;
        if (error != 'canceled') _error = 'Purchase failed. Please try again.';
      });
    }
  }

  Future<void> _subscribe() async {
    if (_selectedProduct == null) return;
    setState(() { _purchasing = true; _error = null; });
    try {
      await _paymentService.subscribe(_selectedProduct!);
    } catch (e) {
      if (mounted) {
        setState(() { _purchasing = false; _error = 'Something went wrong.'; });
      }
    }
  }

  Future<void> _restore() async {
    setState(() { _purchasing = true; _error = null; });
    try {
      await _paymentService.restore();
      await Future.delayed(const Duration(seconds: 3));
      final status = await _paymentService.getStatus();
      if (status['is_premium'] == true) {
        FreemiumGateService().clearPremiumCache();
        if (mounted) setState(() => _success = true);
      } else {
        if (mounted) setState(() => _error = 'No subscription found.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not restore.');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_success) return _buildSuccess();
    return Scaffold(
      backgroundColor: const Color(0xFF1A1714),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _buildPaywall(),
    );
  }

  Widget _buildPaywall() {
    return Stack(
      children: [
        // Background gradient
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF2A2420),
                  Color(0xFF1A1714),
                  Color(0xFF1A1714),
                ],
              ),
            ),
          ),
        ),

        // Gold glow at top
        Positioned(
          top: -80,
          left: 0,
          right: 0,
          child: Container(
            height: 250,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  AppTheme.accent.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              // Close button
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      // Crown icon
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.accent,
                              AppTheme.accentDark,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.3),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.diamond_outlined, color: Colors.white, size: 34),
                      ),

                      const SizedBox(height: 20),

                      // Title
                      const Text(
                        'Outfi Premium',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Elevate your style discovery',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Feature list
                      _featureRow(Icons.search, 'Image Search', '25 searches per day'),
                      _featureRow(Icons.notifications_active_outlined, 'Price Alerts', 'Up to 100 active alerts'),
                      _featureRow(Icons.bookmark_outline, 'Saved Deals', 'Save up to 1,000 deals'),
                      _featureRow(Icons.dashboard_outlined, 'Style Boards', 'Create up to 50 boards'),
                      _featureRow(Icons.block, 'Ad-Free', 'Clean, uninterrupted experience'),

                      const SizedBox(height: 36),

                      // Plan cards
                      if (_products.isEmpty && _error == null)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Text(
                            'Plans are being set up.\nPlease try again shortly.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                        ),

                      ..._products.map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _planCard(p),
                          )),

                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppTheme.error, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 28),

                      // Subscribe button
                      AnimatedBuilder(
                        animation: _shimmerCtrl,
                        builder: (context, child) {
                          return Container(
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: (_purchasing || _selectedProduct == null)
                                    ? [Colors.grey.shade800, Colors.grey.shade700]
                                    : [AppTheme.accent, AppTheme.accentDark, AppTheme.accent],
                                stops: (_purchasing || _selectedProduct == null)
                                    ? null
                                    : [0.0, _shimmerCtrl.value, 1.0],
                              ),
                              boxShadow: (_purchasing || _selectedProduct == null)
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: AppTheme.accent.withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: (_purchasing || _selectedProduct == null) ? null : _subscribe,
                                child: Center(
                                  child: _purchasing
                                      ? const SizedBox(
                                          width: 24, height: 24,
                                          child: CircularProgressIndicator(
                                              color: Colors.white, strokeWidth: 2.5))
                                      : const Text(
                                          'Subscribe Now',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 14),

                      // Restore
                      TextButton(
                        onPressed: _purchasing ? null : _restore,
                        child: Text(
                          'Restore Purchase',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 14,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Legal
                      Text(
                        'Payment is charged to your Apple ID account.\n'
                        'Subscription auto-renews unless turned off at least\n'
                        '24 hours before the end of the current period.\n'
                        'Manage in Settings → Apple ID → Subscriptions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.25),
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(ProductDetails product) {
    final selected = _selectedProduct == product;
    final isMonthly = product.id.contains('monthly');
    final title = isMonthly ? 'Monthly' : 'Weekly';
    final period = isMonthly ? '/month' : '/week';

    return GestureDetector(
      onTap: () => setState(() => _selectedProduct = product),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.accent : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppTheme.accent : Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accent,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // Title + badge
            Expanded(
              child: Row(
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                  if (isMonthly) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.accent, AppTheme.accentDark],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('SAVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                    ),
                  ],
                ],
              ),
            ),

            // Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(product.price,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                Text(period,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Success ────────────────────────────────────────────

  Widget _buildSuccess() {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1714),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.3),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 28),
              const Text(
                'Welcome to Premium',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You now have full access to image searches,\nprice alerts, and an ad-free experience.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.5),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Start Exploring',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
