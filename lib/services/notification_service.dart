import '../models/notification_item.dart';
import 'api_client.dart';

/// Talks to /api/mobile/notifications/. Results are already scoped
/// to the authenticated user server-side — the client never passes
/// a user_id.
class NotificationService {
  final ApiClient _api;

  NotificationService(this._api);

  /// Fetch the feed. Returns (items, unreadCount, total).
  Future<({List<NotificationItem> items, int unread, int total})> list({
    bool unreadOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final resp = await _api.get('/notifications/', params: {
      if (unreadOnly) 'unread_only': 'true',
      'limit': limit,
      'offset': offset,
    });
    final data = resp.data as Map<String, dynamic>? ?? const {};
    final raw = data['notifications'] as List? ?? const [];
    final items = raw
        .whereType<Map>()
        .map((m) => NotificationItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return (
      items: items,
      unread: (data['unread_count'] as num?)?.toInt() ?? 0,
      total: (data['count'] as num?)?.toInt() ?? items.length,
    );
  }

  /// Mark specific notifications as read. Server silently ignores ids
  /// that don't belong to the user.
  Future<int> markRead(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final resp = await _api.post('/notifications/read/', data: {'ids': ids});
    final data = resp.data as Map<String, dynamic>? ?? const {};
    return (data['updated'] as num?)?.toInt() ?? 0;
  }

  /// Mark every notification as read.
  Future<int> markAllRead() async {
    final resp = await _api.post('/notifications/read/', data: {'all': true});
    final data = resp.data as Map<String, dynamic>? ?? const {};
    return (data['updated'] as num?)?.toInt() ?? 0;
  }
}
