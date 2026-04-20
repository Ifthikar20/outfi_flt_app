import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../bloc/auth/auth_bloc.dart';
import '../bloc/auth/auth_event.dart';
import '../bloc/auth/auth_state.dart';
import '../services/api_client.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import '../widgets/paywall_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) context.go('/login');
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgMain,
        body: SafeArea(
          child: BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final user = state is AuthAuthenticated ? state.user : null;
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Profile',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: _IdentityCard(
                        name: user?.email ?? 'User',
                        email: user?.email ?? '',
                      ),
                    ),
                  ),
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                    sliver: SliverToBoxAdapter(child: _PremiumCard()),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: _Section(
                        title: 'Your account',
                        rows: [
                          _Row(
                            icon: Icons.bookmark_border,
                            label: 'Saved deals',
                            onTap: () => context.go('/favorites'),
                          ),
                          _Row(
                            icon: Icons.dashboard_outlined,
                            label: 'My boards',
                            onTap: () => context.go('/boards'),
                          ),
                          _Row(
                            icon: Icons.notifications_active_outlined,
                            label: 'Alerts',
                            onTap: () => context.push('/deal-alerts'),
                          ),
                          _Row(
                            icon: Icons.calendar_month,
                            label: 'Fashion timeline',
                            onTap: () => context.push('/timeline'),
                          ),
                          _Row(
                            icon: Icons.tune,
                            label: 'Style & location preferences',
                            onTap: () => context.push('/preferences'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: _Section(
                        title: 'Legal',
                        rows: [
                          _Row(
                            icon: Icons.description_outlined,
                            label: 'Terms & Conditions',
                            onTap: () => _showLegalPage(context,
                                title: 'Terms & Conditions',
                                content: _termsContent),
                          ),
                          _Row(
                            icon: Icons.privacy_tip_outlined,
                            label: 'Privacy Policy',
                            onTap: () => _showLegalPage(context,
                                title: 'Privacy Policy',
                                content: _privacyContent),
                          ),
                          _Row(
                            icon: Icons.verified_user_outlined,
                            label: 'Usage Policy',
                            onTap: () => _showLegalPage(context,
                                title: 'Usage Policy',
                                content: _usageContent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: _Section(
                        title: 'Support',
                        rows: [
                          _Row(
                            icon: Icons.help_outline,
                            label: 'Help & support',
                            onTap: () async {
                              final uri = Uri.parse('mailto:support@outfi.ai');
                              if (await url_launcher.canLaunchUrl(uri)) {
                                await url_launcher.launchUrl(uri);
                              }
                            },
                          ),
                          _Row(
                            icon: Icons.info_outline,
                            label: 'About Outfi',
                            onTap: () => _showLegalPage(context,
                                title: 'About Outfi',
                                content: _aboutContent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    sliver: SliverToBoxAdapter(
                      child: GestureDetector(
                        onTap: () => context
                            .read<AuthBloc>()
                            .add(AuthLogoutRequested()),
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Log out',
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                              decoration: TextDecoration.underline,
                              decorationThickness: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 32),
                    sliver: SliverToBoxAdapter(child: _VersionLabel()),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showLegalPage(BuildContext context,
      {required String title, required String content}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.7,
            ),
          ),
        ),
      ),
    ));
  }
}

// ─── Identity Card ─────────────────────────────────────────
class _IdentityCard extends StatelessWidget {
  final String name;
  final String email;

  const _IdentityCard({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgMain,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppTheme.bgCard,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(email),
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName(name, email),
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _displayName(String name, String email) {
    if (name.isNotEmpty && name != email) return name;
    if (email.contains('@')) return email.split('@').first;
    return name.isEmpty ? 'User' : name;
  }

  static String _initials(String email) {
    if (email.isEmpty) return '·';
    final handle = email.contains('@') ? email.split('@').first : email;
    final letter = handle.isNotEmpty ? handle[0] : '·';
    return letter.toUpperCase();
  }
}

// ─── Section ───────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i < rows.length - 1) {
        children.add(const Divider(
          height: 1,
          thickness: 0.5,
          color: AppTheme.divider,
          indent: 44,
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.bgMain,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ─── Row ───────────────────────────────────────────────────
class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.textPrimary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
              const Icon(Icons.chevron_right,
                  size: 20, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Premium Card ──────────────────────────────────────────
/// Premium card that reflects the server's view of subscription state.
///
/// The *client-side copy is display-only* — all gating decisions still go
/// through the server via FreemiumGateService / PaymentService.getStatus().
/// This widget never trusts a locally-stored "is premium" flag as truth; it
/// always fetches fresh status on mount.
class _PremiumCard extends StatefulWidget {
  const _PremiumCard();

  @override
  State<_PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<_PremiumCard> {
  bool _loading = true;
  bool _isPremium = false;
  String? _planLabel;
  String? _renewalLabel;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await PaymentService(ApiClient()).getStatus();
      if (!mounted) return;
      final isPremium = status['is_premium'] == true;
      setState(() {
        _loading = false;
        _isPremium = isPremium;
        _planLabel = _labelForPlan(status['plan']);
        _renewalLabel = _labelForRenewal(status);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String? _labelForPlan(Object? plan) {
    if (plan is! String) return null;
    switch (plan) {
      case 'premium_monthly':
      case 'monthly':
        return 'Monthly';
      case 'premium_weekly':
      case 'premium_biweekly':
      case 'weekly':
        return 'Weekly';
    }
    return null;
  }

  String? _labelForRenewal(Map<String, dynamic> status) {
    final expires = status['current_period_end'] ?? status['expires_at'];
    if (expires is! String) return null;
    final dt = DateTime.tryParse(expires);
    if (dt == null) return null;
    final cancelAtPeriodEnd = status['cancel_at_period_end'] == true ||
        status['status'] == 'canceled';
    final month = _monthShort(dt.month);
    final label = '$month ${dt.day}, ${dt.year}';
    return cancelAtPeriodEnd ? 'Ends $label' : 'Renews $label';
  }

  static String _monthShort(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][(m - 1).clamp(0, 11)];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () async {
          final changed = _isPremium
              ? await context.push<bool>('/subscription')
              : await showPaywallSheet(context);
          if (changed == true && mounted) _loadStatus();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgMain,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium,
                    color: AppTheme.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: _buildText()),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildText() {
    if (_loading) {
      return const Text(
        'Outfi Premium',
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      );
    }
    if (!_isPremium) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Outfi Premium',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Unlimited searches, more alerts, ad-free',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      );
    }
    final meta = [
      if (_planLabel != null) _planLabel!,
      if (_renewalLabel != null) _renewalLabel!,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Outfi Premium',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  color: AppTheme.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            meta,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Legal Content ──────────────────────

const _termsContent = '''
Terms & Conditions — Outfi

Last updated: March 2026

1. Acceptance of Terms
By downloading, installing, or using Outfi, you agree to these Terms & Conditions. If you do not agree, please do not use the app.

2. Description of Service
Outfi provides curated modest fashion discovery. We aggregate product listings from third-party retailers and present them to you. Outfi does not sell products directly — purchases are made through the original retailer.

3. User Accounts
You may create an account to save favorites and create fashion boards. You are responsible for maintaining the confidentiality of your account credentials.

4. Intellectual Property
All content, logos, and branding within Outfi are the property of Outfi or its licensors. Fashion boards created by you remain your intellectual property.

5. Third-Party Links
Product links redirect to third-party retailers. Outfi is not responsible for the products, services, or policies of these retailers.

6. Limitation of Liability
Outfi provides information "as is" without warranty. We are not liable for any damages arising from your use of the app or purchases made through linked retailers.

7. Modifications
We reserve the right to modify these terms at any time. Continued use of the app constitutes acceptance of modified terms.

8. Governing Law
These terms shall be governed by the laws of the jurisdiction in which Outfi operates.

Contact: support@outfi.ai
''';

const _privacyContent = '''
Privacy Policy — Outfi

Last updated: March 2026

1. Information We Collect
- Account information: email address, name (optional)
- Usage data: search queries, saved products, fashion boards
- Device information: device type, OS version, app version

2. How We Use Your Information
- To provide and improve our fashion discovery service
- To personalize your experience and recommendations
- To communicate service updates and new features
- To analyze app usage and improve performance

3. Data Sharing
We do not sell your personal information. We may share anonymized, aggregated data for analytics purposes. Third-party retailers receive referral information when you click product links.

4. Data Security
We use industry-standard security measures to protect your data, including encrypted storage and secure HTTPS connections.

5. Your Rights
You may request deletion of your account and associated data at any time by contacting support@outfi.ai.

6. Cookies & Tracking
The app uses minimal tracking for analytics purposes. No third-party advertising trackers are used.

7. Children's Privacy
Outfi is not intended for children under 13. We do not knowingly collect information from children.

Contact: support@outfi.ai
''';

const _usageContent = '''
Usage Policy — Outfi

Last updated: March 2026

1. Acceptable Use
Outfi is designed for personal, non-commercial fashion discovery. Users agree to use the app respectfully and lawfully.

2. Prohibited Activities
- Automated scraping or data extraction
- Impersonation of other users
- Uploading offensive, inappropriate, or copyrighted content to fashion boards
- Attempting to gain unauthorized access to other accounts

3. Fashion Boards
- Boards you create are private by default
- Shared boards may be visible to others via the share link
- Outfi reserves the right to remove boards that violate these guidelines

4. Content Standards
When creating or sharing fashion boards, ensure content is:
- Appropriate and respectful
- Not infringing on third-party copyrights
- Not promoting illegal activities

5. Account Suspension
We reserve the right to suspend or terminate accounts that violate these policies.

Contact: support@outfi.ai
''';

const _aboutContent = '''
About Outfi

Style. Curated.

Outfi is a modern modest fashion discovery platform. We curate beautiful, affordable fashion from trusted retailers and bring them together in one elegant experience.

Our Mission
To make modest fashion accessible, beautiful, and easy to discover. We believe everyone deserves to find clothing that aligns with their values without compromising on style.

Features
• Visual search — snap a photo to find similar items
• Fashion boards — create mood boards with curated products
• Price comparison — see how prices compare across retailers
• Personalized deals — discover items picked just for you

Built with love for the modest fashion community.

Version 1.0.0
© 2026 Outfi. All rights reserved.
support@outfi.ai
''';

/// Displays "Outfi v[name] ([build])" pulled from the native app bundle.
class _VersionLabel extends StatefulWidget {
  const _VersionLabel();

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _label = 'Outfi v${info.version} (${info.buildNumber})');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label ?? '',
      style: const TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 12,
        color: AppTheme.textMuted,
      ),
    );
  }
}
