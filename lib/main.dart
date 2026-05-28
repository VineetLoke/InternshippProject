import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:focus_lock/core/presentation/screens/splash_screen.dart';
import 'package:focus_lock/core/presentation/screens/permissions_screen.dart';
import 'package:focus_lock/core/presentation/screens/setup_screen.dart';
import 'package:focus_lock/features/dashboard/presentation/screens/home_screen.dart';
import 'package:focus_lock/features/app_blocker/presentation/screens/lock_screen.dart';
import 'package:focus_lock/features/app_blocker/presentation/screens/emergency_unlock_screen.dart';
import 'package:focus_lock/features/challenges/presentation/screens/pushup_challenge_screen.dart';
import 'package:focus_lock/features/challenges/presentation/screens/instagram_pushup_challenge_screen.dart';
import 'package:focus_lock/features/challenges/presentation/screens/app_pushup_challenge_screen.dart';
import 'package:focus_lock/features/uninstall_protection/presentation/screens/uninstall_protection_screen.dart';
import 'package:focus_lock/features/app_blocker/presentation/providers/lock_state_provider.dart';

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
    const colorScheme = ColorScheme.dark(
      primary: Color(0xFFC6A85A), // Antique Gold
      secondary: Color(0xFF8A7A6C), // Iron/Stone Grey
      surface: Color(0xFF16161A), // Charcoal Stone
      error: Color(0xFFB54534), // Ember Crimson Red
      onPrimary: Color(0xFF151208),
      onSecondary: Color(0xFFF0E6D2),
      onSurface: Color(0xFFF0E6D2), // Parchment Cream
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
          brightness: Brightness.dark,
          colorScheme: colorScheme,
          scaffoldBackgroundColor: const Color(0xFF0A0A0C),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor: Color(0xFFC6A85A),
            elevation: 0,
            centerTitle: true,
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: colorScheme.surface,
            contentTextStyle: const TextStyle(color: Color(0xFFF0E6D2)),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
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
              side: BorderSide(color: colorScheme.primary.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF222228)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF222228)),
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