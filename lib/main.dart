import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';

import 'services/api_service.dart';
import 'services/local_auth_service.dart';
import 'services/storage_service.dart';
import 'services/firestore_service.dart';

import 'repositories/auth_repository.dart';
import 'repositories/weather_repository.dart';

import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/user_viewmodel.dart';
import 'viewmodels/weather_viewmodel.dart';

import 'views/auth/login_view.dart';
import 'views/home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final storageService = StorageService();
  await storageService.init();

  final apiService = ApiService();
  final localAuthService = LocalAuthService();
  final firestoreService = FirestoreService();

  final authRepository = AuthRepository(
    storageService: storageService,
    firestoreService: firestoreService,
    localAuthService: localAuthService,
  );

  final weatherRepository = WeatherRepository(
    apiService: apiService,
    storageService: storageService,
  );

  // Pre-load saved theme before runApp so there's no flash on startup
  final userVM = UserViewModel(
    authRepository: authRepository,
    firestoreService: firestoreService,
    storageService: storageService,
  );
  await userVM.loadTheme();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewModel>(
          create: (_) => AuthViewModel(authRepository: authRepository),
        ),

        ChangeNotifierProvider<WeatherViewModel>(
          create: (_) =>
              WeatherViewModel(weatherRepository: weatherRepository),
        ),

        ChangeNotifierProxyProvider2<AuthViewModel, WeatherViewModel,
            UserViewModel>(
          create: (_) => userVM,
          update: (_, authVM, weatherVM, previous) {
            final uvm = previous!;
            uvm.setWeatherViewModel(weatherVM);
            switch (authVM.status) {
              case AuthStatus.initial:
                return uvm;
              case AuthStatus.authenticated:
                uvm.onAuthStateChanged(authVM.currentUser);
                return uvm;
              case AuthStatus.unauthenticated:
              case AuthStatus.sessionExpired:
                uvm.onAuthStateChanged(null);
                return uvm;
            }
          },
        ),
      ],
      child: const SkyFitProApp(),
    ),
  );
}

class SkyFitProApp extends StatelessWidget {
  const SkyFitProApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<UserViewModel, ThemeMode>(
      (uvm) => uvm.themeMode,
    );

    return MaterialApp(
      title: 'SkyFit Pro',
      debugShowCheckedModeBanner: false,

      // ── Light Theme ──────────────────────────────────────────────────────
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0072FF),
          brightness: Brightness.light,
          surface: Colors.white,
          surfaceContainerHighest: const Color(0xFFEEF1F6),
          onSurface: const Color(0xFF1A1A2E),
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F2F8),
        cardColor: Colors.white,
        dividerColor: const Color(0xFFDDE1EA),
        useMaterial3: true,
      ),

      // ── Dark Theme ───────────────────────────────────────────────────────
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0072FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF0F0F1E),
          surfaceContainerHighest: const Color(0xFF12121E),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A14),
        cardColor: const Color(0xFF0F0F1E),
        dividerColor: const Color(0xFF1E1E30),
        useMaterial3: true,
      ),

      themeMode: themeMode,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authVM = context.watch<AuthViewModel>();

    switch (authVM.status) {
      case AuthStatus.initial:
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF00C6FF),
            ),
          ),
        );

      case AuthStatus.authenticated:
        return const HomeView();

      case AuthStatus.sessionExpired:
        return const LoginView(sessionExpired: true);

      case AuthStatus.unauthenticated:
      default:
        return const LoginView();
    }
  }
}

// ── App Theme Colors Helper ───────────────────────────────────────────────────
// Centralised so every view imports from one place (no new file needed).
class AC {
  AC._();

  /// Scaffold / page background
  static Color bg(BuildContext ctx) =>
      Theme.of(ctx).scaffoldBackgroundColor;

  /// Card / surface background
  static Color card(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.surface;

  /// Input field fill
  static Color input(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.surfaceContainerHighest;

  /// Divider / border color
  static Color border(BuildContext ctx) =>
      Theme.of(ctx).dividerColor;

  /// Primary text (headings, values)
  static Color text(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onSurface;

  /// Secondary / muted text
  static Color subtle(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onSurface.withOpacity(0.55);

  /// Extra-dim text (placeholders, hints)
  static Color dim(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onSurface.withOpacity(0.35);

  // ── Brand constants (same in both modes) ──────────────────────────────────
  static const Color accent  = Color(0xFF00C6FF);
  static const Color blue    = Color(0xFF0072FF);
  static const Color danger  = Color(0xFFFF4757);
  static const Color success = Color(0xFF2ECC71);
  static const Color warning = Color(0xFFFFA502);
}