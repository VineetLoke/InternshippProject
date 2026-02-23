import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/emergency_unlock_screen.dart';
import 'providers/lock_state_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter framework errors (widget build / layout errors).
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  // Catch all async errors that escape the widget tree entirely
  // (plugin init, dart:io failures, etc.).
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LockStateProvider()),
      ],
      child: MaterialApp(
        title: 'FocusLock',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/setup': (context) => const SetupScreen(),
          '/home': (context) => const HomeScreen(),
          '/lock': (context) => const LockScreen(),
          '/emergency': (context) => const EmergencyUnlockScreen(),
        },
      ),
    );
  }
}
