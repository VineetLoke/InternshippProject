import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'features/incognito_blocker/controller/quotes_loader.dart';
import 'providers/lock_state_provider.dart';
import 'services/notification/notification_service.dart';
import 'services/notification/unlock_timer_manager.dart';
import 'screens/splash_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/emergency_unlock_screen.dart';
import 'screens/pushup_challenge_screen.dart';
import 'screens/uninstall_protection_screen.dart';

/// FocusGuard — Productivity app that replaces distractions with wisdom.
///
/// Test scenario:
/// 1. Launch app → splash screen → permissions screen
/// 2. Grant overlay + accessibility permissions → setup password
/// 3. Home screen shows lock status, app open counts, screen time
/// 4. Open Instagram → quote overlay blocks it
/// 5. Open Chrome incognito → quote overlay blocks it
/// 6. Do 100 pushups → unlocks temporary access (10 min)
/// 7. Open Twitter/X or Reddit → blocked with quote overlay
/// 8. Notification countdown shows during unlock
/// 9. After 10 min, blocking resumes automatically
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-load the quote bank so the first overlay is instant.
  await QuotesLoader.instance.load();

  // Initialize notification service and start unlock timer monitoring.
  await NotificationService.instance.initialize();
  UnlockTimerManager.instance.startMonitoring();

  // Catch Flutter framework errors (widget build / layout errors).
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  // Catch all async errors that escape the widget tree entirely
  // (plugin init, dart:io failures, etc.).
  runZonedGuarded(
    () => runApp(const FocusGuardApp()),
    (error, stack) {
      debugPrint('Unhandled async error: $error\n$stack');
    },
  );
}

class FocusGuardApp extends StatelessWidget {
  const FocusGuardApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LockStateProvider()),
      ],
      child: MaterialApp(
        title: 'FocusGuard',
        theme: AppTheme.darkTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/permissions': (context) => const PermissionsScreen(),
          '/setup': (context) => const SetupScreen(),
          '/home': (context) => const HomeScreen(),
          '/lock': (context) => const LockScreen(),
          '/emergency': (context) => const EmergencyUnlockScreen(),
          '/pushup_challenge': (context) => const PushupChallengeScreen(),
          '/uninstall_protection': (context) =>
              const UninstallProtectionScreen(),
        },
      ),
    );
  }
}
