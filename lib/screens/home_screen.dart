import 'dart:async';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/deals/deals_bloc.dart';
import '../bloc/deals/deals_event.dart';
import '../models/featured_content.dart';
import '../services/api_client.dart';
import '../services/featured_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
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
  final _prefsApi = ApiClient();
  LocationInfo? _location;
  int _maxDistanceMiles = 25;

  // API-driven data (replaces hardcoded demo data)
  List<FeaturedBrand> _brands = [];
  List<String> _searchPrompts = [];
  List<String> _suggestions = [];
  bool _featuredLoaded = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  // Notifications badge
  int _unreadNotifications = 0;
  Timer? _unreadPoll;

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
    // Poll the notification unread-count on a slow cadence. Server-side
    // query is indexed on (user, is_read) so this is cheap.
    _refreshUnread();
    _unreadPoll = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshUnread(),
    );
  }

  Future<void> _refreshUnread() async {
    try {
      // Cheap endpoint — returns only {unread, total}, no row payload.
      final result = await NotificationService(_prefsApi).summary();
      if (mounted) setState(() => _unreadNotifications = result.unread);
    } catch (_) {
      // Non-fatal — keep last known badge count.
    }
  }

  Future<void> _loadLocation() async {
    // 1. Try saved preferences first (user's remembered zip).
    try {
      final resp = await _prefsApi.get('/preferences/');
      final data = resp.data as Map<String, dynamic>? ?? const {};
      final lat = (data['default_latitude'] as num?)?.toDouble();
      final lng = (data['default_longitude'] as num?)?.toDouble();
      final name = data['default_location_name'] as String? ?? '';
      final radius = (data['max_distance_miles'] as num?)?.toInt();
      if (lat != null && lng != null) {
        if (mounted) {
          setState(() {
            _location = LocationInfo(
              city: name.isNotEmpty ? name : 'Saved location',
              area: '',
              country: '',
              latitude: lat,
              longitude: lng,
            );
            if (radius != null && radius > 0) _maxDistanceMiles = radius;
          });
          // Refresh feed with saved location so near-me results appear.
          context.read<DealsBloc>().add(DealsFetchTrending(
            nearMe: true,
            latitude: lat,
            longitude: lng,
            maxDistance: _maxDistanceMiles,
          ));
        }
        return;
      }
    } catch (_) {
      // Unauthenticated or offline — fall through to device GPS.
    }

    // 2. Fall back to device GPS (no persistence, no feed refresh).
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
            const SizedBox(height: 6),
            Text(
              'Enter a zip code to see deals nearby.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
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

  Future<void> _setLocationFromZip(String zip) async {
    // Show zip as location immediately while we geocode in the background.
    setState(() {
      _location = LocationInfo(
        city: zip,
        area: '',
        country: '',
        latitude: 0,
        longitude: 0,
      );
    });

    final loc = await _locationService.geocodeZip(zip);
    if (!mounted) return;

    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't find that zip code.")),
      );
      return;
    }

    setState(() => _location = loc);

    // Persist as user's default location so other screens (image search,
    // preferences) pick it up. Fire-and-forget: failure doesn't block the feed.
    try {
      await _prefsApi.patch('/preferences/', data: {
        'default_latitude': loc.latitude,
        'default_longitude': loc.longitude,
        'default_location_name': loc.displayName.isNotEmpty ? loc.displayName : zip,
        'max_distance_miles': _maxDistanceMiles,
      });
    } catch (_) {
      // Non-fatal — user can retry from preferences screen.
    }

    // Refresh the feed in near-me mode so local marketplace results appear.
    if (!mounted) return;
    context.read<DealsBloc>().add(DealsFetchTrending(
      nearMe: true,
      latitude: loc.latitude,
      longitude: loc.longitude,
      maxDistance: _maxDistanceMiles,
    ));
  }

  Future<void> _loadFeaturedContent() async {
    // Retry with exponential backoff on transient failures. The old path
    // flipped _featuredLoaded=true on the first error and gave up —
    // which is why brand cards sometimes disappeared after login when
    // the initial fetch raced auth/cold-start.
    const maxAttempts = _maxRetries;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final service = context.read<FeaturedService>();
        final content = await service.getFeaturedContent();
        if (!mounted) return;

        // Treat an empty brands array as a transient failure (backend
        // serves a static list; empty almost always means a blip).
        if (content.brands.isEmpty && attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 400 * attempt * attempt));
          continue;
        }

        setState(() {
          _brands = content.brands;
          _searchPrompts = content.searchPrompts;
          _suggestions = content.quickSuggestions;
          _featuredLoaded = true;
          _retryCount = 0;
        });
        _startPromptAnimation();
        return;
      } catch (e) {
        debugPrint(
            'Featured content attempt $attempt/$maxAttempts failed: $e');
        if (!mounted) return;
        if (attempt == maxAttempts) {
          // All retries exhausted — fall back to the built-in prompts
          // so the header animation still works, and leave _brands
          // empty so the brand row collapses instead of showing
          // half-broken UI.
          setState(() => _featuredLoaded = true);
          return;
        }
        await Future.delayed(Duration(milliseconds: 400 * attempt * attempt));
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
    _unreadPoll?.cancel();
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
                    // Location row + notifications bell
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
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
                                      _location?.displayName ??
                                          'Set your location',
                                      key: ValueKey(
                                          _location?.displayName ?? 'none'),
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
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: AppTheme.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Notifications bell with unread badge
                        InkResponse(
                          onTap: () async {
                            await context.push('/notifications');
                            if (mounted) _refreshUnread();
                          },
                          radius: 22,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(
                                  Icons.notifications_none_rounded,
                                  size: 22,
                                  color: AppTheme.textPrimary,
                                ),
                                if (_unreadNotifications > 0)
                                  Positioned(
                                    top: -2,
                                    right: -4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      constraints: const BoxConstraints(
                                          minWidth: 14, minHeight: 14),
                                      decoration: const BoxDecoration(
                                        color: AppTheme.error,
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(8)),
                                      ),
                                      child: Text(
                                        _unreadNotifications > 99
                                            ? '99+'
                                            : '$_unreadNotifications',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Logo + tagline
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Image.asset(
                          AppTheme.logoPath,
                          height: 80,
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
                  // Exponential backoff: 3s, 6s, 12s — max 3 retries
                  _retryCount++;
                  if (_retryCount <= _maxRetries) {
                    final delay = Duration(seconds: 3 * (1 << (_retryCount - 1)));
                    Future.delayed(delay, () {
                      if (mounted) {
                        context.read<DealsBloc>().add(DealsFetchTrending());
                      }
                    });
                  }
                }
                if (state is DealsLoaded) {
                  _retryCount = 0; // reset on success
                }
              },
              builder: (context, state) {
                if (state is DealsLoading || state is DealsInitial || state is DealsError) {
                    final cols = MediaQuery.of(context).size.width >= 600 ? 3 : 2;
                    return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
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
                  final cols = MediaQuery.of(context).size.width >= 600 ? 3 : 2;
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
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
