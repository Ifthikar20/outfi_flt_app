import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/freemium_gate_service.dart';
import '../services/payment_service.dart';

/// Outfi Premium paywall.
///
/// On a real iPhone with Apple Pay: shows the native Apple Pay sheet.
/// On simulator / no Apple Pay: shows Stripe's card payment sheet.
///
/// The user NEVER leaves the app. No redirect. No typing card numbers
/// (unless on simulator for testing).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  String _selectedPlan = 'premium_monthly';
  bool _loading = false;
  String? _error;
  bool _success = false;

  late final PaymentService _paymentService;

  @override
  void initState() {
    super.initState();
    _paymentService = PaymentService(ApiClient());
  }

  Future<void> _subscribe() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Ask backend for a PaymentIntent
      final result = await _paymentService.subscribe(
        plan: _selectedPlan,
        paymentMethod: 'apple_pay',
      );

      final clientSecret = result['client_secret'] as String?;
      if (clientSecret == null) {
        setState(() =>
            _error = result['error'] as String? ?? 'Failed to create payment.');
        return;
      }

      // 2. Show the payment sheet (Apple Pay on real device, card on simulator)
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Outfi',
          customerId: result['customer_id'] as String?,
          customerEphemeralKeySecret: result['ephemeral_key'] as String?,
          style: ThemeMode.light,
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'US',
          ),
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'US',
            testEnv: true,
          ),
        ),
      );

      // 3. Present it — this shows Apple Pay sheet or card form
      await Stripe.instance.presentPaymentSheet();

      // 4. If we get here, payment succeeded (presentPaymentSheet throws on cancel/fail)
      // Wait a moment for the webhook to fire and activate the subscription
      await Future.delayed(const Duration(seconds: 2));
      final status = await _paymentService.getStatus();

      // Clear the freemium gate cache so all gates open immediately.
      FreemiumGateService().clearPremiumCache();

      if (mounted) {
        setState(() => _success = true);
        debugPrint('Subscription activated: ${status['plan']}');
      }
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        // User canceled the payment sheet — not an error
        debugPrint('Payment canceled by user');
      } else {
        setState(() => _error = e.error.localizedMessage ?? 'Payment failed.');
      }
    } catch (e) {
      setState(() => _error = 'Payment failed. Please try again.');
      debugPrint('Subscribe error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _paymentService.restore();
      if (result['restored'] == true) {
        setState(() => _success = true);
      } else {
        setState(() =>
            _error = result['message'] as String? ?? 'No subscription found.');
      }
    } catch (e) {
      setState(() => _error = 'Could not restore. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) return _buildSuccessScreen();

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),

              // Premium badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentDark],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'PREMIUM',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Unlock Outfi Premium',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),

              // Features
              ..._features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppTheme.accent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(f,
                              style: const TextStyle(
                                  fontSize: 15, color: AppTheme.textPrimary)),
                        ),
                      ],
                    ),
                  )),

              const SizedBox(height: 32),

              // Plan cards
              _buildPlanCard(
                id: 'premium_monthly',
                title: 'Monthly',
                price: '\$9.99',
                subtitle: 'per month',
                badge: 'BEST VALUE',
              ),
              const SizedBox(height: 12),
              _buildPlanCard(
                id: 'premium_biweekly',
                title: '2 Weeks',
                price: '\$4.99',
                subtitle: 'every 2 weeks',
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style:
                        const TextStyle(color: AppTheme.error, fontSize: 14)),
              ],

              const Spacer(flex: 2),

              // Subscribe button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _subscribe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.apple, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Subscribe with Apple Pay',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _loading ? null : _restore,
                child: const Text(
                  'Restore Purchase',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ),

              const SizedBox(height: 8),
              const Text(
                'Cancel anytime from your profile. Subscription auto-renews.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String id,
    required String title,
    required String price,
    required String subtitle,
    String? badge,
  }) {
    final selected = _selectedPlan == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.08)
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppTheme.accent : AppTheme.textMuted,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accent,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(badge,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Text(price,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Premium!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You now have access to unlimited image searches, '
                'more price alerts, and an ad-free experience.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15, color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Start Exploring',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _features = [
    '50 image searches per day',
    '100 price alerts',
    'Up to 1,000 saved deals',
    '50 style boards',
    'Ad-free experience',
  ];
}
