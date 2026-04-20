import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provides a stable, persistent device identifier for iOS.
///
/// Uses `identifierForVendor` (persists until app uninstall). When that
/// value is unavailable, generates a random 128-bit ID and persists it in
/// secure storage so subsequent launches reuse the same value.
class DeviceInfoService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _fallbackIdKey = 'device_id_fallback';
  static String? _cachedDeviceId;

  /// Returns a stable device ID. Caches after first call.
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _cachedDeviceId =
            iosInfo.identifierForVendor ?? await _persistentFallbackId();
      } else {
        // Non-iOS platforms aren't supported, but we still return a stable
        // id so unit tests and dev simulators don't crash.
        _cachedDeviceId = await _persistentFallbackId();
      }
    } catch (_) {
      _cachedDeviceId = await _persistentFallbackId();
    }

    return _cachedDeviceId!;
  }

  /// Returns the platform name for the current device.
  static String getPlatform() {
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Reads (or generates and persists) a random 128-bit device ID in secure
  /// storage. This survives hot restarts and app relaunches.
  static Future<String> _persistentFallbackId() async {
    try {
      final existing = await _storage.read(key: _fallbackIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final generated = _randomUuidV4();
      await _storage.write(key: _fallbackIdKey, value: generated);
      return generated;
    } catch (_) {
      // Secure storage unavailable (extremely rare) — return an ephemeral ID
      // that at least isn't trivially predictable.
      return _randomUuidV4();
    }
  }

  /// Generates a RFC 4122 v4 UUID using a cryptographic RNG.
  static String _randomUuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xxxxxx
    String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    final s = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) s.write('-');
      s.write(hex(i));
    }
    return s.toString();
  }
}
