import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../bloc/image_search/image_search_bloc.dart';
import '../models/deal.dart';
import '../theme/app_theme.dart';
import '../services/freemium_gate_service.dart';
import '../services/location_service.dart';
import '../widgets/loading_shimmer.dart';
import '../widgets/paywall_sheet.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  String? _capturedImagePath;
  bool _isCapturing = false;
  bool _flashOn = false;
  final _locationService = LocationService();
  double? _userLat;
  double? _userLng;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _fetchLocation();
  }

  Future<void> _fetchLocation() async {
    final loc = _locationService.cachedLocation ??
        await _locationService.getCurrentLocation();
    if (loc != null && mounted) {
      setState(() {
        _userLat = loc.latitude;
        _userLng = loc.longitude;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
      if (mounted) setState(() => _isInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      // Guard: skip re-init if already initialized
      if (_controller == null || !_controller!.value.isInitialized) {
        _initCamera();
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'No camera found on this device.';
          });
        }
        return;
      }

      // Prefer back camera
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.medium, // medium (720p) is sufficient for visual search & inits ~30% faster
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString().contains('permission')
              ? 'Camera permission denied.\nGo to Settings > Outfi to enable.'
              : 'Could not initialize camera.';
        });
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final file = await _controller!.takePicture();
      if (mounted) {
        setState(() {
          _capturedImagePath = file.path;
          _isCapturing = false;
        });
        // Freemium gate: 3 free image searches per day, then paywall.
        final gate = FreemiumGateService();
        if (!await gate.canImageSearch()) {
          if (mounted) await showPaywallSheet(context);
          return;
        }
        await gate.recordImageSearch();
        if (!mounted) return;
        context.read<ImageSearchBloc>().add(
              ImageSearchRequested(imagePath: file.path, latitude: _userLat, longitude: _userLng),
            );
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not capture photo. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
      );
      if (photo != null && mounted) {
        setState(() => _capturedImagePath = photo.path);
        // Freemium gate: 3 free image searches per day, then paywall.
        final gate = FreemiumGateService();
        if (!await gate.canImageSearch()) {
          if (mounted) await showPaywallSheet(context);
          return;
        }
        await gate.recordImageSearch();
        if (!mounted) return;
        context.read<ImageSearchBloc>().add(
              ImageSearchRequested(imagePath: photo.path, latitude: _userLat, longitude: _userLng),
            );
      }
    } catch (e) {
      debugPrint('Gallery error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access gallery. Check permissions.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _retake() {
    setState(() => _capturedImagePath = null);
  }

  void _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      _flashOn = !_flashOn;
      await _controller!.setFlashMode(
        _flashOn ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // After capture — show results view
    if (_capturedImagePath != null) {
      return _buildResultsView(context);
    }

    // Camera preview view
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          if (_isInitialized && _controller != null)
            _buildCameraPreview()
          else if (_hasError)
            _buildErrorView()
          else
            _buildLoadingView(),

          // Top bar overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close
                  _CircleButton(
                    icon: Icons.close,
                    onTap: () => context.pop(),
                  ),
                  // Title
                  const Text(
                    'Outfi Lens',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  // Flash toggle
                  _CircleButton(
                    icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                    onTap: _toggleFlash,
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls overlay
          if (_isInitialized && !_hasError)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                  left: 32,
                  right: 32,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Point at any fashion item',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Gallery
                        _CircleButton(
                          icon: Icons.photo_library_rounded,
                          size: 48,
                          onTap: _pickFromGallery,
                        ),
                        // Capture
                        GestureDetector(
                          onTap: _capturePhoto,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 4,
                              ),
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _isCapturing
                                    ? Colors.grey
                                    : Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: _isCapturing
                                  ? const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        // Placeholder for symmetry
                        const SizedBox(width: 48, height: 48),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Focus target indicator (center)
          if (_isInitialized && !_hasError)
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final size = MediaQuery.of(context).size;
    final previewSize = _controller!.value.previewSize!;
    // Camera preview aspect ratio
    var scale = size.aspectRatio * previewSize.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Transform.scale(
      scale: scale,
      child: Center(
        child: CameraPreview(_controller!),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Initializing camera...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
                size: 56, color: Colors.white38),
            const SizedBox(height: 20),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _pickFromGallery,
              icon: const Icon(Icons.photo_library_rounded, size: 18),
              label: const Text('Choose from Gallery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Results View (after capture) ───────────────
  Widget _buildResultsView(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: CustomScrollView(
        slivers: [
          // Captured image header
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Captured image
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Image.file(
                    File(_capturedImagePath!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    cacheWidth: MediaQuery.of(context).size.width.toInt(), // constrain decode to screen width
                  ),
                ),
                // Gradient overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 100,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppTheme.bgMain,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Top buttons
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CircleButton(
                        icon: Icons.close,
                        onTap: () => context.pop(),
                      ),
                      _CircleButton(
                        icon: Icons.refresh_rounded,
                        onTap: _retake,
                      ),
                    ],
                  ),
                ),
                // Focus indicator on the image
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Results section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Text(
                    'SIMILAR PRODUCTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  BlocBuilder<ImageSearchBloc, ImageSearchState>(
                    builder: (context, state) {
                      if (state is ImageSearchLoaded) {
                        return Text(
                          '${state.result.total} found',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),

          // Results grid
          BlocConsumer<ImageSearchBloc, ImageSearchState>(
            listener: (context, state) {
              if (state is ImageSearchError && _capturedImagePath != null) {
                // Exponential backoff: 3s, 6s, 12s — max 3 retries
                _retryCount++;
                if (_retryCount <= 3) {
                  final delay = Duration(seconds: 3 * (1 << (_retryCount - 1)));
                  Future.delayed(delay, () {
                    if (mounted) {
                      context.read<ImageSearchBloc>().add(
                        ImageSearchRequested(imagePath: _capturedImagePath!, latitude: _userLat, longitude: _userLng),
                      );
                    }
                  });
                }
              }
              if (state is ImageSearchLoaded) {
                _retryCount = 0; // reset on success
              }
            },
            builder: (context, state) {
              if (state is ImageSearchLoading) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: Column(
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Finding similar items...',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              if (state is ImageSearchError) {
                // Show shimmer while retrying, or error msg after max retries
                if (_retryCount <= 3) {
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, __) => const LoadingShimmer(),
                        childCount: 4,
                      ),
                    ),
                  );
                }
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 48, color: AppTheme.textMuted),
                        const SizedBox(height: 16),
                        Text('Couldn\'t connect',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          'Check your connection and try again',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            _retryCount = 0;
                            context.read<ImageSearchBloc>().add(
                              ImageSearchRequested(imagePath: _capturedImagePath!, latitude: _userLat, longitude: _userLng),
                            );
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (state is ImageSearchLoaded && state.result.deals.isNotEmpty) {
                final cols = MediaQuery.of(context).size.width >= 600 ? 3 : 2;
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _ResultCard(deal: state.result.deals[i]),
                      childCount: state.result.deals.length,
                    ),
                  ),
                );
              }

              if (state is ImageSearchLoaded && state.result.deals.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      children: [
                        const Icon(Icons.search_off,
                            size: 48, color: AppTheme.textMuted),
                        const SizedBox(height: 16),
                        Text('No similar products found',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          'Try a clearer photo with better lighting',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return const SliverToBoxAdapter(child: SizedBox.shrink());
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ─── Circle Button ────────────────────────────────
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

// ─── Result Product Card ──────────────────────────
class _ResultCard extends StatelessWidget {
  final Deal deal;

  const _ResultCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          Expanded(
            flex: 3,
            child: deal.image != null
                ? CachedNetworkImage(
                    imageUrl: deal.image!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    memCacheWidth: 400,
                    fadeInDuration: const Duration(milliseconds: 200),
                    placeholder: (_, __) => Container(
                      color: AppTheme.bgCard,
                      child: const Center(
                        child: Icon(Icons.image_outlined,
                            color: AppTheme.textMuted, size: 28),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: AppTheme.bgCard,
                      child: const Center(
                        child: Icon(Icons.image_outlined,
                            color: AppTheme.textMuted, size: 28),
                      ),
                    ),
                  )
                : Container(
                    color: AppTheme.bgCard,
                    child: const Center(
                      child: Icon(Icons.shopping_bag_outlined,
                          color: AppTheme.textMuted, size: 28),
                    ),
                  ),
          ),

          // Details
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source / brand
                  if (deal.source.isNotEmpty)
                    Text(
                      deal.source.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  const SizedBox(height: 2),
                  // Title
                  Expanded(
                    child: Text(
                      deal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                  // Price
                  Row(
                    children: [
                      Text(
                        deal.formattedPrice,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (deal.hasDiscount) ...[
                        const SizedBox(width: 5),
                        Text(
                          deal.formattedOriginalPrice,
                          style: const TextStyle(
                            fontSize: 10,
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
    );
  }
}
