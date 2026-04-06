import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/home_screen.dart';
import '../screens/search_results_screen.dart';
import '../screens/camera_screen.dart';
import '../screens/image_results_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/fashion_board_screen.dart';
import '../screens/fashion_board_editor.dart';
import '../screens/fashion_board_share_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/brand_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/paywall_screen.dart';
import '../screens/preferences_screen.dart';
import '../screens/deal_alerts_screen.dart';
import '../screens/fashion_timeline_screen.dart';
import '../screens/app_shell.dart';
import '../models/deal.dart';
import '../models/storyboard.dart';

// Navigation keys per tab – keeps pages alive when switching tabs
final _homeNavKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _favNavKey = GlobalKey<NavigatorState>(debugLabel: 'favorites');
final _boardsNavKey = GlobalKey<NavigatorState>(debugLabel: 'boards');
final _profileNavKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),

    // ─── Main App Shell (with bottom nav) — pages stay alive ──────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _homeNavKey,
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: HomeScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _favNavKey,
          routes: [
            GoRoute(
              path: '/favorites',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: FavoritesScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _boardsNavKey,
          routes: [
            GoRoute(
              path: '/boards',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: FashionBoardScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _profileNavKey,
          routes: [
            GoRoute(
              path: '/profile',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ProfileScreen(),
              ),
            ),
          ],
        ),
      ],
    ),

    // ─── Full-screen Pages ─────────────────────
    GoRoute(
      path: '/search',
      builder: (context, state) {
        final query = state.uri.queryParameters['q'] ?? '';
        return SearchResultsScreen(query: query);
      },
    ),
    GoRoute(
      path: '/camera',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const CameraScreen(),
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ),
    GoRoute(
      path: '/image-results',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ImageResultsScreen(
          imagePath: extra?['imagePath'] ?? '',
          latitude: extra?['latitude'] as double?,
          longitude: extra?['longitude'] as double?,
        );
      },
    ),
    GoRoute(
      path: '/boards/editor',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return FashionBoardEditor(
          existingBoard: extra?['storyboard'] as Storyboard?,
          initialDeal: extra?['addDeal'] as Deal?,
        );
      },
    ),
    GoRoute(
      path: '/boards/share',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FashionBoardShareScreen(
          boardData: extra['boardData'] as Map<String, dynamic>? ?? {},
          title: extra['title'] as String? ?? 'My Board',
          imageBytes: extra['imageBytes'] as Uint8List?,
          existingBoard: extra['existingBoard'] as Storyboard?,
        );
      },
    ),

    GoRoute(
      path: '/brand/:name',
      builder: (context, state) {
        final name = Uri.decodeComponent(state.pathParameters['name'] ?? '');
        return BrandScreen(brandName: name);
      },
    ),
    GoRoute(
      path: '/deal',
      builder: (context, state) {
        final deal = state.extra as Deal;
        return ProductDetailScreen(deal: deal);
      },
    ),
    GoRoute(
      path: '/preferences',
      builder: (context, state) => const PreferencesScreen(),
    ),
    GoRoute(
      path: '/deal-alerts',
      builder: (context, state) => const DealAlertsScreen(),
    ),
    GoRoute(
      path: '/timeline',
      builder: (context, state) => const FashionTimelineScreen(),
    ),
    GoRoute(
      path: '/premium',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const PaywallScreen(),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    ),
  ],
);
