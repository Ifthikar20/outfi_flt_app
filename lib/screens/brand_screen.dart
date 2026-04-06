import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/deals/deals_bloc.dart';
import '../bloc/deals/deals_event.dart';
import '../theme/app_theme.dart';
import '../widgets/deal_card.dart';
import '../widgets/loading_shimmer.dart';

/// Brand page — shows all products from a specific brand/source.
///
/// Triggers a search for the brand name via `DealsSearchRequested` and
/// displays the results in a grid identical to the search results screen.
class BrandScreen extends StatefulWidget {
  final String brandName;

  const BrandScreen({super.key, required this.brandName});

  @override
  State<BrandScreen> createState() => _BrandScreenState();
}

class _BrandScreenState extends State<BrandScreen> {
  @override
  void initState() {
    super.initState();
    // Search for all products from this brand (filter by source)
    context.read<DealsBloc>().add(DealsSearchRequested(
          query: widget.brandName,
          sources: [widget.brandName],
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.brandName.toUpperCase(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: BlocConsumer<DealsBloc, DealsState>(
        listener: (context, state) {
          if (state is DealsError) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                context.read<DealsBloc>().add(DealsSearchRequested(
                  query: widget.brandName,
                  sources: [widget.brandName],
                ));
              }
            });
          }
        },
        builder: (context, state) {
          if (state is DealsLoading || state is DealsInitial || state is DealsError) {
            return GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.62,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: 6,
              itemBuilder: (_, __) => const LoadingShimmer(),
            );
          }

          if (state is DealsLoaded) {
            final deals = state.result.deals;

            if (deals.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_outlined,
                        size: 56, color: AppTheme.textMuted),
                    const SizedBox(height: 16),
                    Text(
                      'No products found',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try searching for ${widget.brandName} directly',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Results count
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    '${state.result.total} product${state.result.total == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),

                // Product grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: deals.length,
                    itemBuilder: (_, i) => DealCard(deal: deals[i]),
                  ),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}
