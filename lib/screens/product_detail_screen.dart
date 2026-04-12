import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../bloc/deal_alerts/deal_alerts_bloc.dart';
import '../bloc/favorites/favorites_bloc.dart';
import '../models/deal.dart';
import '../services/api_client.dart';
import '../services/deal_alert_service.dart';
import '../services/deal_service.dart';
import '../services/freemium_gate_service.dart';
import '../theme/app_theme.dart';

/// Light-themed product detail page.
///
/// Shows hero image, price info, price-comparison bar, buy/save buttons,
/// product description, and a row of similar products at the bottom.
class ProductDetailScreen extends StatefulWidget {
  final Deal deal;

  const ProductDetailScreen({super.key, required this.deal});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Deal _deal;
  final ApiClient _apiClient = ApiClient();
  late final DealService _dealService = DealService(_apiClient);

  // Backend comparison data
  Map<String, dynamic>? _comparisonData;
  List<Deal> _similarProducts = [];
  bool _loadingComparison = true;

  // Prevent hero image from rebuilding on setState
  late final Widget _heroImage;

  @override
  void initState() {
    super.initState();
    _deal = widget.deal;
    // Build hero image once — never rebuild on setState
    _heroImage = _deal.image != null
        ? CachedNetworkImage(
            imageUrl: _deal.image!,
            fit: BoxFit.cover,
            memCacheWidth: 800,
            fadeInDuration: const Duration(milliseconds: 200),
            fadeOutDuration: const Duration(milliseconds: 200),
            placeholder: (_, __) => Container(color: AppTheme.bgCard),
            errorWidget: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: AppTheme.textMuted, size: 48),
            ),
          )
        : const Center(
            child: Icon(Icons.shopping_bag_outlined,
                color: AppTheme.textMuted, size: 56),
          );
    _loadPriceComparison();
  }

  Future<void> _loadPriceComparison() async {
    try {
      if (_deal.price == null) {
        if (mounted) setState(() => _loadingComparison = false);
        return;
      }

      final data = await _dealService.comparePrices(
        title: _deal.title,
        price: _deal.price!,
        source: _deal.source,
      );

      if (data != null && mounted) {
        // Parse compared products into Deal objects
        final compared = (data['compared_products'] as List<dynamic>?) ?? [];
        final deals = compared
            .map((d) => Deal.fromJson(d as Map<String, dynamic>))
            .where((d) => d.id != _deal.id)
            .where((d) => d.image != null && d.image!.isNotEmpty)
            .take(8)
            .toList();

        setState(() {
          _comparisonData = data;
          _similarProducts = deals;
          _loadingComparison = false;
        });
      } else {
        if (mounted) setState(() => _loadingComparison = false);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load price comparison: $e');
      if (mounted) setState(() => _loadingComparison = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Hero Image ──────────────────────
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    Container(
                      color: AppTheme.bgCard,
                      child: AspectRatio(
                        aspectRatio: 0.85,
                        child: _heroImage,
                      ),
                    ),

                    // Subtle fade into background
                    Positioned(
                      bottom: -1,
                      left: 0,
                      right: 0,
                      height: 80,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppTheme.bgMain.withValues(alpha: 0.0),
                              AppTheme.bgMain.withValues(alpha: 0.3),
                              AppTheme.bgMain.withValues(alpha: 0.8),
                              AppTheme.bgMain,
                            ],
                            stops: const [0.0, 0.35, 0.7, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Discount badge
                    if (_deal.hasDiscount)
                      Positioned(
                        top: topPadding + 60,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.success,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_deal.discountPercent}% OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Product Info ────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand (tappable)
                      if (_deal.brand.isNotEmpty)
                        GestureDetector(
                          onTap: () => context.push(
                            '/brand/${Uri.encodeComponent(_deal.brand)}',
                          ),
                          child: Text(
                            _deal.brand.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),

                      // Title (compact)
                      Text(
                        _deal.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Price row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _deal.formattedPrice,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (_deal.hasDiscount) ...[
                            const SizedBox(width: 10),
                            Text(
                              _deal.formattedOriginalPrice,
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textMuted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 14),

                      // ── Price Comparison (compact) ─────────
                      _PriceComparisonCard(
                        deal: _deal,
                        comparisonData: _comparisonData,
                        loading: _loadingComparison,
                      ),

                      const SizedBox(height: 16),

                      // ── Action Buttons (compact row) ──────────
                      Row(
                        children: [
                          // Buy Now (icon button)
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () => _showRoutingPage(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.shopping_bag_outlined, size: 18),
                                    SizedBox(width: 6),
                                    Text('Buy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Save
                          _SecondaryButton(
                            icon: _deal.isSaved ? Icons.bookmark : Icons.bookmark_border,
                            label: '',
                            highlight: _deal.isSaved,
                            onTap: () {
                              if (_deal.isSaved) {
                                context.read<FavoritesBloc>().add(FavoritesRemoveRequested(_deal.id));
                              } else {
                                context.read<FavoritesBloc>().add(FavoritesSaveRequested(_deal));
                              }
                              setState(() => _deal = _deal.copyWith(isSaved: !_deal.isSaved));
                            },
                          ),
                          const SizedBox(width: 8),
                          // Add to Board
                          _SecondaryButton(
                            icon: Icons.dashboard_customize_outlined,
                            label: '',
                            onTap: () {
                              context.push('/boards/editor', extra: {'addDeal': _deal});
                            },
                          ),
                          const SizedBox(width: 8),
                          // Alert (price drop / similar)
                          _SecondaryButton(
                            icon: Icons.notifications_none_rounded,
                            label: '',
                            onTap: () => _showAlertSheet(context),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ── Mini tags ─────────────
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (_deal.condition.isNotEmpty)
                            _MiniTag(label: _deal.condition),
                          if (_deal.shipping.isNotEmpty)
                            _MiniTag(label: _deal.shipping),
                          if (_deal.inStock)
                            const _MiniTag(label: 'In Stock')
                          else
                            const _MiniTag(label: 'Out of Stock'),
                        ],
                      ),

                      // ── Collapsible Product Details ─────────
                      if (_deal.description.isNotEmpty || _deal.features.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _CollapsibleDetails(deal: _deal),
                      ],

                      // ── Brand card ─────────────
                      if (_deal.brand.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: () => context.push(
                            '/brand/${Uri.encodeComponent(_deal.brand)}',
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border, width: 0.5),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _deal.brand[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.accent,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _deal.brand,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                      ),
                                      const Text(
                                        'View all products',
                                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),

              // ── Similar Products ────────────────
              if (_similarProducts.isNotEmpty || _loadingComparison)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Text(
                          'You may also like',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 190,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _loadingComparison
                              ? ListView.builder(
                                  key: const ValueKey('loading'),
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  itemCount: 4,
                                  itemBuilder: (_, __) => Container(
                                    width: 130,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.bgCard,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                )
                              : _similarProducts.isEmpty
                                  ? const SizedBox.shrink(key: ValueKey('empty'))
                                  : ListView.builder(
                                      key: const ValueKey('loaded'),
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      itemCount: _similarProducts.length,
                                      itemBuilder: (_, i) => _SimilarProductCard(
                                        deal: _similarProducts[i],
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => ProductDetailScreen(
                                                  deal: _similarProducts[i]),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
            ],
          ),

          // ── Top bar (floating back + share) ──
          Positioned(
            top: topPadding + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CircleButton(
                  icon: Icons.arrow_back,
                  onTap: () => context.pop(),
                ),
                _CircleButton(
                  icon: Icons.notifications_active_outlined,
                  onTap: () {
                    context.read<DealAlertsBloc>().add(
                      DealAlertCreateRequested(
                        description: _deal.title,
                        maxPrice: _deal.price,
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Deal alert created! We\'ll find similar deals for you.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRoutingPage(BuildContext context) async {
    // Freemium gate: 1 free buy redirect, then paywall.
    final gate = FreemiumGateService();
    if (!await gate.canBuy()) {
      if (mounted) context.push('/premium');
      return;
    }
    await gate.recordBuyClick();

    if (!mounted) return;
    final storeName = _deal.source.isNotEmpty ? _deal.source : 'store';
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _RoutingPage(
          storeName: storeName,
          onComplete: () {
            Navigator.of(context).pop();
            _launchAffiliateUrl();
          },
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  /// Shows a bottom sheet with two alert options. Each option creates an
  /// entry via the existing [DealAlertsBloc] — it appears on the Deal Alerts
  /// screen (Profile → Deal Alerts) where the user can delete it or see
  /// what matches triggered it.
  void _showAlertSheet(BuildContext context) async {
    // Check alert count BEFORE showing the sheet — don't let the user
    // pick an option only to fail after.
    try {
      final service = DealAlertService(ApiClient());
      final existing = await service.getAlerts();
      final activeCount = existing.where((a) => a.isActive).length;

      if (!mounted) return;

      // Free limit: 5 alerts. If at limit, go straight to paywall.
      if (activeCount >= 5) {
        final gate = FreemiumGateService();
        if (await gate.isPremium()) {
          // Premium users get 100 — let them through
        } else {
          context.push('/premium');
          return;
        }
      }
    } catch (_) {
      // If the check fails, proceed anyway — the create will catch it
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgMain,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Set an alert',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Get notified about this product. Manage alerts from Profile → Alerts.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),
              _AlertOptionTile(
                icon: Icons.trending_down_rounded,
                title: 'Price drop alert',
                subtitle: _deal.price != null
                    ? 'Notify me when this drops below \$${_deal.price!.toStringAsFixed(0)}'
                    : 'Notify me on any price drop',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _createAlert(
                    description: 'Price drop: ${_deal.title}',
                    maxPrice: _deal.price,
                  );
                },
              ),
              const SizedBox(height: 10),
              _AlertOptionTile(
                icon: Icons.auto_awesome_outlined,
                title: 'Similar products alert',
                subtitle: 'Notify me when similar items appear',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _createAlert(
                    description: 'Similar to: ${_deal.title}',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createAlert({required String description, double? maxPrice}) async {
    try {
      final service = DealAlertService(ApiClient());
      await service.createAlert(description: description, maxPrice: maxPrice);

      if (mounted) {
        context.read<DealAlertsBloc>().add(DealAlertsFetchRequested());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Alert created'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => context.push('/deal-alerts'),
            ),
          ),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      // Extract the actual server message from the DioException
      final responseData = e.response?.data;
      String serverMsg = '';
      if (responseData is List && responseData.isNotEmpty) {
        serverMsg = responseData.first.toString();
      } else if (responseData is Map) {
        serverMsg = (responseData['detail'] ?? responseData['error'] ?? '').toString();
      } else if (responseData is String) {
        serverMsg = responseData;
      }

      // At the free limit → paywall
      if (serverMsg.contains('Maximum') || serverMsg.contains('alert')) {
        context.push('/premium');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(serverMsg.isNotEmpty ? serverMsg : 'Could not create alert'),
          duration: const Duration(seconds: 4),
          backgroundColor: AppTheme.error,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not create alert. Check your connection.'),
            duration: const Duration(seconds: 4),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _launchAffiliateUrl() async {
    if (_deal.url != null) {
      final uri = Uri.parse(_deal.url!);
      if (await url_launcher.canLaunchUrl(uri)) {
        await url_launcher.launchUrl(uri,
            mode: url_launcher.LaunchMode.externalApplication);
      }
    }
  }
}

// ─── Price Comparison Card ──────────────────

class _PriceComparisonCard extends StatelessWidget {
  final Deal deal;
  final Map<String, dynamic>? comparisonData;
  final bool loading;

  const _PriceComparisonCard({
    required this.deal,
    this.comparisonData,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (deal.price == null) return const SizedBox.shrink();

    // Show loading skeleton
    if (loading) {
      return Container(
        height: 50,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppTheme.accent),
          ),
        ),
      );
    }

    final price = deal.price!;

    // Only show the meter when we have REAL data from the backend or
    // from compared products. Never fake a ±30% estimate.
    double? low, high;
    double position;
    String rating;
    int sellerCount;

    if (comparisonData != null) {
      final priceRange = comparisonData!['price_range'] as Map<String, dynamic>? ?? {};
      low = (priceRange['low'] as num?)?.toDouble();
      high = (priceRange['high'] as num?)?.toDouble();

      // If backend didn't return a range, compute from compared_products
      if (low == null || high == null) {
        final compared = comparisonData!['compared_products'] as List<dynamic>? ?? [];
        final prices = compared
            .map((p) => (p is Map ? (p['price'] as num?)?.toDouble() : null))
            .whereType<double>()
            .toList();
        if (prices.length >= 2) {
          prices.sort();
          low = prices.first;
          high = prices.last;
        }
      }

      // If we still have no real range, hide the meter entirely
      if (low == null || high == null) return const SizedBox.shrink();

      // Compute position from actual data if backend didn't provide it
      final backendPos = (comparisonData!['position'] as num?)?.toDouble();
      if (backendPos != null) {
        position = backendPos;
      } else {
        final range = high - low;
        position = range > 0 ? ((price - low) / range).clamp(0.0, 1.0) : 0.5;
      }

      // Compute rating from actual position if backend didn't provide it
      final backendRating = comparisonData!['rating'] as String?;
      if (backendRating != null) {
        rating = backendRating;
      } else {
        rating = position < 0.33 ? 'great' : (position < 0.66 ? 'fair' : 'high');
      }

      sellerCount = comparisonData!['seller_count'] as int? ?? 0;
    } else {
      // No backend data at all — don't show a fake meter
      return const SizedBox.shrink();
    }

    final String label;
    final Color labelColor;
    if (rating == 'great') {
      label = 'Great price';
      labelColor = AppTheme.success;
    } else if (rating == 'fair') {
      label = 'Fair price';
      labelColor = AppTheme.warning;
    } else {
      label = '\$${price.toInt()} is high';
      labelColor = AppTheme.error;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: labelColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (sellerCount >= 2)
                Text(
                  '$sellerCount sellers',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Gradient bar
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.success,
                      const Color(0xFFFFEB3B),
                      AppTheme.warning,
                      AppTheme.error,
                    ],
                  ),
                ),
              ),

              // Price indicator
              Positioned(
                left: 0,
                right: 0,
                top: -28,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final leftOffset = (constraints.maxWidth * position)
                        .clamp(0.0, constraints.maxWidth - 90);
                    return SizedBox(
                      height: 22,
                      child: Padding(
                        padding: EdgeInsets.only(left: leftOffset),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: labelColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '\$${price.toInt()}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Min / Max labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$${low.toInt()}',
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              ),
              Text(
                '\$${high.toInt()}',
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Apple-style Bounce Secondary Button ───────────────
// ─── Alert option tile (used in the "Set an alert" bottom sheet) ───
class _AlertOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AlertOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 48,
          width: widget.label.isEmpty ? 48 : null,
          decoration: BoxDecoration(
            color: widget.highlight
                ? AppTheme.primary.withValues(alpha: 0.06)
                : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.highlight
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : AppTheme.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: widget.label.isEmpty ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(widget.icon,
                  size: 18,
                  color: widget.highlight
                      ? AppTheme.accent
                      : AppTheme.textPrimary),
              if (widget.label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: widget.highlight
                        ? AppTheme.accent
                        : AppTheme.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Apple-style Bounce Circle Button ──────────────────
class _CircleButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.bgMain.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(widget.icon, color: AppTheme.textPrimary, size: 20),
        ),
      ),
    );
  }
}

// ─── Mini Tag ──────────────────────────────

class _MiniTag extends StatelessWidget {
  final String label;

  const _MiniTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── Similar Product Card ──────────────────────
class _SimilarProductCard extends StatelessWidget {
  final Deal deal;
  final VoidCallback onTap;

  const _SimilarProductCard({required this.deal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: deal.image != null
                  ? CachedNetworkImage(
                      imageUrl: deal.image!,
                      height: 120,
                      width: 130,
                      fit: BoxFit.cover,
                      memCacheWidth: 260,
                      placeholder: (_, __) => Container(
                        height: 120,
                        color: AppTheme.bgCard,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: 120,
                        color: AppTheme.bgCard,
                        child: const Icon(Icons.image_outlined,
                            color: AppTheme.textMuted, size: 24),
                      ),
                    )
                  : Container(
                      height: 120,
                      color: AppTheme.bgCard,
                      child: const Icon(Icons.image_outlined,
                          color: AppTheme.textMuted, size: 24),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deal.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deal.formattedPrice,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Collapsible Product Details ─────────────────
class _CollapsibleDetails extends StatefulWidget {
  final Deal deal;
  const _CollapsibleDetails({required this.deal});

  @override
  State<_CollapsibleDetails> createState() => _CollapsibleDetailsState();
}

class _CollapsibleDetailsState extends State<_CollapsibleDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              const Text(
                'Product Details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down, size: 20, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.deal.description.isNotEmpty)
                  Text(
                    widget.deal.description,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
                  ),
                if (widget.deal.features.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...widget.deal.features.take(5).map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                        Expanded(
                          child: Text(f, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3)),
                        ),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }
}

// ─── Routing Animation Page ──────────────────────
class _RoutingPage extends StatefulWidget {
  final String storeName;
  final VoidCallback onComplete;

  const _RoutingPage({required this.storeName, required this.onComplete});

  @override
  State<_RoutingPage> createState() => _RoutingPageState();
}

class _RoutingPageState extends State<_RoutingPage> with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _dotCount = (_dotCount + 1) % 4);
        _dotCtrl.forward(from: 0);
      }
    });
    _dotCtrl.forward();

    // Navigate after short delay
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * (_dotCount + 1);
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Store icon with pulse
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_outlined, size: 32, color: AppTheme.accent),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Routing to ${widget.storeName}$dots',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Opening in your browser',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
