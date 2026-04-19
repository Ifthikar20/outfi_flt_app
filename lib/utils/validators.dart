/// Client-side input validators for auth forms.
///
/// Backend is the source of truth; these exist to reject obvious garbage
/// before it hits the network.
class AuthValidators {
  static const int minPasswordLength = 8;

  static final RegExp _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  /// Returns null if the email is acceptable, otherwise a user-facing error.
  static String? email(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Please enter your email';
    if (!_emailRegex.hasMatch(trimmed)) return 'Please enter a valid email';
    return null;
  }

  /// Returns null if the password is acceptable, otherwise a user-facing error.
  static String? password(String value) {
    if (value.isEmpty) return 'Please enter your password';
    if (value.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters';
    }
    return null;
  }
}
