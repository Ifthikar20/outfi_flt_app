class Storyboard {
  final String? id;
  final String token;
  final String title;
  final String shareUrl;
  final bool isPublic;
  final int viewCount;
  final String snapshotUrl;
  final Map<String, dynamic> storyboardData;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  Storyboard({
    this.id,
    required this.token,
    required this.title,
    this.shareUrl = '',
    this.isPublic = true,
    this.viewCount = 0,
    this.snapshotUrl = '',
    this.storyboardData = const {},
    this.expiresAt,
    this.createdAt,
  });

  factory Storyboard.fromJson(Map<String, dynamic> json) {
    return Storyboard(
      id: json['id']?.toString(),
      token: json['token'] ?? '',
      title: json['title'] ?? '',
      shareUrl: json['share_url'] ?? '',
      isPublic: json['is_public'] ?? true,
      viewCount: json['view_count'] ?? 0,
      snapshotUrl: json['snapshot_url'] ?? '',
      storyboardData:
          json['storyboard_data'] as Map<String, dynamic>? ?? {},
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}
