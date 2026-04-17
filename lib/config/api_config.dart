/// Centralized API configuration.
///
/// All secrets are injected via `--dart-define` at build time.
/// Example build command:
/// ```bash
/// flutter build ios \
///   --dart-define=OUTFI_MOBILE_API_KEY=your-key \
///   --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
/// ```
class ApiConfig {
  static const String baseUrl = 'https://api.outfi.ai/api/v1/mobile';
  static const String webBaseUrl = 'https://outfi.ai';
  static const String apiHost = 'api.outfi.ai';

  // Local development:
  // static const String baseUrl = 'http://192.168.1.66:8000/api/v1/mobile';
  // static const String webBaseUrl = 'http://192.168.1.66:8000';
  // static const String apiHost = '192.168.1.66';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration imageUploadTimeout = Duration(seconds: 60);

  /// Single source of truth for the app version sent in API headers.
  /// Must stay in sync with the version in pubspec.yaml.
  static const String appVersion = '1.0.1';
  static const String minAppVersion = '1.0.0';

  // ── Secrets (injected via --dart-define) ───────────────────────

  /// Mobile API key — must match OUTFI_MOBILE_API_KEY in backend .env.
  /// Will be empty string if not provided at build time.
  static const String mobileApiKey =
      String.fromEnvironment('OUTFI_MOBILE_API_KEY');

  // OAuth
  static const String googleClientId =
      String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const String appleServiceId = 'com.outfi.app';

  // ── Certificate Pinning ───────────────────────────────────────
  // SHA-256 fingerprints of your TLS certificate chain (leaf + intermediate).
  // Generate with:
  //   openssl s_client -connect api.outfi.ai:443 | openssl x509 -pubkey -noout \
  //     | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
  //
  // ⚠️  UPDATE these before every certificate renewal (or pin the intermediate CA).
  static const List<String> certificatePins = [
    // TODO: Replace with real SHA-256 base64 hashes of your certificate's SPKI
    // 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',  // leaf
    // 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',  // intermediate / backup
  ];
}
