import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../config/api_config.dart';
import 'api_client.dart';

/// Handles APNs push notifications — no Firebase, direct Apple integration.
///
/// Flow:
///   1. Request notification permission from iOS
///   2. iOS returns an APNs device token
///   3. Send token to backend via POST /devices/
///   4. Backend stores it and uses it to send pushes when alerts trigger
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;
  PushNotificationService._();

  static const _channel = MethodChannel('ai.outfi.app/push');

  String? _deviceToken;
  bool _initialized = false;

  /// Initialize push notifications. Call once after user is authenticated.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Listen for token updates from native iOS
    _channel.setMethodCallHandler(_handleNativeCall);

    // Request permission + register for remote notifications
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      debugPrint('Push permission: $granted');
    } catch (e) {
      debugPrint('Push permission request failed: $e');
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onToken':
        _deviceToken = call.arguments as String?;
        debugPrint('APNs token received: ${_deviceToken?.substring(0, 20)}...');
        if (_deviceToken != null) {
          await _registerTokenWithBackend(_deviceToken!);
        }
      case 'onNotification':
        final data = call.arguments as Map?;
        debugPrint('Push notification received: $data');
        // Could navigate to alerts screen, show in-app banner, etc.
    }
  }

  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final api = ApiClient();
      final hasAuth = await api.hasTokens();
      if (!hasAuth) {
        debugPrint('No auth tokens — skipping device registration');
        return;
      }

      // Get device info
      final deviceInfo = DeviceInfoPlugin();
      final ios = await deviceInfo.iosInfo;

      await api.post('/devices/', data: {
        'token': token,
        'platform': 'ios',
        'device_id': ios.identifierForVendor ?? 'unknown',
        'device_name': ios.utsname.machine,
        'app_version': ApiConfig.appVersion,
        'os_version': ios.systemVersion,
      });
      debugPrint('Device token registered with backend');
    } catch (e) {
      debugPrint('Failed to register device token: $e');
    }
  }
}
