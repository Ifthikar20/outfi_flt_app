import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../services/api_client.dart';
import '../services/freemium_gate_service.dart';
import '../services/payment_service.dart';
import '../services/storekit_service.dart';
import '../theme/app_theme.dart';

/// Surface where a premium user can view plan details, cancel via the
/// platform store, request a refund, or restore a prior purchase.
///
/// All authoritative state comes from `/payments/status/` (server). Nothing
/// here trusts a local "is premium" bit — we always re-fetch on mount, and
/// we never show raw receipts / transaction IDs in the UI.
class ManageSubscriptionScreen extends StatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  State<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  late final PaymentService _payments;
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic> _status = const {};
  String? _error;

  // Native store deep links. These never change per-user and are safe to
  // launch — the store app handles auth.
  static const String _appleManageUrl =
      'https://apps.apple.com/account/subscriptions';
  static const String _appleReportUrl = 'https://reportaproblem.apple.com/';

  @override
  void initState() {
    super.initState();
    _payments = PaymentService(ApiClient());
    _refresh();
  }

  Future<void> _refresh() async {
    // Invalidate cached premium state so the card and gating see the latest
    // server verdict if the user cancels or buys here.
    FreemiumGateService().clearPremiumCache();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _payments.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load subscription details.';
      });
    }
  }

  bool get _isPremium => _status['is_premium'] == true;
  bool get _cancelAtPeriodEnd =>
      _status['cancel_at_period_end'] == true ||
      _status['status'] == 'canceled';

  String get _planLabel {
    final plan = _status['plan'];
    if (plan is! String) return 'Free';
    switch (plan) {
      case 'premium_monthly':
      case 'monthly':
        return 'Monthly';
      case 'premium_weekly':
      case 'premium_biweekly':
      case 'weekly':
        return 'Weekly';
    }
    return plan.replaceAll('_', ' ');
  }

  String? get _renewalLabel {
    final expires = _status['current_period_end'] ?? _status['expires_at'];
    if (expires is! String) return null;
    final dt = DateTime.tryParse(expires);
    if (dt == null) return null;
    final local = dt.toLocal();
    return '${_monthShort(local.month)} ${local.day}, ${local.year}';
  }

  static String _monthShort(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][(m - 1).clamp(0, 11)];

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await url_launcher.launchUrl(
        uri,
        mode: url_launcher.LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the store.')),
      );
    }
  }

  Future<void> _openManageSubscription() async {
    // Apple controls cancellation and billing — we just link out to the
    // App Store subscriptions page.
    await _openUrl(_appleManageUrl);
  }

  Future<void> _requestRefund() async {
    // Apple's refund request portal. It handles auth and transaction
    // lookup; we don't send identifiers along.
    await _openUrl(_appleReportUrl);
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await StoreKitService().restorePurchases();
      // Give the purchase stream a moment to fire then re-pull status.
      await Future.delayed(const Duration(seconds: 2));
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore purchases.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contactSupport() async {
    // Pre-fill a subject only; we never include receipt data or tokens in
    // a user-controlled mailto URL.
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@outfi.ai',
      query: 'subject=${Uri.encodeComponent('Subscription help')}',
    );
    try {
      if (await url_launcher.canLaunchUrl(uri)) {
        await url_launcher.launchUrl(uri);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Subscription')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _refresh,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _statusCard(),
        const SizedBox(height: 24),
        if (_isPremium) ..._premiumActions() else _upgradePrompt(),
        const SizedBox(height: 24),
        _fineprint(),
      ],
    );
  }

  Widget _statusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium,
                  color: AppTheme.accent, size: 22),
              const SizedBox(width: 8),
              Text(
                _isPremium ? 'Outfi Premium' : 'Outfi Free',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              if (_isPremium)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _cancelAtPeriodEnd
                        ? AppTheme.error.withValues(alpha: 0.15)
                        : AppTheme.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _cancelAtPeriodEnd ? 'CANCELING' : 'ACTIVE',
                    style: TextStyle(
                      color: _cancelAtPeriodEnd
                          ? AppTheme.error
                          : AppTheme.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow('Plan', _planLabel),
          if (_renewalLabel != null)
            _detailRow(
              _cancelAtPeriodEnd ? 'Ends on' : 'Renews on',
              _renewalLabel!,
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  List<Widget> _premiumActions() => [
        _actionButton(
          icon: Icons.open_in_new,
          label: 'Manage in App Store',
          subtitle: _cancelAtPeriodEnd
              ? 'Access continues until ${_renewalLabel ?? 'period end'}.'
              : 'Cancel or change your plan.',
          onTap: _openManageSubscription,
        ),
        const SizedBox(height: 12),
        _actionButton(
          icon: Icons.receipt_long,
          label: 'Request a refund',
          subtitle: 'Opens Apple\'s Report a Problem page.',
          onTap: _requestRefund,
        ),
        const SizedBox(height: 12),
        _actionButton(
          icon: Icons.restore,
          label: _busy ? 'Restoring…' : 'Restore purchase',
          subtitle: 'Sync a past purchase made on another device.',
          onTap: _busy ? null : _restore,
        ),
        const SizedBox(height: 12),
        _actionButton(
          icon: Icons.mail_outline,
          label: 'Contact support',
          subtitle: 'support@outfi.ai',
          onTap: _contactSupport,
        ),
      ];

  Widget _upgradePrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _actionButton(
          icon: Icons.upgrade,
          label: 'Upgrade to Premium',
          subtitle: 'Unlock unlimited image searches and more alerts.',
          onTap: () => context.push('/premium'),
        ),
        const SizedBox(height: 12),
        _actionButton(
          icon: Icons.restore,
          label: _busy ? 'Restoring…' : 'Restore purchase',
          subtitle: 'Already subscribed on another device?',
          onTap: _busy ? null : _restore,
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _fineprint() {
    const text = 'Billing is handled by Apple. Cancelling in the App Store stops '
        'the next renewal; access continues until the current period ends.';
    return Text(
      text,
      style: const TextStyle(
          fontSize: 11, color: AppTheme.textMuted, height: 1.5),
    );
  }
}
