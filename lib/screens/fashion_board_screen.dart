import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/storyboard_service.dart';
import '../models/storyboard.dart';
import '../theme/app_theme.dart';

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
    _load();
  }

  @override
  void dispose() {
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
      try {
        await _service.deleteStoryboard(board.token);
        setState(() => _boards?.remove(board));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Board deleted')),
          );
        }
      } catch (_) {
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

  const _BoardCard({
    required this.board,
    required this.onTap,
    required this.onDelete,
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
                // Thumbnail area
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppTheme.radiusMd)),
                    child: items.isEmpty
                        ? Center(
                            child: Icon(Icons.dashboard_rounded,
                                size: 32, color: AppTheme.textMuted),
                          )
                        : _MiniThumbnail(items: items),
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
                          // Outfi logo watermark
                          Image.asset(
                            AppTheme.logoPath,
                            height: 12,
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

// ─── Mini Thumbnail Grid ───────────────────────
class _MiniThumbnail extends StatelessWidget {
  final List<dynamic> items;
  const _MiniThumbnail({required this.items});

  @override
  Widget build(BuildContext context) {
    final productItems = items
        .where((i) =>
            i is Map &&
            (i['type'] == 'product') &&
            (i['content'] ?? '').toString().startsWith('http'))
        .take(4)
        .toList();

    if (productItems.isEmpty) {
      return Center(
        child:
            Icon(Icons.style_rounded, size: 28, color: AppTheme.textMuted),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(6),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: productItems.map((item) {
        final url = item['content'] ?? '';
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppTheme.bgCardLight,
              child: const Icon(Icons.image,
                  size: 16, color: AppTheme.textMuted),
            ),
          ),
        );
      }).toList(),
    );
  }
}
