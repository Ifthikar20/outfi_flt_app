import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'bloc/auth/auth_bloc.dart';
import 'bloc/deals/deals_bloc.dart';
import 'bloc/favorites/favorites_bloc.dart';

import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/deal_service.dart';
import 'services/favorites_service.dart';
import 'services/featured_service.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Stripe for Apple Pay
  Stripe.publishableKey =
      'pk_test_51TILuq3I87vPzCFd7eOqVXJoGagewgzN2Vr4SiEDlNfZeKvCoeUqa4h1O5ekXXEvTPj4TY8ENMzM792qC4li9YMW00O0y5aMc6';
  Stripe.merchantIdentifier = 'merchant.ai.outfi.app';

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppTheme.bgCard,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Create shared API client
  final apiClient = ApiClient();

  runApp(OutfiApp(apiClient: apiClient));
}

class OutfiApp extends StatelessWidget {
  final ApiClient apiClient;

  const OutfiApp({super.key, required this.apiClient});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<FeaturedService>(
      create: (_) => FeaturedService(apiClient),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(
              authService: AuthService(apiClient),
            ),
          ),
          BlocProvider<DealsBloc>(
            create: (_) => DealsBloc(
              dealService: DealService(apiClient),
            ),
          ),
          BlocProvider<FavoritesBloc>(
            create: (_) => FavoritesBloc(
              favoritesService: FavoritesService(apiClient),
            ),
          ),
        ],
        child: MaterialApp.router(
          title: 'Outfi',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
