import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../bloc/deals/deals_bloc.dart';
import '../bloc/deals/deals_event.dart';
import '../models/featured_content.dart';
import '../services/featured_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../widgets/deal_card.dart';
import '../widgets/loading_shimmer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _promptIndex = 0;
  Timer? _promptTimer;
  int _taglineIndex = 0;
  Timer? _taglineTimer;

  static const _taglines = [
    'Discover the latest',
    'Super hot fashion',
    'The best deals',
    'Style. Curated.',
  ];

  // Location
  final _locationService = LocationService();
  LocationInfo? _location;

  // API-driven data (replaces hardcoded demo data)
  List<FeaturedBrand> _brands = [];
  List<String> _searchPrompts = [];
  List<String> _suggestions = [];
  bool _featuredLoaded = false;

  // Fallback prompts shown while API loads
  static const _fallbackPrompts = [
    'Discover modest fashion...',
  ];

  @override
  void initState() {
    super.initState();
    context.read<DealsBloc>().add(DealsFetchTrending());
    _scrollController.addListener(_onScroll);
    _loadLocation();
    _loadFeaturedContent();
    _taglineTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _taglineIndex = (_taglineIndex + 1) % _taglines.length);
    });
  }

  Future<void> _loadLocation() async {
    final loc = await _locationService.getCurrentLocation();
    if (mounted && loc != null) {
      setState(() => _location = loc);
    }
  }

  void _showLocationPicker() {
    final zipController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgMain,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
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
              'Set your location',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),

            // Use GPS button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _loadLocation();
                },
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('Use current location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: const BorderSide(color: AppTheme.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Or enter zip
            Row(
              children: [
                Expanded(child: Divider(color: AppTheme.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or enter zip code', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
                Expanded(child: Divider(color: AppTheme.border)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: zipController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Zip / Postal code',
                      prefixIcon: const Icon(Icons.pin_drop_outlined, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        Navigator.pop(ctx);
                        _setLocationFromZip(val.trim());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final val = zipController.text.trim();
                      if (val.isNotEmpty) {
                        Navigator.pop(ctx);
                        _setLocationFromZip(val);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                    ),
                    child: const Text('Set'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _setLocationFromZip(String zip) {
    // Show zip as location immediately, geocode in background
    setState(() {
      _location = LocationInfo(
        city: zip,
        area: '',
        country: '',
        latitude: 0,
        longitude: 0,
      );
    });
    // Try to geocode the zip
    _locationService.geocodeZip(zip).then((loc) {
      if (mounted && loc != null) {
        setState(() => _location = loc);
      }
    });
  }

  Future<void> _loadFeaturedContent() async {
    try {
      final service = context.read<FeaturedService>();
      final content = await service.getFeaturedContent();
      if (mounted) {
        setState(() {
          _brands = content.brands;
          _searchPrompts = content.searchPrompts;
          _suggestions = content.quickSuggestions;
          _featuredLoaded = true;
        });
        _startPromptAnimation();
      }
    } catch (e) {
      // Silently fail — the home screen still works with trending deals
      debugPrint('Failed to load featured content: $e');
      if (mounted) {
        setState(() => _featuredLoaded = true);
      }
    }
  }

  void _startPromptAnimation() {
    if (_searchPrompts.isEmpty) return;
    _promptTimer?.cancel();
    _promptTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() => _promptIndex = (_promptIndex + 1) % _searchPrompts.length);
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      context.read<DealsBloc>().add(const DealsLoadMoreRequested());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _promptTimer?.cancel();
    _taglineTimer?.cancel();
    super.dispose();
  }

  List<String> get _activePrompts =>
      _searchPrompts.isNotEmpty ? _searchPrompts : _fallbackPrompts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // ─── Location + Logo Header ─────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Location row
                    GestureDetector(
                      onTap: _showLocationPicker,
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: _location != null
                                ? AppTheme.textPrimary
                                : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                _location?.displayName ?? 'Set your location',
                                key: ValueKey(_location?.displayName ?? 'none'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _location != null
                                      ? AppTheme.textPrimary
                                      : AppTheme.textMuted,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: AppTheme.textMuted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Logo + tagline
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SvgPicture.asset(
                          AppTheme.googleLogoPath,
                          height: 40,
                          fit: BoxFit.contain,
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 500),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: child,
                            ),
                            child: Text(
                              _taglines[_taglineIndex],
                              key: ValueKey(_taglineIndex),
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ─── Prompt Search Box ───────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: GestureDetector(
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppTheme.bgMain,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => _SearchSheet(
                        suggestions: _suggestions,
                        onSearch: (q) {
                          Navigator.pop(context);
                          context.push('/search?q=$q');
                        },
                      ),
                    );
                  },
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.bgInput,
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      border: Border.all(color: AppTheme.border, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              _activePrompts[_promptIndex % _activePrompts.length],
                              key: ValueKey(_promptIndex),
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ─── Featured Brands ──────────────
            if (_brands.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
                  child: Text(
                    'EXPLORE BRANDS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),

              // Brand carousel
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _brands.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => context.push(
                        '/brand/${Uri.encodeComponent(_brands[i].name)}',
                      ),
                      child: _BrandCard(brand: _brands[i]),
                    ),
                  ),
                ),
              ),
            ],

            // ─── Trending / Brand sections ───────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 14),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PICKED FOR YOU',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Trending Deals',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.push('/search?q=trending'),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const Icon(Icons.chevron_right, size: 18, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Deals grid
            BlocConsumer<DealsBloc, DealsState>(
              listener: (context, state) {
                if (state is DealsError) {
                  // Retry once after 3s — listener fires once per state change
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted) {
                      context.read<DealsBloc>().add(DealsFetchTrending());
                    }
                  });
                }
              },
              builder: (context, state) {
                if (state is DealsLoading || state is DealsInitial || state is DealsError) {
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, __) => const LoadingShimmer(),
                        childCount: 6,
                      ),
                    ),
                  );
                }

                if (state is DealsLoaded) {
                  final deals = state.result.deals;
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => DealCard(
                          deal: deals[i],
                          showTrendingTag: true,
                        ),
                        childCount: deals.length,
                      ),
                    ),
                  );
                }

                return const SliverToBoxAdapter(child: SizedBox.shrink());
              },
            ),

            // Loading more indicator
            BlocBuilder<DealsBloc, DealsState>(
              builder: (context, state) {
                if (state is DealsLoaded && state.isLoadingMore) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  );
                }
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

// ─── Brand Card (API-driven) ────────────────────
class _BrandCard extends StatelessWidget {
  final FeaturedBrand brand;

  const _BrandCard({required this.brand});

  // Hash-based color generation for variety
  Color get _brandColor {
    final hash = brand.name.hashCode;
    final hue = (hash % 360).abs().toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.25, 0.18).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: _brandColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _brandColor.withValues(alpha: 0.3),
                    _brandColor,
                  ],
                ),
              ),
            ),
          ),

          // Brand initial (large, faded)
          Positioned(
            right: -10,
            top: 10,
            child: Text(
              brand.initial,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.08),
                fontSize: 100,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),

          // Brand name
          Positioned(
            left: 14,
            bottom: 40,
            child: Text(
              brand.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),

          // Category label
          Positioned(
            left: 14,
            bottom: 16,
            child: Text(
              brand.category,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Like count pill (top-right)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    brand.isLiked ? Icons.favorite : Icons.favorite_border,
                    color: brand.isLiked ? Colors.redAccent : Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${brand.likesCount}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Search Bottom Sheet ────────────────────────
class _SearchSheet extends StatefulWidget {
  final ValueChanged<String> onSearch;
  final List<String> suggestions;

  const _SearchSheet({required this.onSearch, required this.suggestions});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  // Fallback suggestions if API returned empty
  static const _fallbackSuggestions = [
    'Black leather jacket',
    'Summer dresses',
    'Nike sneakers',
    'Designer handbag',
  ];

  List<String> get _activeSuggestions =>
      widget.suggestions.isNotEmpty ? widget.suggestions : _fallbackSuggestions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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
            const SizedBox(height: 16),

            // Search field
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              onSubmitted: (q) {
                if (q.isNotEmpty) widget.onSearch(q);
              },
              decoration: InputDecoration(
                hintText: 'Search for an item...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded, size: 20),
                  onPressed: () {
                    if (_controller.text.isNotEmpty) {
                      widget.onSearch(_controller.text);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Suggestion chips
            Text(
              'TRY SEARCHING',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _activeSuggestions.map((s) => GestureDetector(
                onTap: () => widget.onSearch(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    s,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
