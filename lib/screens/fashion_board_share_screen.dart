import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_client.dart';
import '../services/storyboard_service.dart';
import '../models/storyboard.dart';
import '../theme/app_theme.dart';
import 'fashion_board_screen.dart' show boardsRefreshNotifier;

class FashionBoardShareScreen extends StatefulWidget {
  final Map<String, dynamic> boardData;
  final String title;
  final Uint8List? imageBytes;
  final Storyboard? existingBoard;

  const FashionBoardShareScreen({
    super.key,
    required this.boardData,
    required this.title,
    this.imageBytes,
    this.existingBoard,
  });

  @override
  State<FashionBoardShareScreen> createState() =>
      _FashionBoardShareScreenState();
}

class _FashionBoardShareScreenState extends State<FashionBoardShareScreen> {
  final StoryboardService _service = StoryboardService(ApiClient());
  bool _saving = false;
  bool _saved = false;
  String? _shareUrl;
  String? _savedToken;
  bool _isPublic = true;
  bool _savedToGallery = false;

  @override
  void initState() {
    super.initState();
    // If we already have an existing board (came from editor that saved),
    // use it directly instead of creating a duplicate
    if (widget.existingBoard != null && widget.existingBoard!.token.isNotEmpty) {
      _saved = true;
      _saving = false;
      _shareUrl = widget.existingBoard!.shareUrl;
      _savedToken = widget.existingBoard!.token;
      _isPublic = widget.existingBoard!.isPublic;
    } else {
      _saveToServer();
    }
  }

  Future<void> _saveToServer() async {
    setState(() => _saving = true);
    try {
      final board = await _service.createStoryboard(
        title: widget.title,
        storyboardData: widget.boardData,
      );
      if (mounted) {
        setState(() {
          _saved = true;
          _saving = false;
          _shareUrl = board.shareUrl;
          _savedToken = board.token;
          _isPublic = board.isPublic;
        });
        // Notify boards list so it shows the new board immediately
        boardsRefreshNotifier.value++;
      }
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareBoard() async {
    if (widget.imageBytes != null) {
      // Share image
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fashion_board.png');
      await file.writeAsBytes(widget.imageBytes!);

      final text = _shareUrl != null
          ? 'Check out my fashion board! $_shareUrl'
          : 'Check out my fashion board on Outfi!';

      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
      );
    } else if (_shareUrl != null) {
      await Share.share('Check out my fashion board! $_shareUrl');
    }
  }

  Future<void> _saveToGallery() async {
    if (widget.imageBytes == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fashion_board_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(widget.imageBytes!);
      if (mounted) {
        setState(() => _savedToGallery = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Board saved to files')),
        );
      }
    } catch (_) {}
  }

  void _done() {
    // Notify boards list to refresh, then navigate
    boardsRefreshNotifier.value++;
    context.go('/boards');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top Bar ─────────────────
            _buildTopBar(),

            // ─── Preview ─────────────────
            Expanded(child: _buildPreview()),

            // ─── Actions ─────────────────
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgMain,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          const Expanded(
            child: Text(
              'Share Board',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: _done,
            child: const Text(
              'Done',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.info,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Board title
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Board preview
          if (widget.imageBytes != null)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  widget.imageBytes!,
                  fit: BoxFit.contain,
                ),
              ),
            )
          else
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dashboard_rounded,
                        size: 40, color: AppTheme.textMuted),
                    SizedBox(height: 8),
                    Text('Board Preview',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ],
                ),
              ),
            ),

          // Google logo below preview
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                AppTheme.googleLogoPath,
                height: 20,
                fit: BoxFit.contain,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Status
          if (_saving)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Text('Saving...',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              ],
            ),
          if (_saved) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 16, color: AppTheme.success),
                const SizedBox(width: 6),
                Text('Saved',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.success,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 20),
            // ─── Visibility Toggle ──────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(
                    _isPublic ? Icons.public : Icons.lock_outline,
                    size: 20,
                    color: _isPublic ? AppTheme.accent : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isPublic ? 'Public' : 'Private',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _isPublic
                              ? 'Anyone with the link can view'
                              : 'Only you can see this board',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _isPublic,
                    activeColor: AppTheme.accent,
                    onChanged: _savedToken == null
                        ? null
                        : (v) async {
                            setState(() => _isPublic = v);
                            try {
                              await _service.togglePublic(_savedToken!, v);
                            } catch (_) {
                              if (mounted) setState(() => _isPublic = !v);
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppTheme.bgMain,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Share button (primary)
          GestureDetector(
            onTap: _shareBoard,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.share_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Share Board',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Secondary actions
          Row(
            children: [
              Expanded(
                child: _SecondaryAction(
                  icon: _savedToGallery
                      ? Icons.check_rounded
                      : Icons.save_alt_rounded,
                  label: _savedToGallery ? 'Saved' : 'Save Image',
                  onTap: _savedToGallery ? null : _saveToGallery,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecondaryAction(
                  icon: Icons.link_rounded,
                  label: 'Copy Link',
                  onTap: _shareUrl != null
                      ? () {
                          // Copy to clipboard
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied')),
                          );
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SecondaryAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: onTap != null
                    ? AppTheme.textPrimary
                    : AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: onTap != null
                    ? AppTheme.textPrimary
                    : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
