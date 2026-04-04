import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';

/// User preferences screen — location, style, distance.
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  final _api = ApiClient();
  bool _loading = true;
  bool _saving = false;

  // Location
  String _locationName = '';
  double? _latitude;
  double? _longitude;
  double _maxDistance = 25;

  // Style
  String _gender = '';
  List<String> _sizes = [];
  List<String> _styles = [];

  static const _allSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];
  static const _allStyles = [
    'Casual',
    'Streetwear',
    'Modest',
    'Formal',
    'Athletic',
    'Vintage',
    'Minimalist',
    'Bohemian',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await _api.get('/preferences/');
      final data = resp.data as Map<String, dynamic>;
      setState(() {
        _locationName = data['default_location_name'] ?? '';
        _latitude = (data['default_latitude'] as num?)?.toDouble();
        _longitude = (data['default_longitude'] as num?)?.toDouble();
        _maxDistance = (data['max_distance_miles'] as num?)?.toDouble() ?? 25;
        _gender = data['preferred_gender'] ?? '';
        _sizes = List<String>.from(data['preferred_sizes'] ?? []);
        _styles = List<String>.from(data['preferred_styles'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.patch('/preferences/', data: {
        'default_location_name': _locationName,
        'default_latitude': _latitude,
        'default_longitude': _longitude,
        'max_distance_miles': _maxDistance.round(),
        'preferred_gender': _gender,
        'preferred_sizes': _sizes,
        'preferred_styles': _styles,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferences saved')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _detectLocation() async {
    try {
      final loc = await LocationService().getCurrentLocation();
      if (loc != null && mounted) {
        setState(() {
          _locationName = loc.displayName;
          _latitude = loc.latitude;
          _longitude = loc.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not detect location')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        title: const Text('Preferences'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: AppTheme.accent)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Location ───────────────────
                  _sectionTitle('Location'),
                  const SizedBox(height: 8),
                  _locationCard(),
                  const SizedBox(height: 16),

                  // Distance slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Max Distance',
                          style: TextStyle(fontSize: 15)),
                      Text('${_maxDistance.round()} mi',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent)),
                    ],
                  ),
                  Slider(
                    value: _maxDistance,
                    min: 5,
                    max: 200,
                    divisions: 39,
                    activeColor: AppTheme.accent,
                    label: '${_maxDistance.round()} mi',
                    onChanged: (v) => setState(() => _maxDistance = v),
                  ),

                  const SizedBox(height: 28),

                  // ─── Gender ─────────────────────
                  _sectionTitle('Gender Preference'),
                  const SizedBox(height: 12),
                  _chipRow(
                    options: ['', 'men', 'women', 'unisex'],
                    labels: ['All', 'Men', 'Women', 'Unisex'],
                    selected: _gender,
                    onSelect: (v) => setState(() => _gender = v),
                  ),

                  const SizedBox(height: 28),

                  // ─── Sizes ──────────────────────
                  _sectionTitle('Sizes'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allSizes.map((s) {
                      final active = _sizes.contains(s);
                      return GestureDetector(
                        onTap: () => setState(() {
                          active ? _sizes.remove(s) : _sizes.add(s);
                        }),
                        child: Container(
                          width: 52,
                          height: 40,
                          decoration: BoxDecoration(
                            color: active
                                ? AppTheme.accent.withValues(alpha: 0.12)
                                : AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  active ? AppTheme.accent : AppTheme.border,
                              width: active ? 1.5 : 0.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(s,
                              style: TextStyle(
                                fontWeight:
                                    active ? FontWeight.w600 : FontWeight.w400,
                                color: active
                                    ? AppTheme.accent
                                    : AppTheme.textSecondary,
                              )),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 28),

                  // ─── Styles ─────────────────────
                  _sectionTitle('Style Preferences'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allStyles.map((s) {
                      final active = _styles.contains(s.toLowerCase());
                      return GestureDetector(
                        onTap: () => setState(() {
                          final lower = s.toLowerCase();
                          active
                              ? _styles.remove(lower)
                              : _styles.add(lower);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: active
                                ? AppTheme.accent.withValues(alpha: 0.12)
                                : AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  active ? AppTheme.accent : AppTheme.border,
                              width: active ? 1.5 : 0.5,
                            ),
                          ),
                          child: Text(s,
                              style: TextStyle(
                                fontWeight:
                                    active ? FontWeight.w600 : FontWeight.w400,
                                color: active
                                    ? AppTheme.accent
                                    : AppTheme.textSecondary,
                              )),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _locationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined,
              color: AppTheme.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _locationName.isNotEmpty ? _locationName : 'No location set',
              style: TextStyle(
                fontSize: 15,
                color: _locationName.isNotEmpty
                    ? AppTheme.textPrimary
                    : AppTheme.textMuted,
              ),
            ),
          ),
          GestureDetector(
            onTap: _detectLocation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.my_location, size: 14, color: AppTheme.accent),
                  SizedBox(width: 4),
                  Text('Detect',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipRow({
    required List<String> options,
    required List<String> labels,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      children: List.generate(options.length, (i) {
        final active = selected == options[i];
        return GestureDetector(
          onTap: () => onSelect(options[i]),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppTheme.textPrimary : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? AppTheme.textPrimary : AppTheme.border,
                width: 0.5,
              ),
            ),
            child: Text(labels[i],
                style: TextStyle(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? Colors.white : AppTheme.textSecondary,
                )),
          ),
        );
      }),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
          letterSpacing: -0.3,
        ));
  }
}
