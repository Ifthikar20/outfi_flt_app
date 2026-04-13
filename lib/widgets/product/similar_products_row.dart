import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../models/deal.dart';
import '../../theme/app_theme.dart';

/// Horizontal row of similar product cards shown below the main product.
class SimilarProductsRow extends StatelessWidget {
  final List<Deal> similarProducts;
  final bool loading;

  const SimilarProductsRow({
    super.key,
    required this.similarProducts,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && similarProducts.isEmpty) return const SizedBox.shrink();

    return Column(
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
            child: loading
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
                : ListView.builder(
                    key: const ValueKey('loaded'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: similarProducts.length,
                    itemBuilder: (_, i) => _SimilarProductCard(
                      deal: similarProducts[i],
                      onTap: () => context.push(
                        '/product/${similarProducts[i].id}',
                        extra: similarProducts[i],
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

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
