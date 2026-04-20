import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/notification_item.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// In-app notification feed.
///
/// Shows alert status changes (new matches, price drops, alert
/// lifecycle events) produced server-side. Tapping a notification
/// opens the related alert detail page and marks it read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationService _service;
  List<NotificationItem> _items = [];
  int _unread = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = NotificationService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.list();
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _unread = result.unread;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load notifications.';
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_unread == 0) return;
    try {
      await _service.markAllRead();
    } catch (_) {
      // Non-fatal — try again on next load.
    }
    if (!mounted) return;
    setState(() {
      _items = _items.map((n) => _markedRead(n)).toList();
      _unread = 0;
    });
  }

  Future<void> _onTap(NotificationItem item) async {
    // Optimistically mark read; server call is fire-and-forget.
    if (!item.isRead) {
      setState(() {
        _items = _items
            .map((n) => n.id == item.id ? _markedRead(n) : n)
            .toList();
        _unread = (_unread - 1).clamp(0, _items.length);
      });
      _service.markRead([item.id]).catchError((_) => 0);
    }
    if (!mounted) return;
    // Deep-link if we have an alert id.
    final alertId = item.alertId ?? item.data['alert_id']?.toString();
    if (alertId != null && alertId.isNotEmpty) {
      context.push('/deal-alerts/$alertId');
    }
  }

  NotificationItem _markedRead(NotificationItem n) => NotificationItem(
        id: n.id,
        kind: n.kind,
        title: n.title,
        body: n.body,
        alertId: n.alertId,
        data: n.data,
        isRead: true,
        createdAt: n.createdAt,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMain,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.textPrimary),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: AppTheme.error),
        ),
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.notifications_none_rounded,
            size: 48,
            color: AppTheme.textMuted.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              "You're all caught up",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'New alert matches will show up here.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: AppTheme.border.withValues(alpha: 0.5),
        indent: 72,
      ),
      itemBuilder: (context, i) => _row(_items[i]),
    );
  }

  Widget _row(NotificationItem n) {
    return InkWell(
      onTap: () => _onTap(n),
      child: Container(
        color: n.isRead ? Colors.transparent : AppTheme.accent.withValues(alpha: 0.04),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kindIcon(n.kind, read: n.isRead),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          n.isRead ? FontWeight.w500 : FontWeight.w700,
                      color: AppTheme.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  if (n.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      n.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(n.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            if (!n.isRead)
              Container(
                margin: const EdgeInsets.only(top: 6, left: 6),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kindIcon(String kind, {required bool read}) {
    IconData icon;
    Color tint;
    switch (kind) {
      case 'new_matches':
        icon = Icons.local_offer_rounded;
        tint = AppTheme.accent;
        break;
      case 'price_drop':
        icon = Icons.trending_down_rounded;
        tint = AppTheme.success;
        break;
      case 'alert_expired':
      case 'alert_paused':
        icon = Icons.notifications_off_outlined;
        tint = AppTheme.textMuted;
        break;
      case 'subscription':
        icon = Icons.diamond_outlined;
        tint = AppTheme.accent;
        break;
      default:
        icon = Icons.notifications_rounded;
        tint = AppTheme.textSecondary;
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: read ? 0.08 : 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: tint, size: 20),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.month}/${t.day}/${t.year}';
  }
}
