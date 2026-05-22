import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/emergency_unlock_screen.dart';
import 'screens/pushup_challenge_screen.dart';
import 'screens/instagram_pushup_challenge_screen.dart';
import 'screens/app_pushup_challenge_screen.dart';
import 'screens/uninstall_protection_screen.dart';
import 'providers/lock_state_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  runZonedGuarded(
    () => runApp(const FocusLockApp()),
    (error, stack) {
      debugPrint('Unhandled async error: $error\n$stack');
    },
  );
}

class FocusLockApp extends StatelessWidget {
  const FocusLockApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF225C4D),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF225C4D),
      secondary: const Color(0xFFB87432),
      surface: const Color(0xFFFFFCF6),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LockStateProvider()),
      ],
      child: MaterialApp(
        title: 'FocusLock',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: colorScheme,
          scaffoldBackgroundColor: const Color(0xFFF5F1E8),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor: Color(0xFF17352E),
            elevation: 0,
            centerTitle: false,
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: colorScheme.primary,
            contentTextStyle: const TextStyle(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              side: BorderSide(color: colorScheme.primary.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
            ),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/permissions': (context) => const PermissionsScreen(),
          '/setup': (context) => const SetupScreen(),
          '/home': (context) => const HomeScreen(),
          '/lock': (context) => const LockScreen(),
          '/emergency': (context) => const EmergencyUnlockScreen(),
          '/pushup_challenge': (context) => const PushupChallengeScreen(),
          '/instagram_pushup_challenge': (context) =>
              const InstagramPushupChallengeScreen(),
          '/app_pushup_challenge': (context) =>
              const AppPushupChallengeScreen(),
          '/uninstall_protection': (context) =>
              const UninstallProtectionScreen(),
        },
      ),
    );
  }
}