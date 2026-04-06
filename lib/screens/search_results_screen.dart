import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/deals/deals_bloc.dart';
import '../bloc/deals/deals_event.dart';
import '../theme/app_theme.dart';
import '../widgets/deal_card.dart';
import '../widgets/loading_shimmer.dart';
import '../widgets/quota_warning_banner.dart';

class SearchResultsScreen extends StatefulWidget {
  final String query;

  const SearchResultsScreen({super.key, required this.query});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  String _sort = 'relevance';
  String? _gender;
  int? _maxDistance;
  late TextEditingController _searchController;
  late ScrollController _scrollController;

  static const _sortOptions = [
    ('relevance', 'All'),
    ('price_low', 'Price ↑'),
    ('price_high', 'Price ↓'),
    ('rating', 'Top Rated'),
    ('newest', 'New In'),
  ];

  static const _genderOptions = [
    (null, 'All'),
    ('men', 'Men'),
    ('women', 'Women'),
  ];

  static const _distanceOptions = [
    (null, 'Any Distance'),
    (10, '10 mi'),
    (25, '25 mi'),
    (50, '50 mi'),
    (100, '100 mi'),
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _search(widget.query);
  }

  void _search(String query) {
    if (query.isEmpty) return;
    context.read<DealsBloc>().add(DealsSearchRequested(
          query: query,
          sort: _sort,
          gender: _gender,
          maxDistance: _maxDistance,
        ));
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Trigger load more when 80% scrolled
    if (currentScroll >= maxScroll * 0.8) {
      final state = context.read<DealsBloc>().state;
      if (state is DealsLoaded && !state.isLoadingMore && state.result.hasMore) {
        context.read<DealsBloc>().add(const DealsLoadMoreRequested());
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Search Bar ─────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.bgInput,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border, width: 0.5),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onSubmitted: _search,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search deals...',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: InputBorder.none,
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border, width: 0.5),
                    ),
                    child: const Icon(Icons.tune, size: 18,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),

            // ─── Sort Chips ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sortOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final (value, label) = _sortOptions[i];
                    final isActive = _sort == value;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _sort = value);
                        _search(_searchController.text);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.textPrimary
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusFull),
                          border: Border.all(
                            color: isActive
                                ? AppTheme.textPrimary
                                : AppTheme.border,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isActive
                                ? AppTheme.bgMain
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ─── Gender Chips ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _genderOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final (value, label) = _genderOptions[i];
                    final isActive = _gender == value;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _gender = value);
                        _search(_searchController.text);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF6366F1)
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusFull),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFF6366F1)
                                : AppTheme.border,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isActive
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ─── Distance Chips (for Marketplace) ───
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _distanceOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final (value, label) = _distanceOptions[i];
                    final isActive = _maxDistance == value;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _maxDistance = value);
                        _search(_searchController.text);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.accent
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusFull),
                          border: Border.all(
                            color: isActive
                                ? AppTheme.accent
                                : AppTheme.border,
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (i == 0) ...[
                              Icon(Icons.location_on,
                                  size: 12,
                                  color: isActive
                                      ? Colors.white
                                      : AppTheme.textMuted),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    isActive ? FontWeight.w600 : FontWeight.w400,
                                color: isActive
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const Divider(height: 1, color: AppTheme.border),

            // ─── Results ────────────────────────────
            Expanded(
              child: BlocConsumer<DealsBloc, DealsState>(
                listener: (context, state) {
                  if (state is DealsError) {
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) _search(_searchController.text);
                    });
                  }
                },
                builder: (context, state) {
                  if (state is DealsLoading || state is DealsError) {
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: 6,
                      itemBuilder: (_, __) => const LoadingShimmer(),
                    );
                  }

                  if (state is DealsLoaded) {
                    final result = state.result;
                    if (result.deals.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppTheme.bgInput,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.search_off,
                                  size: 40, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No results for "${widget.query}"',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try different keywords',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Total item count = deals + optional loading indicator
                    final itemCount = result.deals.length +
                        (result.hasMore || state.isLoadingMore ? 1 : 0);

                    return Column(
                      children: [
                        if (result.quotaWarning != null) ...[
                          const SizedBox(height: 8),
                          QuotaWarningBanner(message: result.quotaWarning!),
                        ],
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.textPrimary,
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.radiusFull),
                                ),
                                child: Text(
                                  '${result.total} results',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.bgMain,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${result.searchTimeMs}ms',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.62,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: itemCount,
                            itemBuilder: (_, i) {
                              // Last item = load more indicator
                              if (i >= result.deals.length) {
                                return _buildLoadMoreIndicator(state.isLoadingMore);
                              }
                              return DealCard(deal: result.deals[i]);
                            },
                          ),
                        ),
                      ],
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator(bool isLoading) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.textMuted,
                ),
              )
            : GestureDetector(
                onTap: () {
                  context.read<DealsBloc>().add(const DealsLoadMoreRequested());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Text(
                    'Load More',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
