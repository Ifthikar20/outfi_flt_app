import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../bloc/auth/auth_bloc.dart';
import '../bloc/auth/auth_event.dart';
import '../bloc/auth/auth_state.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) context.go('/login');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            final user = state is AuthAuthenticated ? state.user : null;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Google Logo
                  SvgPicture.asset(
                    AppTheme.googleLogoPath,
                    height: 36,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),

                  // Avatar
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppTheme.bgCard,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_outline,
                        size: 32, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),

                  Text(
                    user?.email ?? 'User',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),

                  // ─── Premium ─────────────────────────
                  GestureDetector(
                    onTap: () => context.push('/premium'),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A1A1A), Color(0xFF2A2A2A)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.workspace_premium,
                                color: AppTheme.accent, size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Outfi Premium',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    )),
                                SizedBox(height: 2),
                                Text('Unlimited searches, more alerts, ad-free',
                                    style: TextStyle(
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 13,
                                    )),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppTheme.accent),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─── Quick links ──────────────────────
                  _SettingsRow(
                    icon: Icons.bookmark_border,
                    label: 'Saved Deals',
                    onTap: () => context.go('/favorites'),
                  ),
                  _SettingsRow(
                    icon: Icons.dashboard_outlined,
                    label: 'My Boards',
                    onTap: () => context.go('/boards'),
                  ),
                  _SettingsRow(
                    icon: Icons.notifications_active_outlined,
                    label: 'Deal Alerts',
                    onTap: () => context.push('/deal-alerts'),
                  ),
                  _SettingsRow(
                    icon: Icons.calendar_month,
                    label: 'Fashion Timeline',
                    onTap: () => context.push('/timeline'),
                  ),
                  _SettingsRow(
                    icon: Icons.tune,
                    label: 'Style & Location Preferences',
                    onTap: () => context.push('/preferences'),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ─── Legal / Info ────────────────────
                  _SettingsRow(
                    icon: Icons.description_outlined,
                    label: 'Terms & Conditions',
                    onTap: () => _showLegalPage(context,
                        title: 'Terms & Conditions',
                        content: _termsContent),
                  ),
                  _SettingsRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () => _showLegalPage(context,
                        title: 'Privacy Policy',
                        content: _privacyContent),
                  ),
                  _SettingsRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Usage Policy',
                    onTap: () => _showLegalPage(context,
                        title: 'Usage Policy',
                        content: _usageContent),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  _SettingsRow(
                    icon: Icons.help_outline,
                    label: 'Help & Support',
                    onTap: () async {
                      final uri = Uri.parse('mailto:support@outfi.ai');
                      if (await url_launcher.canLaunchUrl(uri)) {
                        await url_launcher.launchUrl(uri);
                      }
                    },
                  ),
                  _SettingsRow(
                    icon: Icons.info_outline,
                    label: 'About Outfi',
                    onTap: () => _showLegalPage(context,
                        title: 'About Outfi',
                        content: _aboutContent),
                  ),
                  const SizedBox(height: 32),

                  // Logout
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.read<AuthBloc>().add(AuthLogoutRequested()),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Sign Out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: BorderSide(color: AppTheme.error.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    'v1.0.0',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
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

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
