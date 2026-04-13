import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth/auth_bloc.dart';
import '../bloc/auth/auth_event.dart';
import '../bloc/auth/auth_state.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _scale;
  late Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5)),
    );
    _scale = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _taglineFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.8)),
    );
    _controller.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    context.read<AuthBloc>().add(AuthCheckRequested());
    await Future.delayed(const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          // Init push notifications AFTER auth — the device token
          // registration POST requires a valid auth header.
          PushNotificationService().init();
          context.go('/');
        } else if (state is AuthUnauthenticated) {
          context.go('/onboarding');
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFDFBF7),     // Warm white
                Color(0xFFF8F4ED),     // Cream
                Color(0xFFFDFBF7),     // Warm white
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Outfi Logo
                    Opacity(
                      opacity: _fadeIn.value,
                      child: Transform.scale(
                        scale: _scale.value,
                        child: Image.asset(
                          AppTheme.logoPath,
                          width: 200,
                          height: 200,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tagline
                    Opacity(
                      opacity: _taglineFade.value,
                      child: Text(
                        'Style. Curated.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.accent,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Loading indicator
                    Opacity(
                      opacity: _taglineFade.value,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppTheme.accent.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
