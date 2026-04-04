import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/board_item.dart';
import '../models/deal.dart';
import '../services/api_client.dart';
import '../services/deal_service.dart';
import '../services/background_removal_service.dart';
import '../models/storyboard.dart';
import '../services/storyboard_service.dart';
import '../theme/app_theme.dart';

class FashionBoardEditor extends StatefulWidget {
  final Storyboard? existingBoard;
  final Deal? initialDeal;
  const FashionBoardEditor({super.key, this.existingBoard, this.initialDeal});

  @override
  State<FashionBoardEditor> createState() => _FashionBoardEditorState();
}

class _FashionBoardEditorState extends State<FashionBoardEditor> {
  final GlobalKey _canvasKey = GlobalKey();
  final TextEditingController _titleCtrl =
      TextEditingController(text: 'My Board');
  final TextEditingController _searchCtrl = TextEditingController();
  final ApiClient _apiClient = ApiClient();
  late final DealService _dealService = DealService(_apiClient);
  late final BackgroundRemovalService _bgService = BackgroundRemovalService(_apiClient);

  final List<BoardItem> _items = [];
  Color _bgColor = const Color(0xFFF5F0EB);
  String? _bgPattern; // null = solid, or pattern name
  int _selectedItemIndex = -1;
  int _bottomTab = 0;
  bool _removingBg = false;
  bool _saving = false;
  String? _savedToken; // token of existing/saved board
  DateTime? _lastBgRemoveTime; // 15s cooldown (matches web app)

  // Search state
  List<Deal> _searchResults = [];
  bool _searching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    if (widget.existingBoard != null) {
      _loadExisting(widget.existingBoard!);
      _savedToken = widget.existingBoard!.token;
    }
    // Auto-add a deal passed from product detail
    if (widget.initialDeal != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addProductToCanvas(widget.initialDeal!);
      });
    }
  }

  void _loadExisting(Storyboard board) {
    _titleCtrl.text = board.title;
    final data = board.storyboardData;
    final bg = data['background'] as String?;
    if (bg != null) {
      try {
        _bgColor = Color(int.parse(bg.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    _bgPattern = data['pattern'] as String?;
    final items = data['items'] as List<dynamic>? ?? [];
    _items.addAll(
        items.map((i) => BoardItem.fromJson(i as Map<String, dynamic>)));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Search ──────────────────────────────────

  // Non-fashion keywords to filter out from board search results
  static const _nonFashionKeywords = [
    // Food & Baking
    'cake', 'cupcake', 'cookie', 'brownie', 'chocolate', 'candy', 'food',
    'recipe', 'baking', 'frosting', 'icing', 'sprinkle', 'donut', 'pastry',
    'bread', 'muffin', 'pie', 'tart', 'dessert', 'snack', 'cereal',
    'protein bar', 'gummy', 'sauce', 'spice', 'seasoning', 'syrup',
    'coffee', 'tea set', 'wine', 'beer', 'cocktail',
    // Kitchen & Dining
    'kitchen', 'cookware', 'bakeware', 'utensil', 'spatula', 'whisk',
    'mixing bowl', 'pan ', 'skillet', 'pot ', 'blender', 'toaster',
    'microwave', 'oven', 'dishwasher', 'plate', 'dinnerware', 'mug',
    'tumbler', 'cutting board', 'knife set',
    // Electronics & Tech
    'laptop', 'computer', 'monitor', 'keyboard', 'mouse pad', 'printer',
    'router', 'modem', 'hard drive', 'usb', 'charger', 'cable', 'adapter',
    'speaker', 'headphone', 'earbud', 'tablet', 'ipad', 'kindle',
    'gaming', 'controller', 'console', 'playstation', 'xbox', 'nintendo',
    // Toys & Baby
    'toy', 'lego', 'puzzle', 'board game', 'doll', 'action figure',
    'stuffed animal', 'plush', 'baby bottle', 'pacifier', 'diaper', 'stroller',
    // Home & Garden
    'furniture', 'mattress', 'pillow', 'comforter', 'curtain', 'rug',
    'carpet', 'lamp', 'light bulb', 'candle', 'vase', 'planter',
    'garden', 'lawn', 'fertilizer', 'pesticide', 'hose',
    // Tools & Auto
    'drill', 'hammer', 'wrench', 'screwdriver', 'power tool',
    'car ', 'tire', 'motor oil', 'windshield',
    // Pet
    'dog food', 'cat food', 'pet bed', 'pet toy', 'litter',
  ];

  bool _isFashionProduct(Deal deal) {
    final title = deal.title.toLowerCase();
    for (final keyword in _nonFashionKeywords) {
      if (title.contains(keyword)) return false;
    }
    return true;
  }

  Future<void> _doSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = []; // clear old results, shimmer will show
    });

    // Phase 1: instant cache check (~50ms)
    try {
      final instant = await _dealService.instantSearch(q);
      if (mounted && instant != null) {
        setState(() {
          _searchResults = instant.deals
              .where((d) => d.image != null && d.image!.isNotEmpty)
              .where(_isFashionProduct)
              .toList();
        });
      }
    } catch (_) {}

    // Phase 2: full marketplace search (3-5s)
    try {
      final result = await _dealService.search(query: q, limit: 40);
      if (mounted) {
        final filtered = result.deals
            .where((d) => d.image != null && d.image!.isNotEmpty)
            .where(_isFashionProduct)
            .toList();
        setState(() {
          _searchResults = filtered;
          _searching = false;
          if (filtered.isEmpty) _searchError = 'No fashion items found for "$q"';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          if (_searchResults.isEmpty) {
            _searchError = 'Search failed — check your connection';
          }
        });
      }
    }
  }

  void _addProductToCanvas(Deal deal) {
    final rand = Random();
    final cw = MediaQuery.of(context).size.width - 64;
    setState(() {
      _items.add(BoardItem(
        type: BoardItemType.product,
        content: deal.image ?? '',
        x: 10 + rand.nextDouble() * (cw - 120),
        y: 20 + rand.nextDouble() * 180,
        width: 110,
        height: 110,
        metadata: {
          'title': deal.title,
          'source': deal.source,
          'price': deal.price,
        },
      ));
      _selectedItemIndex = _items.length - 1;
    });
  }

  void _addSticker(String emoji) {
    final rand = Random();
    final cw = MediaQuery.of(context).size.width - 64;
    setState(() {
      _items.add(BoardItem(
        type: BoardItemType.sticker,
        content: emoji,
        x: 20 + rand.nextDouble() * (cw - 80),
        y: 40 + rand.nextDouble() * 180,
        width: 56,
        height: 56,
      ));
      _selectedItemIndex = _items.length - 1;
    });
  }

  void _addAssetSticker(String assetPath) {
    final rand = Random();
    final cw = MediaQuery.of(context).size.width - 64;
    setState(() {
      _items.add(BoardItem(
        type: BoardItemType.assetSticker,
        content: assetPath,
        x: 20 + rand.nextDouble() * (cw - 100),
        y: 30 + rand.nextDouble() * 160,
        width: 90,
        height: 90,
      ));
      _selectedItemIndex = _items.length - 1;
    });
  }

  void _addTextToCanvas(String text, String fontFamily, Color color) {
    final rand = Random();
    final cw = MediaQuery.of(context).size.width - 64;
    setState(() {
      _items.add(BoardItem(
        type: BoardItemType.text,
        content: text,
        x: 10 + rand.nextDouble() * (cw - 100),
        y: 30 + rand.nextDouble() * 180,
        width: 140,
        height: 36,
        metadata: {
          'font': fontFamily,
          'color': color.value,
        },
      ));
      _selectedItemIndex = _items.length - 1;
    });
  }

  void _showAddTextDialog() {
    final textCtrl = TextEditingController();
    String selectedFont = 'Serif';
    Color selectedColor = Colors.black;

    const fonts = ['Serif', 'Monospace', 'Cursive', 'Sans-Serif'];
    const colors = [
      Colors.black,
      Color(0xFF1A1A1A),
      Color(0xFF4A4A4A),
      Color(0xFF8B4513),
      Color(0xFF800020),
      Color(0xFF2F4F4F),
      Colors.white,
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgMain,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add Text',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: textCtrl,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: selectedFont == 'Sans-Serif'
                          ? null
                          : selectedFont.toLowerCase(),
                      color: selectedColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type something...',
                      filled: true,
                      fillColor: AppTheme.bgInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Font picker
                  const Text('Font',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: fonts.map((f) {
                      final sel = f == selectedFont;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedFont = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppTheme.primary
                                : AppTheme.bgCard,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusFull),
                            border: Border.all(
                                color:
                                    sel ? AppTheme.primary : AppTheme.border,
                                width: 0.5),
                          ),
                          child: Text(f,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: f == 'Sans-Serif'
                                    ? null
                                    : f.toLowerCase(),
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                              )),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  // Color picker
                  const Text('Color',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: colors.map((c) {
                      final sel = c.value == selectedColor.value;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: sel
                                    ? AppTheme.info
                                    : AppTheme.border,
                                width: sel ? 2.5 : 1),
                          ),
                          child: sel
                              ? Icon(Icons.check,
                                  size: 14,
                                  color: c.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final text = textCtrl.text.trim();
                        if (text.isNotEmpty) {
                          Navigator.pop(ctx);
                          _addTextToCanvas(text, selectedFont, selectedColor);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusFull)),
                      ),
                      child: const Text('Add to Board',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _deleteSelected() {
    if (_selectedItemIndex >= 0 && _selectedItemIndex < _items.length) {
      setState(() {
        _items.removeAt(_selectedItemIndex);
        _selectedItemIndex = -1;
      });
    }
  }

  Future<void> _removeBackground() async {
    if (_selectedItemIndex < 0 || _selectedItemIndex >= _items.length) return;
    final item = _items[_selectedItemIndex];
    if (item.type != BoardItemType.product) return;

    // If already processed, skip
    if (item.metadata?['bgRemoved'] == true) return;

    // 15-second cooldown between calls (matches web app)
    if (_lastBgRemoveTime != null) {
      final elapsed = DateTime.now().difference(_lastBgRemoveTime!);
      if (elapsed.inSeconds < 3) {
        final remaining = 3 - elapsed.inSeconds;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please wait ${remaining}s before removing another background'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }
    _lastBgRemoveTime = DateTime.now();

    // Mark as processing (shows shimmer)
    setState(() {
      _removingBg = true;
      item.metadata ??= {};
      item.metadata!['bgProcessing'] = true;
    });

    try {
      final resultBytes = await _bgService.removeBackgroundFromUrl(item.content);
      if (resultBytes != null && mounted) {
        setState(() {
          item.metadata ??= {};
          item.metadata!['bgRemoved'] = true;
          item.metadata!['bgRemovedBytes'] = resultBytes;
        });
      }
    } catch (e) {
      debugPrint('BG removal error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Background removal failed — try again'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _removingBg = false;
          item.metadata?.remove('bgProcessing');
        });
      }
    }
  }

  Future<Uint8List?> _captureCanvas() async {
    try {
      // Deselect before capture
      setState(() => _selectedItemIndex = -1);
      await Future.delayed(const Duration(milliseconds: 100));

      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveBoard() async {
    if (_saving) return;
    setState(() => _saving = true);

    final boardData = {
      'background': '#${_bgColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      if (_bgPattern != null) 'pattern': _bgPattern,
      'items': _items.map((i) {
        final json = i.toJson();
        // Double-ensure no binary data leaks into the payload
        if (json['metadata'] is Map) {
          (json['metadata'] as Map).remove('bgRemovedBytes');
          (json['metadata'] as Map).remove('bgProcessing');
        }
        return json;
      }).toList(),
    };

    // Debug: log payload size
    final payloadStr = boardData.toString();
    debugPrint('📏 Board save payload: ${payloadStr.length} chars, ${_items.length} items');

    try {
      final service = StoryboardService(_apiClient);
      if (_savedToken != null && _savedToken!.isNotEmpty) {
        // Update existing
        await service.updateStoryboard(
          token: _savedToken!,
          title: _titleCtrl.text,
          storyboardData: boardData,
        );
      } else {
        // Create new
        final created = await service.createStoryboard(
          title: _titleCtrl.text,
          storyboardData: boardData,
        );
        _savedToken = created.token;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Board saved ✓'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _done() async {
    final imageBytes = await _captureCanvas();
    if (!mounted || imageBytes == null) return;

    // Upload board snapshot to S3 and capture the path
    String? snapshotPath;
    try {
      final service = StoryboardService(_apiClient);
      final uploadResult = await service.uploadImage(imageBytes, filename: 'board_snapshot.jpg');
      debugPrint('Board snapshot uploaded: $uploadResult');
      // uploadResult is the URL — extract path for permanent storage
      // URL looks like: https://bucket.s3.region.amazonaws.com/storyboard/abc.jpg
      final uri = Uri.tryParse(uploadResult);
      if (uri != null && uri.path.isNotEmpty) {
        snapshotPath = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
      }
    } catch (e) {
      debugPrint('Snapshot upload failed (non-blocking): $e');
    }

    // Auto-save board data
    if (!_saving) await _saveBoard();

    if (!mounted) return;

    // Navigate to share screen with image bytes
    final title = _titleCtrl.text.isEmpty ? 'My Fashion Board' : _titleCtrl.text;
    final boardData = {
      'background': '#${_bgColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      if (_bgPattern != null) 'pattern': _bgPattern,
      if (snapshotPath != null) 'snapshot_path': snapshotPath,
      'items': _items.map((i) {
        final json = i.toJson();
        if (json['metadata'] is Map) {
          (json['metadata'] as Map).remove('bgRemovedBytes');
          (json['metadata'] as Map).remove('bgProcessing');
        }
        return json;
      }).toList(),
    };

    context.push('/boards/share', extra: {
      'boardData': boardData,
      'title': title,
      'imageBytes': imageBytes,
      'existingBoard': _savedToken != null
          ? Storyboard(token: _savedToken!, title: title, storyboardData: boardData)
          : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildCanvas()),
            _buildBottomToolbar(),
          ],
        ),
      ),
    );
  }

  // ─── Top Bar ────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.bgMain,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _titleCtrl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_selectedItemIndex >= 0) ...[                    
            // Remove BG button (product items only)
            if (_selectedItemIndex < _items.length &&
                _items[_selectedItemIndex].type == BoardItemType.product &&
                _items[_selectedItemIndex].metadata?['bgRemoved'] != true)
              GestureDetector(
                onTap: _removingBg ? null : _removeBackground,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _removingBg
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary))
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_fix_high_rounded,
                                size: 16, color: AppTheme.primary),
                            SizedBox(width: 4),
                            Text('Remove BG',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary)),
                          ],
                        ),
                ),
              ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _deleteSelected,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: AppTheme.error),
              ),
            ),
          ],
          const SizedBox(width: 8),
          // Save button
          GestureDetector(
            onTap: _saving ? null : _saveBoard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accent))
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            size: 16, color: AppTheme.accent),
                        SizedBox(width: 4),
                        Text('Save',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accent)),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _done,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: const Text('Done',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Canvas ─────────────────────────────────
  Widget _buildCanvas() {
    return GestureDetector(
      onTap: () => setState(() => _selectedItemIndex = -1),
      child: RepaintBoundary(
        key: _canvasKey,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _bgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Background layer
                Positioned.fill(
                  child: _bgPattern != null
                      ? CustomPaint(
                          painter: _FabricPatternPainter(
                            color: _bgColor,
                            pattern: _bgPattern!,
                          ),
                        )
                      : Container(color: _bgColor),
                ),
                // Items
                for (int i = 0; i < _items.length; i++)
                  _CanvasItemWidget(
                    key: ValueKey(_items[i].id),
                    item: _items[i],
                    isSelected: _selectedItemIndex == i,
                    onSelect: () => setState(() => _selectedItemIndex = i),
                    onMove: (dx, dy) {
                      setState(() {
                        _items[i].x += dx;
                        _items[i].y += dy;
                      });
                    },
                    onResize: (dw, dh) {
                      setState(() {
                        _items[i].width = (_items[i].width + dw).clamp(30, 600);
                        _items[i].height = (_items[i].height + dh).clamp(30, 600);
                      });
                    },
                    onRotate: (delta) {
                      setState(() {
                        _items[i].rotation += delta;
                      });
                    },
                  ),

                // Outfi watermark (captured in share image)
                Positioned(
                  bottom: 10,
                  right: 12,
                  child: Opacity(
                    opacity: 0.6,
                    child: Image.asset(
                      AppTheme.logoPath,
                      height: 28,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Bottom Toolbar ─────────────────────────
  Widget _buildBottomToolbar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgMain,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 200,
            child: IndexedStack(
              index: _bottomTab,
              children: [
                _buildSearchTab(),
                _buildStickersTab(),
                _buildBackgroundTab(),
              ],
            ),
          ),
          Row(
            children: [
              _ToolbarTab(
                icon: Icons.search_rounded,
                label: 'Search',
                active: _bottomTab == 0,
                onTap: () => setState(() => _bottomTab = 0),
              ),
              _ToolbarTab(
                icon: Icons.emoji_emotions_outlined,
                label: 'Stickers',
                active: _bottomTab == 1,
                onTap: () => setState(() => _bottomTab = 1),
              ),
              _ToolbarTab(
                icon: Icons.palette_outlined,
                label: 'Background',
                active: _bottomTab == 2,
                onTap: () => setState(() => _bottomTab = 2),
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  // ─── Search Tab ─────────────────────────────
  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: TextField(
            controller: _searchCtrl,
            onSubmitted: _doSearch,
            onChanged: (_) => setState(() {}), // refresh suffix icon
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search fashion items...',
              prefixIcon:
                  const Icon(Icons.search, size: 20, color: AppTheme.textMuted),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _searchResults = [];
                          _searchError = null;
                        });
                      },
                    ),
                  // Always-visible search button
                  IconButton(
                    icon: Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: _searchCtrl.text.trim().isNotEmpty
                          ? AppTheme.accent
                          : AppTheme.textMuted,
                    ),
                    onPressed: _searchCtrl.text.trim().isNotEmpty
                        ? () => _doSearch(_searchCtrl.text)
                        : null,
                  ),
                ],
              ),
              filled: true,
              fillColor: AppTheme.bgInput,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: _searching && _searchResults.isEmpty
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: 6,
                  itemBuilder: (_, __) => const _SkeletonResultTile(),
                )
              : _searchError != null && _searchResults.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(_searchError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: AppTheme.textMuted)),
                      ),
                    )
                  : _searchResults.isEmpty
                      ? Center(
                          child: Text('Search to find items',
                              style: TextStyle(
                                  fontSize: 13, color: AppTheme.textMuted)))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: _searchResults.length,
                          itemBuilder: (_, i) {
                            final deal = _searchResults[i];
                            return _SearchResultTile(
                              deal: deal,
                              onTap: () => _addProductToCanvas(deal),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  // ─── Stickers Tab ───────────────────────────
  Widget _buildStickersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fashion
          _sectionLabel('Fashion'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              '👗', '👠', '👜', '💄', '🕶️', '💎',
            ]
                .map((e) =>
                    _StickerChip(emoji: e, onTap: () => _addSticker(e)))
                .toList(),
          ),
          const SizedBox(height: 12),
          // Essentials
          _sectionLabel('Essentials'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              '✂️', '🧵', '📐', '🎀', '✨',
            ]
                .map((e) =>
                    _StickerChip(emoji: e, onTap: () => _addSticker(e)))
                .toList(),
          ),
          const SizedBox(height: 12),
          // Mood
          _sectionLabel('Mood'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              '🌸', '🔥', '🦋', '🌙', '💕', '🍃',
            ]
                .map((e) =>
                    _StickerChip(emoji: e, onTap: () => _addSticker(e)))
                .toList(),
          ),
          const SizedBox(height: 12),
          // Retro
          _sectionLabel('Retro'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ImageStickerChip(
                assetPath: 'assets/images/stickers/single-petel-png.png',
                onTap: () => _addAssetSticker(
                    'assets/images/stickers/single-petel-png.png'),
              ),
              ...['📻', '📺', '🎞️', '📷']
                  .map((e) =>
                      _StickerChip(emoji: e, onTap: () => _addSticker(e))),
            ],
          ),
          const SizedBox(height: 14),
          // Add Text button
          GestureDetector(
            onTap: _showAddTextDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.text_fields_rounded,
                      size: 18, color: AppTheme.textSecondary),
                  SizedBox(width: 6),
                  Text('Add Text',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary));

  // ─── Background Tab ─────────────────────────
  Widget _buildBackgroundTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Solid colors
          _sectionLabel('Colors'),
          const SizedBox(height: 8),
          _buildColorGrid(),
          const SizedBox(height: 16),
          // Fabric patterns
          _sectionLabel('Fabric Patterns'),
          const SizedBox(height: 8),
          _buildFabricGrid(),
        ],
      ),
    );
  }

  Widget _buildColorGrid() {
    const colors = [
      // Neutrals
      Color(0xFFF5F0EB), Color(0xFFFFFFFF), Color(0xFFF5F5F7),
      Color(0xFFE8E3DE), Color(0xFF1A1A1A), Color(0xFF2C2C2E),
      // Pastels
      Color(0xFFFCE4EC), Color(0xFFE8EAF6), Color(0xFFE0F2F1),
      Color(0xFFFFF3E0), Color(0xFFF3E5F5), Color(0xFFE8F5E9),
      // Fashion
      Color(0xFFFAD0C4), Color(0xFFA8EDEA), Color(0xFFD5AAFF),
      Color(0xFFFFE0B2), Color(0xFFB2EBF2), Color(0xFFF8BBD0),
      // Bold
      Color(0xFFFF6B6B), Color(0xFF4ECDC4), Color(0xFF45B7D1),
      Color(0xFFFECA57), Color(0xFFFF85A2), Color(0xFF6C5CE7),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) {
        final sel = _bgColor.value == color.value && _bgPattern == null;
        return GestureDetector(
          onTap: () => setState(() {
            _bgColor = color;
            _bgPattern = null;
          }),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel ? AppTheme.info : AppTheme.border,
                width: sel ? 2.5 : 0.5,
              ),
            ),
            child: sel
                ? Icon(Icons.check_rounded,
                    size: 16,
                    color: color.computeLuminance() > 0.5
                        ? AppTheme.textPrimary
                        : Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFabricGrid() {
    final fabrics = [
      _FabricOption('Linen', const Color(0xFFF0E6D3), 'linen'),
      _FabricOption('Denim', const Color(0xFF5B7FAE), 'denim'),
      _FabricOption('Silk', const Color(0xFFFAF0E6), 'silk'),
      _FabricOption('Tweed', const Color(0xFFB8A99A), 'tweed'),
      _FabricOption('Corduroy', const Color(0xFF8B7355), 'corduroy'),
      _FabricOption('Velvet', const Color(0xFF6B2D5B), 'velvet'),
      _FabricOption('Cotton', const Color(0xFFF5F5F0), 'cotton'),
      _FabricOption('Wool', const Color(0xFFCCC0B0), 'wool'),
      _FabricOption('Satin', const Color(0xFFE8D5E0), 'satin'),
      _FabricOption('Canvas', const Color(0xFFD4C9B8), 'canvas'),
      _FabricOption('Jersey', const Color(0xFF3A3A3A), 'jersey'),
      _FabricOption('Chiffon', const Color(0xFFF5E6F0), 'chiffon'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: fabrics.map((f) {
        final sel = _bgPattern == f.pattern;
        return GestureDetector(
          onTap: () => setState(() {
            _bgColor = f.color;
            _bgPattern = f.pattern;
          }),
          child: Container(
            width: 72,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel ? AppTheme.info : AppTheme.border,
                width: sel ? 2.5 : 0.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(sel ? 7 : 9),
              child: CustomPaint(
                painter: _FabricPatternPainter(
                  color: f.color,
                  pattern: f.pattern,
                ),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      f.name,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Fabric Option ──────────────────────────────
class _FabricOption {
  final String name;
  final Color color;
  final String pattern;
  const _FabricOption(this.name, this.color, this.pattern);
}

// ─── Fabric Pattern Painter ─────────────────────
class _FabricPatternPainter extends CustomPainter {
  final Color color;
  final String pattern;

  _FabricPatternPainter({required this.color, required this.pattern});

  @override
  void paint(Canvas canvas, Size size) {
    // Base fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = color,
    );

    final paint = Paint()..strokeWidth = 1;

    switch (pattern) {
      case 'linen':
        // Horizontal + vertical subtle lines
        paint.color = Colors.black.withValues(alpha: 0.06);
        for (double y = 0; y < size.height; y += 4) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (double x = 0; x < size.width; x += 6) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;

      case 'denim':
        // Diagonal twill lines
        paint.color = Colors.white.withValues(alpha: 0.08);
        for (double i = -size.height; i < size.width; i += 5) {
          canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
        }
        paint.color = Colors.black.withValues(alpha: 0.05);
        for (double i = 0; i < size.width + size.height; i += 8) {
          canvas.drawLine(Offset(i, 0), Offset(i - size.height, size.height), paint);
        }
        break;

      case 'silk':
        // Subtle shimmer lines
        paint.color = Colors.white.withValues(alpha: 0.15);
        paint.strokeWidth = 0.5;
        for (double y = 0; y < size.height; y += 12) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y + 2), paint);
        }
        break;

      case 'tweed':
        // Cross-hatching
        paint.color = Colors.black.withValues(alpha: 0.08);
        for (double i = 0; i < size.width + size.height; i += 6) {
          canvas.drawLine(Offset(i, 0), Offset(i - size.height, size.height), paint);
          canvas.drawLine(Offset(i - size.width, 0), Offset(i, size.height), paint);
        }
        // Dots
        paint.color = Colors.white.withValues(alpha: 0.1);
        for (double x = 3; x < size.width; x += 12) {
          for (double y = 3; y < size.height; y += 12) {
            canvas.drawCircle(Offset(x, y), 1, paint);
          }
        }
        break;

      case 'corduroy':
        // Vertical ridges
        paint.color = Colors.black.withValues(alpha: 0.12);
        paint.strokeWidth = 2;
        for (double x = 0; x < size.width; x += 6) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        paint.color = Colors.white.withValues(alpha: 0.06);
        paint.strokeWidth = 1;
        for (double x = 3; x < size.width; x += 6) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;

      case 'velvet':
        // Soft gradient effect with subtle noise
        paint.color = Colors.white.withValues(alpha: 0.03);
        final rand = Random(42);
        for (int i = 0; i < 200; i++) {
          final x = rand.nextDouble() * size.width;
          final y = rand.nextDouble() * size.height;
          canvas.drawCircle(Offset(x, y), rand.nextDouble() * 2, paint);
        }
        break;

      case 'cotton':
        // Simple woven texture
        paint.color = Colors.black.withValues(alpha: 0.04);
        for (double y = 0; y < size.height; y += 3) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (double x = 0; x < size.width; x += 3) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;

      case 'wool':
        // Fuzzy texture
        paint.color = Colors.black.withValues(alpha: 0.06);
        final rand = Random(99);
        for (int i = 0; i < 300; i++) {
          final x = rand.nextDouble() * size.width;
          final y = rand.nextDouble() * size.height;
          canvas.drawLine(
            Offset(x, y),
            Offset(x + rand.nextDouble() * 4, y + rand.nextDouble() * 4),
            paint,
          );
        }
        break;

      case 'satin':
        // Smooth horizontal waves
        paint.color = Colors.white.withValues(alpha: 0.12);
        paint.strokeWidth = 0.8;
        for (double y = 0; y < size.height; y += 8) {
          final path = Path();
          path.moveTo(0, y);
          for (double x = 0; x < size.width; x += 20) {
            path.quadraticBezierTo(x + 5, y - 1, x + 10, y);
            path.quadraticBezierTo(x + 15, y + 1, x + 20, y);
          }
          canvas.drawPath(path, paint);
        }
        break;

      case 'canvas':
        // Coarse weave
        paint.color = Colors.black.withValues(alpha: 0.08);
        paint.strokeWidth = 1.5;
        for (double y = 0; y < size.height; y += 8) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (double x = 0; x < size.width; x += 8) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;

      case 'jersey':
        // Knit pattern (V shapes)
        paint.color = Colors.white.withValues(alpha: 0.06);
        for (double y = 0; y < size.height; y += 10) {
          for (double x = 0; x < size.width; x += 8) {
            canvas.drawLine(Offset(x, y), Offset(x + 4, y + 5), paint);
            canvas.drawLine(Offset(x + 4, y + 5), Offset(x + 8, y), paint);
          }
        }
        break;

      case 'chiffon':
        // Sheer dots
        paint.color = Colors.white.withValues(alpha: 0.08);
        for (double x = 0; x < size.width; x += 10) {
          for (double y = 0; y < size.height; y += 10) {
            canvas.drawCircle(Offset(x, y), 0.8, paint);
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FabricPatternPainter old) =>
      old.color != color || old.pattern != pattern;
}

// ─── Canvas Item Widget (optimized) ─────────────
class _CanvasItemWidget extends StatefulWidget {
  final BoardItem item;
  final bool isSelected;
  final VoidCallback onSelect;
  final void Function(double dx, double dy) onMove;
  final void Function(double dw, double dh) onResize;
  final void Function(double delta) onRotate;

  const _CanvasItemWidget({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onSelect,
    required this.onMove,
    required this.onResize,
    required this.onRotate,
  });

  @override
  State<_CanvasItemWidget> createState() => _CanvasItemWidgetState();
}

class _CanvasItemWidgetState extends State<_CanvasItemWidget> {
  Offset? _rotateStart;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    Widget child;
    switch (item.type) {
      case BoardItemType.product:
        // If bg was removed, render transparent (no clip, no background)
        final bgBytes = item.metadata?['bgRemovedBytes'] as Uint8List?;
        final isProcessing = item.metadata?['bgProcessing'] == true;
        if (bgBytes != null) {
          child = Image.memory(bgBytes, fit: BoxFit.contain);
        } else {
          child = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: item.content,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              placeholder: (_, __) => Container(
                color: AppTheme.bgCardLight,
                child: const Center(
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5))),
              ),
              errorWidget: (_, __, ___) => Container(
                color: AppTheme.bgCardLight,
                child: const Icon(Icons.image, color: AppTheme.textMuted),
              ),
            ),
          );
        }
        // Shimmer overlay while processing
        if (isProcessing) {
          child = Stack(
            children: [
              child,
              Positioned.fill(
                child: _ShimmerOverlay(),
              ),
            ],
          );
        }
        break;
      case BoardItemType.sticker:
        child = FittedBox(
          child: Text(item.content, style: const TextStyle(fontSize: 40)),
        );
        break;
      case BoardItemType.text:
        final fontName = (item.metadata?['font'] as String?) ?? 'Serif';
        final textColor = item.metadata?['color'] != null
            ? Color(item.metadata!['color'] as int)
            : Colors.black;
        String? fontFamily;
        if (fontName == 'Serif') fontFamily = 'serif';
        else if (fontName == 'Monospace') fontFamily = 'monospace';
        else if (fontName == 'Cursive') fontFamily = 'cursive';
        // Sans-Serif = null (system default)
        child = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              item.content,
              style: TextStyle(
                  fontSize: 18,
                  fontFamily: fontFamily,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: 0.3),
            ),
          ),
        );
        break;
      case BoardItemType.assetSticker:
        child = Image.asset(
          item.content,
          fit: BoxFit.contain,
        );
        break;
    }

    return Positioned(
      left: item.x,
      top: item.y,
      child: GestureDetector(
        onTap: widget.onSelect,
        onPanUpdate: (d) => widget.onMove(d.delta.dx, d.delta.dy),
        child: Transform.rotate(
          angle: item.rotation,
          child: Container(
            width: item.width,
            height: item.height,
            decoration: widget.isSelected
                ? BoxDecoration(
                    border: Border.all(color: AppTheme.info, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(widget.isSelected ? 2 : 0),
                    child: child,
                  ),
                ),
                // ─── Rotation handle (top-center) ───
                if (widget.isSelected)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: -36,
                    child: Center(
                      child: GestureDetector(
                        onPanStart: (d) {
                          _rotateStart = d.globalPosition;
                        },
                        onPanUpdate: (d) {
                          if (_rotateStart == null) return;
                          // Calculate center of the item in global coords
                          final box =
                              context.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          final center = box.localToGlobal(
                              Offset(item.width / 2, item.height / 2));
                          final prev = atan2(
                              _rotateStart!.dy - center.dy,
                              _rotateStart!.dx - center.dx);
                          final curr = atan2(
                              d.globalPosition.dy - center.dy,
                              d.globalPosition.dx - center.dx);
                          widget.onRotate(curr - prev);
                          _rotateStart = d.globalPosition;
                        },
                        onPanEnd: (_) => _rotateStart = null,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.orange.shade400,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.rotate_right_rounded,
                                  size: 14, color: Colors.white),
                            ),
                            Container(
                              width: 1,
                              height: 8,
                              color: Colors.orange.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // ─── Resize handle (bottom-right) ───
                if (widget.isSelected)
                  Positioned(
                    right: -8,
                    bottom: -8,
                    child: GestureDetector(
                      onPanUpdate: (d) =>
                          widget.onResize(d.delta.dx, d.delta.dy),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.info,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.open_in_full_rounded,
                            size: 12, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Toolbar Tab ────────────────────────────────
class _ToolbarTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToolbarTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: active ? AppTheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 20,
                  color: active ? AppTheme.primary : AppTheme.textMuted),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? AppTheme.primary : AppTheme.textMuted,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Search Result Tile ─────────────────────────
/// Shimmer skeleton card shown while search results load
class _SkeletonResultTile extends StatefulWidget {
  const _SkeletonResultTile();

  @override
  State<_SkeletonResultTile> createState() => _SkeletonResultTileState();
}

class _SkeletonResultTileState extends State<_SkeletonResultTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Container(
          width: 100,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border, width: 0.5),
          ),
          child: Column(
            children: [
              // Image placeholder
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(10)),
                    gradient: LinearGradient(
                      begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
                      end: Alignment(-1.0 + 2.0 * _ctrl.value + 1.0, 0),
                      colors: const [
                        Color(0xFF2A2A2A),
                        Color(0xFF3A3A3A),
                        Color(0xFF2A2A2A),
                      ],
                    ),
                  ),
                ),
              ),
              // Text placeholders
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    Container(
                      height: 8,
                      width: 70,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 10,
                      width: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _SearchResultTile extends StatelessWidget {
  final Deal deal;
  final VoidCallback onTap;
  const _SearchResultTile({required this.deal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(10)),
                child: CachedNetworkImage(
                  imageUrl: deal.image ?? '',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  memCacheWidth: 200,
                  placeholder: (_, __) =>
                      Container(color: AppTheme.bgCardLight),
                  errorWidget: (_, __, ___) => Container(
                    color: AppTheme.bgCardLight,
                    child: const Icon(Icons.image, color: AppTheme.textMuted),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  Text(deal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w500)),
                  if (deal.price != null)
                    Text(deal.formattedPrice,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sticker Chip ───────────────────────────────
class _StickerChip extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  const _StickerChip({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
      ),
    );
  }
}

// ─── Image Sticker Chip ─────────────────────────
class _ImageStickerChip extends StatelessWidget {
  final String assetPath;
  final VoidCallback onTap;
  const _ImageStickerChip({required this.assetPath, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        padding: const EdgeInsets.all(4),
        child: Image.asset(assetPath, fit: BoxFit.contain),
      ),
    );
  }
}

// ─── Shimmer Overlay (shown during BG removal) ──
class _ShimmerOverlay extends StatefulWidget {
  @override
  State<_ShimmerOverlay> createState() => _ShimmerOverlayState();
}

class _ShimmerOverlayState extends State<_ShimmerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withValues(alpha: 0.15 + _ctrl.value * 0.35),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.content_cut_rounded,
                size: 22,
                color: AppTheme.accent.withValues(alpha: 0.6 + _ctrl.value * 0.4),
              ),
              const SizedBox(height: 4),
              Text(
                'Removing background...',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent.withValues(alpha: 0.6 + _ctrl.value * 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
