import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/favorites/favorites_bloc.dart';
import '../models/deal.dart';
import '../theme/app_theme.dart';

class DealCard extends StatefulWidget {
  final Deal deal;
  final VoidCallback? onSave;
  final bool showTrendingTag;

  const DealCard({
    super.key,
    required this.deal,
    this.onSave,
    this.showTrendingTag = false,
  });

  @override
  State<DealCard> createState() => _DealCardState();
}

class _DealCardState extends State<DealCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _saveController;
  late Animation<double> _scaleAnim;
  bool _justSaved = false;

  @override
  void initState() {
    super.initState();
    _saveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.85), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _saveController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _saveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _openDeal(context),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bgMain,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Expanded(
                flex: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.deal.image != null)
                      CachedNetworkImage(
                        imageUrl: widget.deal.image!,
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: (_, __) => Container(
                          color: AppTheme.bgCard,
                          child: const Center(
                            child: Icon(Icons.image_outlined,
                                color: AppTheme.textMuted, size: 32),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppTheme.bgCard,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: AppTheme.textMuted, size: 32),
                          ),
                        ),
                      )
                    else
                      Container(
                        color: AppTheme.bgCard,
                        child: const Center(
                          child: Icon(Icons.shopping_bag_outlined,
                              color: AppTheme.textMuted, size: 32),
                        ),
                      ),

                    // Discount badge (top-left, black pill)
                    if (widget.deal.hasDiscount)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${widget.deal.discountPercent}% OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),

                    // Animated bookmark button (top-right)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _handleSave(context),
                        child: AnimatedBuilder(
                          animation: _scaleAnim,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _scaleAnim.value,
                              child: child,
                            );
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: (widget.deal.isSaved || _justSaved)
                                  ? AppTheme.accent.withValues(alpha: 0.95)
                                  : Colors.white.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                              boxShadow: [
                                if (widget.deal.isSaved || _justSaved)
                                  BoxShadow(
                                    color: AppTheme.accent.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                              ],
                            ),
                            child: Icon(
                              (widget.deal.isSaved || _justSaved)
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              size: 16,
                              color: (widget.deal.isSaved || _justSaved)
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Details
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand name (tappable → brand page)
                      if (widget.deal.source.isNotEmpty)
                        GestureDetector(
                          onTap: () => context.push(
                            '/brand/${Uri.encodeComponent(widget.deal.source)}',
                          ),
                          child: Text(
                            widget.deal.source.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      const SizedBox(height: 3),

                      // Title
                      Expanded(
                        child: Text(
                          widget.deal.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                            height: 1.3,
                          ),
                        ),
                      ),

                      // Trending tag
                      if (widget.showTrendingTag)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            widget.deal.trendingTag,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),

                      // Price row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.deal.formattedPrice,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (widget.deal.hasDiscount) ...[
                            const SizedBox(width: 6),
                            Text(
                              widget.deal.formattedOriginalPrice,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSave(BuildContext context) {
    // Haptic feedback
    HapticFeedback.lightImpact();

    // Play bounce animation
    _saveController.forward(from: 0);

    if (widget.onSave != null) {
      widget.onSave!();
      return;
    }

    // Toggle saved state with animation
    if (widget.deal.isSaved) {
      setState(() => _justSaved = false);
      context.read<FavoritesBloc>().add(FavoritesRemoveRequested(widget.deal.id));
    } else {
      setState(() => _justSaved = true);
      context.read<FavoritesBloc>().add(FavoritesSaveRequested(widget.deal));
    }
  }

  Future<void> _openDeal(BuildContext context) async {
    context.push('/deal', extra: widget.deal);
  }
}
