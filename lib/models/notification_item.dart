/// In-app notification feed entry. Matches the backend
/// `NotificationSerializer` shape.
class NotificationItem {
  final String id;
  final String kind; // new_matches, price_drop, alert_expired, alert_paused, subscription, system
  final String title;
  final String body;
  final String? alertId;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.alertId,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'system',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      alertId: json['alert_id']?.toString(),
      data: (json['data'] is Map)
          ? Map<String, dynamic>.from(json['data'] as Map)
          : const {},
      isRead: json['is_read'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
