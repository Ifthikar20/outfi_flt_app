import 'package:flutter/material.dart';
import '../../models/deal.dart';
import '../../theme/app_theme.dart';

/// Compact price comparison meter showing where the current price sits
/// relative to other sellers. Only renders when real backend data is available.
class PriceComparisonCard extends StatelessWidget {
  final Deal deal;
  final Map<String, dynamic>? comparisonData;
  final bool loading;

  const PriceComparisonCard({
    super.key,
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
