import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';

/// Fashion Timeline — shareable weekly/monthly outfit calendar.
///
/// Users log what they wore each day. The timeline can be shared
/// as a storyboard link showing a visual outfit calendar.
class FashionTimelineScreen extends StatefulWidget {
  const FashionTimelineScreen({super.key});

  @override
  State<FashionTimelineScreen> createState() => _FashionTimelineScreenState();
}

class _FashionTimelineScreenState extends State<FashionTimelineScreen> {
  final _api = ApiClient();
  late DateTime _currentMonth;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _sharing = false;

  // View mode
  bool _weekView = true;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final month = DateFormat('yyyy-MM').format(_currentMonth);
      final resp = await _api.get('/timeline/', params: {'month': month});
      final data = resp.data as Map<String, dynamic>;
      setState(() {
        _entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _entryForDate(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    for (final e in _entries) {
      if (e['date'] == dateStr) return e;
    }
    return null;
  }

  Future<void> _addEntry(DateTime date) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgMain,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddEntrySheet(date: date),
    );
    if (result != null) {
      try {
        await _api.post('/timeline/', data: {
          'date': DateFormat('yyyy-MM-dd').format(date),
          ...result,
        });
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save outfit')),
          );
        }
      }
    }
  }

  Future<void> _shareTimeline() async {
    setState(() => _sharing = true);
    try {
      final now = DateTime.now();
      String startDate, endDate;

      if (_weekView) {
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        startDate = DateFormat('yyyy-MM-dd').format(weekStart);
        endDate = DateFormat('yyyy-MM-dd').format(weekEnd);
      } else {
        startDate = DateFormat('yyyy-MM-01').format(_currentMonth);
        final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
        endDate = DateFormat('yyyy-MM-dd').format(lastDay);
      }

      final resp = await _api.post('/timeline/share/', data: {
        'start_date': startDate,
        'end_date': endDate,
      });
      final data = resp.data as Map<String, dynamic>;
      final shareUrl = data['share_url'] as String? ?? '';
      final title = data['title'] as String? ?? 'My Fashion Timeline';

      if (mounted && shareUrl.isNotEmpty) {
        await Share.share('$title\n$shareUrl');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to share timeline')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _deleteEntry(String dateStr) async {
    try {
      await _api.delete('/timeline/$dateStr/');
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        title: const Text('Fashion Timeline'),
        actions: [
          // View toggle
          IconButton(
            icon: Icon(_weekView ? Icons.calendar_month : Icons.view_week,
                size: 22),
            onPressed: () => setState(() => _weekView = !_weekView),
            tooltip: _weekView ? 'Month view' : 'Week view',
          ),
          // Share
          IconButton(
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share, size: 22),
            onPressed: _sharing ? null : _shareTimeline,
            tooltip: 'Share Timeline',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildMonthNav(),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_weekView)
            Expanded(child: _buildWeekView())
          else
            Expanded(child: _buildMonthView()),
        ],
      ),
    );
  }

  Widget _buildMonthNav() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(
                    _currentMonth.year, _currentMonth.month - 1);
              });
              _load();
            },
          ),
          Text(
            DateFormat('MMMM yyyy').format(_currentMonth),
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(
                    _currentMonth.year, _currentMonth.month + 1);
              });
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWeekView() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 7,
      itemBuilder: (ctx, i) {
        final day = weekStart.add(Duration(days: i));
        final entry = _entryForDate(day);
        final isToday = day.day == now.day && day.month == now.month;

        return GestureDetector(
          onTap: () => _addEntry(day),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isToday
                  ? AppTheme.accent.withValues(alpha: 0.06)
                  : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isToday ? AppTheme.accent : AppTheme.border,
                width: isToday ? 1.5 : 0.5,
              ),
            ),
            child: Row(
              children: [
                // Day label
                SizedBox(
                  width: 52,
                  child: Column(
                    children: [
                      Text(
                        DateFormat('E').format(day),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isToday
                              ? AppTheme.accent
                              : AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isToday
                              ? AppTheme.accent
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Outfit content
                Expanded(
                  child: entry != null
                      ? Row(
                          children: [
                            if ((entry['image_url'] ?? '').isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  entry['image_url'],
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            if ((entry['image_url'] ?? '').isNotEmpty)
                              const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry['title'] ?? 'Outfit',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if ((entry['mood'] ?? '').isNotEmpty)
                                    Text(
                                      entry['mood'],
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textMuted),
                                    ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _deleteEntry(entry['date']),
                              child: const Icon(Icons.close,
                                  size: 16, color: AppTheme.textMuted),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.bgInput,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppTheme.border, width: 0.5),
                              ),
                              child: const Icon(Icons.add,
                                  color: AppTheme.textMuted, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Tap to log outfit',
                              style: TextStyle(
                                  fontSize: 14, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthView() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth =
        DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday; // 1=Mon

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.7,
      ),
      itemCount: daysInMonth + startWeekday - 1,
      itemBuilder: (ctx, index) {
        if (index < startWeekday - 1) return const SizedBox.shrink();

        final dayNum = index - startWeekday + 2;
        final day = DateTime(_currentMonth.year, _currentMonth.month, dayNum);
        final entry = _entryForDate(day);
        final isToday = day.day == DateTime.now().day &&
            day.month == DateTime.now().month &&
            day.year == DateTime.now().year;

        return GestureDetector(
          onTap: () => _addEntry(day),
          child: Container(
            decoration: BoxDecoration(
              color: entry != null
                  ? AppTheme.accent.withValues(alpha: 0.1)
                  : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isToday ? AppTheme.accent : AppTheme.border,
                width: isToday ? 1.5 : 0.5,
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 2),
                Text(
                  '$dayNum',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isToday
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                  ),
                ),
                Expanded(
                  child: entry != null && (entry['image_url'] ?? '').isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              entry['image_url'],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.checkroom,
                                  size: 16,
                                  color: AppTheme.accent),
                            ),
                          ),
                        )
                      : entry != null
                          ? const Icon(Icons.checkroom,
                              size: 16, color: AppTheme.accent)
                          : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet for adding an outfit to a day.
class _AddEntrySheet extends StatefulWidget {
  final DateTime date;
  const _AddEntrySheet({required this.date});

  @override
  State<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<_AddEntrySheet> {
  final _titleController = TextEditingController();
  String _mood = '';

  static const _moods = [
    ('cozy', 'Cozy'),
    ('bold', 'Bold'),
    ('minimal', 'Minimal'),
    ('casual', 'Casual'),
    ('formal', 'Formal'),
    ('sporty', 'Sporty'),
    ('vintage', 'Vintage'),
    ('street', 'Street'),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Log Outfit — ${DateFormat('EEEE, MMM d').format(widget.date)}',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'What did you wear? e.g. "Black blazer + jeans"',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          const Text('Mood', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _moods.map((m) {
              final active = _mood == m.$1;
              return GestureDetector(
                onTap: () => setState(() => _mood = active ? '' : m.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? AppTheme.accent.withValues(alpha: 0.12)
                        : AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? AppTheme.accent : AppTheme.border,
                    ),
                  ),
                  child: Text(m.$2,
                      style: TextStyle(
                        fontSize: 13,
                        color: active
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w400,
                      )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'title': _titleController.text,
                  'mood': _mood,
                });
              },
              child: const Text('Save Outfit'),
            ),
          ),
        ],
      ),
    );
  }
}
