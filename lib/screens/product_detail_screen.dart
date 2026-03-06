import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../bloc/favorites/favorites_bloc.dart';
import '../models/deal.dart';
import '../services/api_client.dart';
import '../services/deal_service.dart';
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

  @override
  void initState() {
    super.initState();
    _deal = widget.deal;
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
                        child: _deal.image != null
                            ? CachedNetworkImage(
                                imageUrl: _deal.image!,
                                fit: BoxFit.cover,
                                memCacheWidth: 800,
                                placeholder: (_, __) => const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                errorWidget: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      color: AppTheme.textMuted, size: 48),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.shopping_bag_outlined,
                                    color: AppTheme.textMuted, size: 56),
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
                      if (_deal.source.isNotEmpty)
                        GestureDetector(
                          onTap: () => context.push(
                            '/brand/${Uri.encodeComponent(_deal.source)}',
                          ),
                          child: Text(
                            _deal.source.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),

                      // Title
                      Text(
                        _deal.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
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
                              fontSize: 28,
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

                      // Rating
                      if (_deal.rating != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ...List.generate(5, (i) {
                              final fill = _deal.rating! - i;
                              return Icon(
                                fill >= 1
                                    ? Icons.star
                                    : fill > 0
                                        ? Icons.star_half
                                        : Icons.star_border,
                                color: AppTheme.accent,
                                size: 18,
                              );
                            }),
                            const SizedBox(width: 6),
                            Text(
                              _deal.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_deal.reviewsCount != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${_deal.reviewsCount} reviews)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── Price Comparison ─────────
                      _PriceComparisonCard(
                        deal: _deal,
                        comparisonData: _comparisonData,
                        loading: _loadingComparison,
                      ),

                      const SizedBox(height: 24),

                      // ── Action Buttons ──────────
                      // Buy Now — gold gradient
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFD4B87A), Color(0xFFC9A96E), Color(0xFFB8944F)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _launchAffiliateUrl,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shopping_bag_outlined, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Buy Now',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Secondary buttons row
                      Row(
                        children: [
                          Expanded(
                            child: _SecondaryButton(
                              icon: _deal.isSaved
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              label: _deal.isSaved ? 'Saved' : 'Save',
                              highlight: _deal.isSaved,
                              onTap: () {
                                if (_deal.isSaved) {
                                  context.read<FavoritesBloc>().add(
                                      FavoritesRemoveRequested(_deal.id));
                                } else {
                                  context.read<FavoritesBloc>().add(
                                      FavoritesSaveRequested(_deal));
                                }
                                setState(
                                    () => _deal = _deal.copyWith(
                                        isSaved: !_deal.isSaved));
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SecondaryButton(
                              icon: Icons.dashboard_customize_outlined,
                              label: 'Add to Board',
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Added to Board'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // ── Info chips ─────────────
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_deal.condition.isNotEmpty)
                            _InfoChip(
                                icon: Icons.verified_outlined,
                                label: _deal.condition),
                          if (_deal.shipping.isNotEmpty)
                            _InfoChip(
                                icon: Icons.local_shipping_outlined,
                                label: _deal.shipping),
                          if (_deal.inStock)
                            const _InfoChip(
                                icon: Icons.check_circle_outline,
                                label: 'In Stock')
                          else
                            const _InfoChip(
                                icon: Icons.cancel_outlined,
                                label: 'Out of Stock'),
                        ],
                      ),

                      // ── Product Details ─────────
                      if (_deal.description.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'About this product',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _deal.description,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ],

                      // Features
                      if (_deal.features.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Features',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...(_deal.features.take(6).map((f) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text('•  ',
                                      style: TextStyle(
                                          color: AppTheme.accent,
                                          fontSize: 14)),
                                  Expanded(
                                    child: Text(
                                      f,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ))),
                      ],

                      // Seller info
                      if (_deal.seller.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
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
                                  color: AppTheme.bgMain,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Center(
                                  child: Icon(Icons.store_outlined,
                                      color: AppTheme.textSecondary, size: 22),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sold by ${_deal.seller}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    if (_deal.source.isNotEmpty)
                                      Text(
                                        'via ${_deal.source}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppTheme.textMuted),
                            ],
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
                        child: _loadingComparison
                            ? ListView.builder(
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
                            : ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: _similarProducts.length,
                                itemBuilder: (_, i) {
                                  final similar = _similarProducts[i];
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ProductDetailScreen(deal: similar),
                                        ),
                                      );
                                    },
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
                                            borderRadius: const BorderRadius.vertical(
                                                top: Radius.circular(12)),
                                            child: CachedNetworkImage(
                                              imageUrl: similar.image!,
                                              height: 120,
                                              width: 130,
                                              fit: BoxFit.cover,
                                              memCacheWidth: 260,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  similar.title,
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
                                                  similar.formattedPrice,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.accent,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
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
                  icon: Icons.share_outlined,
                  onTap: () {
                    if (_deal.url != null) {
                      // Could use Share.share here
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        height: 80,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.accent),
          ),
        ),
      );
    }

    final price = deal.price!;

    // Use backend data if available, fallback to estimates
    double low, high;
    double position;
    String rating;
    int sellerCount;

    if (comparisonData != null) {
      final priceRange = comparisonData!['price_range'] as Map<String, dynamic>? ?? {};
      low = (priceRange['low'] as num?)?.toDouble() ?? price * 0.7;
      high = (priceRange['high'] as num?)?.toDouble() ?? price * 1.3;
      position = (comparisonData!['position'] as num?)?.toDouble() ?? 0.5;
      rating = comparisonData!['rating'] as String? ?? 'fair';
      sellerCount = comparisonData!['seller_count'] as int? ?? 0;
    } else {
      low = (price * 0.7).roundToDouble();
      high = (price * 1.3).roundToDouble();
      position = 0.5;
      rating = 'fair';
      sellerCount = 0;
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                sellerCount >= 2
                    ? 'Price comparison ($sellerCount sellers)'
                    : 'Price comparison',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

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
          const SizedBox(height: 8),

          // Min / Max labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$${low.toInt()}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              Text(
                '\$${high.toInt()}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Secondary Button ───────────────────────

class _SecondaryButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: highlight ? AppTheme.accent.withValues(alpha: 0.1) : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlight ? AppTheme.accent.withValues(alpha: 0.3) : AppTheme.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: highlight ? AppTheme.accent : AppTheme.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: highlight ? AppTheme.accent : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Circle Button ──────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
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
        child: Icon(icon, color: AppTheme.textPrimary, size: 22),
      ),
    );
  }
}

// ─── Info Chip ──────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
