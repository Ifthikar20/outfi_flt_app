import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../bloc/auth/auth_bloc.dart';
import '../bloc/auth/auth_state.dart';
import '../bloc/deal_alerts/deal_alerts_bloc.dart';
import '../models/deal.dart';
import '../models/deal_alert.dart';
import '../theme/app_theme.dart';
import '../widgets/loading_shimmer.dart';

class DealAlertsScreen extends StatefulWidget {
  final String? initialAlertId;
  const DealAlertsScreen({super.key, this.initialAlertId});

  @override
  State<DealAlertsScreen> createState() => _DealAlertsScreenState();
}

class _DealAlertsScreenState extends State<DealAlertsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialAlertId != null && widget.initialAlertId!.isNotEmpty) {
      // Deep-link from a notification: jump straight to that alert's
      // detail view. Bloc still guards auth + ownership on the server.
      context
          .read<DealAlertsBloc>()
          .add(DealAlertDetailRequested(widget.initialAlertId!));
    } else {
      context.read<DealAlertsBloc>().add(DealAlertsFetchRequested());
    }
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgMain,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateAlertSheet(
        onSubmit: (desc, price, imagePath) {
          context.read<DealAlertsBloc>().add(
            DealAlertCreateRequested(description: desc, maxPrice: price, imagePath: imagePath),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final isLoggedIn = authState is AuthAuthenticated;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Alerts',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (isLoggedIn)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: _showCreateSheet,
            ),
        ],
      ),
      body: !isLoggedIn
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: const BoxDecoration(
                        color: AppTheme.bgInput,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_none_rounded, size: 40, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Never miss a deal',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sign in to set alerts and get notified\nwhen matching deals are found.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => context.push('/login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.textPrimary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Sign In'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : BlocBuilder<DealAlertsBloc, DealAlertsState>(
              builder: (context, state) {
                if (state is DealAlertsLoading) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 4,
                    itemBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LoadingShimmer(),
                    ),
                  );
                }

                if (state is DealAlertDetailLoaded) {
                  return _AlertDetailView(alert: state.alert);
                }

                if (state is DealAlertsLoaded) {
                  if (state.alerts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 80, height: 80,
                              decoration: const BoxDecoration(
                                color: AppTheme.bgInput,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_none_rounded, size: 40, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Set your first alert',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Describe what you want or share a photo.\nWe\'ll find matching deals for you.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _showCreateSheet,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.textPrimary,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Create Alert'),
                              ),
                            ),
                            const SizedBox(height: 32),
                            // How it works
                            _HowItWorks(),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.alerts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _AlertCard(
                      alert: state.alerts[i],
                      onTap: () {
                        context.read<DealAlertsBloc>().add(
                          DealAlertDetailRequested(state.alerts[i].id),
                        );
                      },
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
    );
  }
}

// ─── Alert Card ──────────────────────────────────
class _AlertCard extends StatelessWidget {
  final DealAlert alert;
  final VoidCallback onTap;

  const _AlertCard({required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Reference image or status icon
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: alert.isPaused
                    ? AppTheme.bgInput
                    : alert.matchesCount > 0
                        ? AppTheme.success.withValues(alpha: 0.12)
                        : AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: alert.hasImage
                  ? CachedNetworkImage(
                      imageUrl: alert.referenceImage,
                      fit: BoxFit.cover,
                      memCacheWidth: 96,
                      errorWidget: (_, __, ___) => Icon(
                        Icons.image_outlined, color: AppTheme.textMuted, size: 22,
                      ),
                    )
                  : Icon(
                      alert.isPaused
                          ? Icons.pause_circle_outline
                          : alert.matchesCount > 0
                              ? Icons.check_circle_outline
                              : Icons.notifications_active_outlined,
                      color: alert.isPaused
                          ? AppTheme.textMuted
                          : alert.matchesCount > 0
                              ? AppTheme.success
                              : AppTheme.accent,
                      size: 22,
                    ),
            ),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: alert.isPaused
                              ? AppTheme.textMuted.withValues(alpha: 0.12)
                              : alert.matchesCount > 0
                                  ? AppTheme.success.withValues(alpha: 0.12)
                                  : AppTheme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          alert.isPaused
                              ? 'Paused'
                              : alert.matchesCount > 0
                                  ? 'Triggered'
                                  : 'Active',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: alert.isPaused
                                ? AppTheme.textMuted
                                : alert.matchesCount > 0
                                    ? AppTheme.success
                                    : AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (alert.maxPrice != null) ...[
                        Text(
                          'Under \$${alert.maxPrice!.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (alert.matchesCount > 0)
                        Text(
                          '${alert.matchesCount} match${alert.matchesCount == 1 ? '' : 'es'} found — tap to view',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.success),
                        ),
                      if (alert.matchesCount == 0 && !alert.isPaused)
                        Text('Checking marketplaces...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      if (alert.isPaused)
                        Text('Not running', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            // Chevron indicator
            if (alert.matchesCount > 0)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
              ),
            // Actions
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textMuted),
              onSelected: (action) {
                if (action == 'pause') {
                  context.read<DealAlertsBloc>().add(
                    DealAlertTogglePauseRequested(alertId: alert.id, pause: !alert.isPaused),
                  );
                } else if (action == 'delete') {
                  context.read<DealAlertsBloc>().add(DealAlertDeleteRequested(alert.id));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pause',
                  child: Text(alert.isPaused ? 'Resume' : 'Pause'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Detail View (shows matches) ─────────────────
class _AlertDetailView extends StatefulWidget {
  final DealAlert alert;

  const _AlertDetailView({required this.alert});

  @override
  State<_AlertDetailView> createState() => _AlertDetailViewState();
}

class _AlertDetailViewState extends State<_AlertDetailView> {
  Timer? _ticker;
  Timer? _checkingPoll;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Refresh "time ago" labels once a minute instead of every frame.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    // If the alert is fresh and empty, the one-shot matcher is running
    // server-side. Poll every 8s for up to 2 minutes to show results as
    // soon as they're written.
    if (_isChecking) {
      _checkingPoll = Timer.periodic(const Duration(seconds: 8), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (!_isChecking) {
          t.cancel();
          return;
        }
        context
            .read<DealAlertsBloc>()
            .add(DealAlertDetailRequested(widget.alert.id));
      });
      // Cancel after 2 minutes regardless — either results came in or
      // something went wrong and we stop hammering.
      Timer(const Duration(minutes: 2), () => _checkingPoll?.cancel());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _checkingPoll?.cancel();
    super.dispose();
  }

  DealAlert get alert => widget.alert;

  /// True when the alert has no matches yet AND the server hasn't
  /// completed its first check. Used to show the "Checking..." state.
  bool get _isChecking {
    if (alert.recentMatches.isNotEmpty) return false;
    final checkedAt = alert.lastCheckedAt;
    if (checkedAt == null) return true;
    // If backend ran the check less than 90s ago and found nothing,
    // give it another beat in case the one-shot is still completing.
    return DateTime.now().difference(checkedAt).inSeconds < 90;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 16),
                    onPressed: () {
                      context.read<DealAlertsBloc>().add(DealAlertsFetchRequested());
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.description,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (alert.maxPrice != null)
                    Text('Max: \$${alert.maxPrice!.toStringAsFixed(0)}  ',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  Text(
                    '${alert.matchesCount} deal${alert.matchesCount == 1 ? '' : 's'} found',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  if (alert.lastCheckedAt != null) ...[
                    const Text('  ·  ', style: TextStyle(color: AppTheme.textMuted)),
                    Text(
                      _timeAgo(alert.lastCheckedAt!, _now),
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Matches grid
        Expanded(
          child: alert.recentMatches.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: _isChecking
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                    color: AppTheme.accent,
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : const Icon(Icons.search_rounded,
                                  size: 32, color: AppTheme.accent),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isChecking
                              ? 'Checking marketplaces…'
                              : 'No matches yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isChecking
                              ? "We're fetching the first batch of deals\n"
                                  'for this alert. This usually takes under a minute.'
                              : 'We check marketplaces every 4 hours.\n'
                                  'New deals will appear here automatically.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: alert.recentMatches.length,
                  itemBuilder: (_, i) => _MatchCard(match: alert.recentMatches[i]),
                ),
        ),
      ],
    );
  }

  static String _timeAgo(DateTime dt, DateTime now) {
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Match Card ──────────────────────────────────
class _MatchCard extends StatelessWidget {
  final DealAlertMatch match;

  const _MatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Navigate to deal detail
        context.push('/deal', extra: Deal(
          id: match.dealId,
          title: match.title,
          price: match.price ?? 0,
          image: match.imageUrl,
          source: match.source,
          url: match.url,
        ));
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 3,
              child: match.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: match.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      memCacheWidth: 400,
                      errorWidget: (_, __, ___) => Container(
                        color: AppTheme.bgInput,
                        child: const Center(child: Icon(Icons.image_outlined, color: AppTheme.textMuted)),
                      ),
                    )
                  : Container(
                      color: AppTheme.bgInput,
                      child: const Center(child: Icon(Icons.shopping_bag_outlined, color: AppTheme.textMuted)),
                    ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (match.source.isNotEmpty)
                      Text(
                        match.source.toUpperCase(),
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.8),
                      ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Text(
                        match.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textPrimary, height: 1.3),
                      ),
                    ),
                    if (match.price != null)
                      Text(
                        '\$${match.price!.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── How It Works ────────────────────────────────
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HOW IT WORKS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _step(Icons.edit_outlined, 'Describe or snap',
            'Tell us what you want, or share a photo of a style you like.'),
        const SizedBox(height: 14),
        _step(Icons.shopping_bag_outlined, 'We search for you',
            'Every 4 hours we scan Amazon, eBay, and other marketplaces.'),
        const SizedBox(height: 14),
        _step(Icons.notifications_none_rounded, 'Get matched deals',
            'Matching deals show up in your alert. Tap to view and buy.'),
      ],
    );
  }

  static Widget _step(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppTheme.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Create Alert Sheet (with image picker) ──────
class _CreateAlertSheet extends StatefulWidget {
  final void Function(String description, double? maxPrice, String? imagePath) onSubmit;

  const _CreateAlertSheet({required this.onSubmit});

  @override
  State<_CreateAlertSheet> createState() => _CreateAlertSheetState();
}

class _CreateAlertSheetState extends State<_CreateAlertSheet> {
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String? _imagePath;
  bool _submitting = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 75,
    );
    if (photo != null) {
      setState(() => _imagePath = photo.path);
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'New Alert',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Describe what you want, or add a reference photo and we\'ll find similar deals.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          // Image picker
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: _imagePath != null ? 160 : 80,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: _imagePath != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_imagePath!), fit: BoxFit.cover),
                        Positioned(
                          top: 8, right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _imagePath = null),
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, color: AppTheme.textMuted, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'Add reference photo',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),

          // Description
          TextField(
            controller: _descCtrl,
            autofocus: _imagePath == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _imagePath != null ? 'Optional — describe what you like about it' : 'e.g. black leather jacket, Nike sneakers...',
              labelText: 'What are you looking for?',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: 'Optional',
              labelText: 'Max price (\$)',
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _submitting ? null : () {
                final desc = _descCtrl.text.trim();
                if (desc.isEmpty && _imagePath == null) return;
                setState(() => _submitting = true);
                widget.onSubmit(
                  desc.isNotEmpty ? desc : 'Find similar items',
                  double.tryParse(_priceCtrl.text.trim()),
                  _imagePath,
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
              ),
              child: Text(
                _imagePath != null ? 'Find Deals Like This' : 'Create Alert',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // Limit info
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Max 5 alerts · Active for 30 days',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
