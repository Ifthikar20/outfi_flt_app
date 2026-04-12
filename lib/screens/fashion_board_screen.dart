import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/storyboard_service.dart';
import '../models/storyboard.dart';
import '../theme/app_theme.dart';

/// Global notifier to trigger board list refresh from anywhere
final boardsRefreshNotifier = ValueNotifier<int>(0);

class FashionBoardScreen extends StatefulWidget {
  const FashionBoardScreen({super.key});

  @override
  State<FashionBoardScreen> createState() => _FashionBoardScreenState();
}

class _FashionBoardScreenState extends State<FashionBoardScreen>
    with WidgetsBindingObserver {
  final StoryboardService _service = StoryboardService(ApiClient());
  List<Storyboard>? _boards;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    boardsRefreshNotifier.addListener(_onRefreshNotified);
    _load();
  }

  void _onRefreshNotified() => _load();

  @override
  void dispose() {
    boardsRefreshNotifier.removeListener(_onRefreshNotified);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Auto-refresh when returning to this screen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  // Called by router when navigating back
  void didPush() => _load();

  Future<void> _load() async {
    try {
      final list = await _service.getStoryboards();
      if (mounted) setState(() { _boards = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _createNew() async {
    await context.push('/boards/editor');
    // Refresh when returning from editor
    _load();
  }

  void _openBoard(Storyboard board) async {
    await context.push('/boards/editor', extra: {
      'storyboard': board,
    });
    _load();
  }

  void _shareBoard(Storyboard board) {
    context.push('/boards/share', extra: {
      'boardData': board.storyboardData,
      'title': board.title,
      'existingBoard': board,
    });
  }

  Future<void> _deleteBoard(Storyboard board) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgMain,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        title: const Text('Delete Board?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        content: Text(
          'This will permanently delete "${board.title.isEmpty ? "Untitled" : board.title}".',
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Optimistic removal — update UI immediately
      setState(() => _boards?.removeWhere((b) => b.token == board.token));

      try {
        await _service.deleteStoryboard(board.token);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Board deleted')),
          );
        }
        // Refresh from server to ensure consistency
        _load();
      } catch (_) {
        // Restore on failure
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete board')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Fashion Boards',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  _CreateButton(onTap: _createNew),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Create & share outfit mood boards',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Content ───────────────────
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textMuted,
                      ),
                    )
                  : (_boards == null || _boards!.isEmpty)
                      ? _EmptyState(onCreate: _createNew)
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppTheme.primary,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: _boards!.length,
                            itemBuilder: (_, i) => _BoardCard(
                              board: _boards![i],
                              onTap: () => _openBoard(_boards![i]),
                              onDelete: () => _deleteBoard(_boards![i]),
                              onShare: () => _shareBoard(_boards![i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Create Button ─────────────────────────────
class _CreateButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'New',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty State ───────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.dashboard_customize_rounded,
              size: 36,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No boards yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create your first fashion mood board',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onCreate,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: const Text(
                'Create Board',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Board Card ────────────────────────────────
class _BoardCard extends StatelessWidget {
  final Storyboard board;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onShare;

  const _BoardCard({
    required this.board,
    required this.onTap,
    required this.onDelete,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final items =
        (board.storyboardData['items'] as List<dynamic>?) ?? [];
    final bg =
        board.storyboardData['background'] as String? ?? '#F5F5F7';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: _parseColor(bg),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail area — use snapshot image if available
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppTheme.radiusMd)),
                    child: board.snapshotUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: board.snapshotUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            memCacheWidth: 400,
                            fadeInDuration: const Duration(milliseconds: 150),
                            errorWidget: (_, __, ___) => items.isNotEmpty
                                ? _MiniThumbnail(items: items, boardData: board.storyboardData)
                                : Center(child: Icon(Icons.dashboard_rounded, size: 32, color: AppTheme.textMuted)),
                          )
                        : items.isEmpty
                            ? Center(
                                child: Icon(Icons.dashboard_rounded,
                                    size: 32, color: AppTheme.textMuted),
                              )
                            : _MiniThumbnail(
                                items: items,
                                boardData: board.storyboardData,
                              ),
                  ),
                ),
                // Title + date + logo
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        board.title.isEmpty ? 'Untitled' : board.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Google logo watermark
                          SvgPicture.asset(
                            AppTheme.googleLogoPath,
                            height: 18,
                            fit: BoxFit.contain,
                          ),
                          const Spacer(),
                          if (board.createdAt != null)
                            Text(
                              _formatDate(board.createdAt!),
                              style: TextStyle(
                                  fontSize: 10, color: AppTheme.textMuted),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Share button
            if (onShare != null)
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: onShare,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.share_rounded,
                        size: 13, color: Colors.white),
                  ),
                ),
              ),
            // Delete button
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${dt.month}/${dt.day}/${dt.year}';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'Just now';
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppTheme.bgCard;
    }
  }
}

// ─── Canvas Preview — renders board exactly as designed ────────
class _MiniThumbnail extends StatelessWidget {
  final List<dynamic> items;
  final Map<String, dynamic> boardData;

  const _MiniThumbnail({required this.items, required this.boardData});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Icon(Icons.style_rounded, size: 28, color: AppTheme.textMuted),
      );
    }

    // Use the stored canvas dimensions from the editor.
    // Falls back to sensible defaults if not present (old boards).
    final canvasW = (boardData['canvasWidth'] as num?)?.toDouble() ?? 358;
    final canvasH = (boardData['canvasHeight'] as num?)?.toDouble() ?? 500;

    return LayoutBuilder(builder: (context, constraints) {
      final cardW = constraints.maxWidth;
      final cardH = constraints.maxHeight;

      // Scale uniformly to fit the card, preserving aspect ratio
      final scaleX = cardW / canvasW;
      final scaleY = cardH / canvasH;
      final scale = scaleX < scaleY ? scaleX : scaleY;

      // Center the scaled canvas in the card
      final offsetX = (cardW - canvasW * scale) / 2;
      final offsetY = (cardH - canvasH * scale) / 2;

      return ClipRect(
        child: Stack(
          children: items.map((item) {
            if (item is! Map) return const SizedBox.shrink();

            final type = item['type'] ?? '';
            final content = (item['content'] ?? '').toString();
            final x = (item['x'] as num?)?.toDouble() ?? 0;
            final y = (item['y'] as num?)?.toDouble() ?? 0;
            final w = (item['width'] as num?)?.toDouble() ?? 100;
            final h = (item['height'] as num?)?.toDouble() ?? 100;
            final rotation = (item['rotation'] as num?)?.toDouble() ?? 0;

            Widget child;
            if (type == 'product' && content.startsWith('http')) {
              child = CachedNetworkImage(
                imageUrl: content,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                fadeInDuration: const Duration(milliseconds: 150),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              );
            } else if (type == 'sticker') {
              child = FittedBox(
                child: Text(content, style: const TextStyle(fontSize: 40)),
              );
            } else if (type == 'text') {
              final meta = item['metadata'] as Map?;
              child = Text(
                content,
                style: TextStyle(
                  fontSize: ((meta?['fontSize'] as num?)?.toDouble() ?? 16) * scale,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              );
            } else {
              return const SizedBox.shrink();
            }

            return Positioned(
              left: offsetX + x * scale,
              top: offsetY + y * scale,
              width: w * scale,
              height: h * scale,
              child: Transform.rotate(
                angle: rotation,
                child: child,
              ),
            );
          }).toList(),
        ),
      );
    });
  }
}
