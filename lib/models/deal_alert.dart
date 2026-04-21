class DealAlertMatch {
  final String id;
  final String dealId;
  final String title;
  final double? price;
  final String imageUrl;
  final String source;
  final String url;
  final bool isSeen;
  final DateTime? createdAt;

  DealAlertMatch({
    required this.id,
    required this.dealId,
    required this.title,
    this.price,
    this.imageUrl = '',
    this.source = '',
    this.url = '',
    this.isSeen = false,
    this.createdAt,
  });

  factory DealAlertMatch.fromJson(Map<String, dynamic> json) {
    return DealAlertMatch(
      id: json['id'] ?? '',
      dealId: json['deal_id'] ?? '',
      title: json['title'] ?? '',
      price: (json['price'] as num?)?.toDouble(),
      imageUrl: json['image_url'] ?? '',
      source: json['source'] ?? '',
      url: json['url'] ?? '',
      isSeen: json['is_seen'] ?? false,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }
}

class DealAlert {
  final String id;
  final String description;
  final String searchQuery;
  final String referenceImage;

  /// Server-computed best-effort thumbnail: reference image the user
  /// uploaded, else the latest match's image, else an empty string.
  /// The list view hides alerts with an empty thumbnail.
  final String thumbnailUrl;

  final double? maxPrice;
  final String status;
  final bool isActive;
  final DateTime? lastCheckedAt;
  final int matchesCount;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final List<DealAlertMatch> recentMatches;

  DealAlert({
    required this.id,
    required this.description,
    this.searchQuery = '',
    this.referenceImage = '',
    this.thumbnailUrl = '',
    this.maxPrice,
    this.status = 'active',
    this.isActive = true,
    this.lastCheckedAt,
    this.matchesCount = 0,
    this.expiresAt,
    this.createdAt,
    this.recentMatches = const [],
  });

  bool get isPaused => status == 'paused';
  bool get hasImage => referenceImage.isNotEmpty;

  /// The URL the list row should render. Falls through:
  ///   server `thumbnail_url` → `reference_image` → first recent match.
  /// Empty string means no image is available for this alert.
  String get displayThumbnail {
    if (thumbnailUrl.isNotEmpty) return thumbnailUrl;
    if (referenceImage.isNotEmpty) return referenceImage;
    for (final m in recentMatches) {
      if (m.imageUrl.isNotEmpty) return m.imageUrl;
    }
    return '';
  }

  factory DealAlert.fromJson(Map<String, dynamic> json) {
    final matchesList = json['recent_matches'] as List<dynamic>? ?? [];
    return DealAlert(
      id: json['id'] ?? '',
      description: json['description'] ?? '',
      searchQuery: json['search_query'] ?? '',
      referenceImage: json['reference_image'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '',
      maxPrice: json['max_price'] != null
          ? double.tryParse(json['max_price'].toString())
          : null,
      status: json['status'] ?? 'active',
      isActive: json['is_active'] ?? true,
      lastCheckedAt: json['last_checked_at'] != null ? DateTime.tryParse(json['last_checked_at']) : null,
      matchesCount: json['matches_count'] ?? 0,
      expiresAt: json['expires_at'] != null ? DateTime.tryParse(json['expires_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      recentMatches: matchesList.map((m) => DealAlertMatch.fromJson(m as Map<String, dynamic>)).toList(),
    );
  }
}
