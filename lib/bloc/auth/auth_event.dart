import 'package:equatable/equatable.dart';

// ─── Auth Events ─────────────────────────────────
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginRequested({required this.email, required this.password});

  // Password is intentionally excluded from props/toString to prevent
  // leakage via BLoC observers, devtools, and crash reporters.
  @override
  List<Object?> get props => [email];

  @override
  String toString() => 'AuthLoginRequested(email: $email)';
}

class AuthRegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String? firstName;
  final String? lastName;

  const AuthRegisterRequested({
    required this.email,
    required this.password,
    this.firstName,
    this.lastName,
  });

  @override
  List<Object?> get props => [email, firstName, lastName];

  @override
  String toString() =>
      'AuthRegisterRequested(email: $email, firstName: $firstName, lastName: $lastName)';
}

class AuthGoogleSignInRequested extends AuthEvent {}

class AuthAppleSignInRequested extends AuthEvent {}

class AuthLogoutRequested extends AuthEvent {}
