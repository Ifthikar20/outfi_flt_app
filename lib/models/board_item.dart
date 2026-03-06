import 'dart:math';

enum BoardItemType { product, sticker, text, assetSticker }

class BoardItem {
  final String id;
  final BoardItemType type;
  String content; // image URL, emoji, or text (mutable for bg removal)
  double x;
  double y;
  double width;
  double height;
  double rotation; // radians
  Map<String, dynamic>? metadata; // product details, deal url, etc.

  BoardItem({
    String? id,
    required this.type,
    required this.content,
    this.x = 50,
    this.y = 50,
    this.width = 120,
    this.height = 120,
    this.rotation = 0,
    this.metadata,
  }) : id = id ?? _generateId();

  static String _generateId() {
    final rand = Random();
    return 'item_${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(9999)}';
  }

  Map<String, dynamic> toJson() {
    // Strip runtime-only keys from metadata (binary data, processing flags)
    Map<String, dynamic>? cleanMeta;
    if (metadata != null) {
      cleanMeta = Map.from(metadata!)
        ..remove('bgRemovedBytes')
        ..remove('bgProcessing');
    }
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'metadata': cleanMeta,
    };
  }

  factory BoardItem.fromJson(Map<String, dynamic> json) => BoardItem(
        id: json['id'],
        type: BoardItemType.values.byName(json['type'] ?? 'product'),
        content: json['content'] ?? '',
        x: (json['x'] as num?)?.toDouble() ?? 50,
        y: (json['y'] as num?)?.toDouble() ?? 50,
        width: (json['width'] as num?)?.toDouble() ?? 120,
        height: (json['height'] as num?)?.toDouble() ?? 120,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}
