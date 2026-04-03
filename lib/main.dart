import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/db_service.dart';
import 'providers/db_provider.dart';
import 'ui/app_lock_screen.dart';
import 'ui/onboarding_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Crashlytics only in release mode so it never blocks dev workflows.
  // Wrapped in try-catch so a missing Crashlytics setup never prevents the app from launching.
  if (!kDebugMode) {
    try {
      FlutterError.onError = (errorDetails) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (_) {
      // Crashlytics unavailable — proceed without crash reporting.
    }
  }

  // Best-effort restore of cached session (silent Google sign-in).
  // This prevents "login not staying" issues after app relaunch.
  try {
    await AuthService().tryRestoreSessionSilently();
  } catch (_) {
    // Failing to restore silently should not break app startup.
  }

  // Initialize local encrypted Hive database
  final dbService = DbService();
  await dbService.init();

  runApp(
    ProviderScope(
      overrides: [
        dbServiceProvider.overrideWithValue(dbService),
      ],
      child: KhataApp(dbService: dbService),
    ),
  );
}

class KhataApp extends StatefulWidget {
  final DbService dbService;
  const KhataApp({super.key, required this.dbService});

  @override
  State<KhataApp> createState() => _KhataAppState();
}

class _KhataAppState extends State<KhataApp> {
  late final AppLifecycleListener _listener;
  DateTime? _pausedTime;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onPause: () {
        _pausedTime = DateTime.now();
      },
      onResume: () {
        if (_pausedTime != null) {
          final difference = DateTime.now().difference(_pausedTime!);
          // If backgrounded for >= 1 minute, and onboarding is done, require lock
          if (difference.inMinutes >= 1 && widget.dbService.hasCompletedOnboarding) {
            _navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const AppLockScreen()),
            );
          }
          _pausedTime = null;
        }
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'SPBOOKS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005CEE),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: _AuthGate(dbService: widget.dbService),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Shows OnboardingScreen to signed-out users, AppLockScreen to signed-in users.
/// Checks the persisted `hasCompletedOnboarding` flag so that users who
/// skipped login or already signed in don't see onboarding on every cold start.
class _AuthGate extends StatelessWidget {
  final DbService dbService;
  const _AuthGate({required this.dbService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still loading Firebase auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF005CEE),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        final user = snapshot.data;

        // User is signed in via Firebase → proceed directly
        if (user != null) {
          return const AppLockScreen();
        }

        // Not signed in, but previously completed onboarding (e.g. skipped) → proceed
        if (dbService.hasCompletedOnboarding) {
          return const AppLockScreen();
        }

        // First time user → show onboarding
        return const OnboardingScreen();
      },
    );
  }
}
