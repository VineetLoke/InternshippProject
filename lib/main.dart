import 'package:flutter/material.dart';
import 'core/services/permission_service.dart';
import 'core/services/platform_channel_service.dart';
import 'features/challenges/screens/pushup_challenge_screen.dart';
import 'features/dashboard/screens/home_screen.dart';
import 'features/setup/screens/permissions_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FocusLockApp());
}

class FocusLockApp extends StatefulWidget {
  const FocusLockApp({super.key});

  @override
  State<FocusLockApp> createState() => _FocusLockAppState();
}

class _FocusLockAppState extends State<FocusLockApp> {
  @override
  void initState() {
    super.initState();
    _setupPlatformChannelListener();
  }

  void _setupPlatformChannelListener() {
    PlatformChannelService.instance.setupMethodCallHandler((call) async {
      if (call.method == "navigateToPushupChallenge") {
        navigatorKey.currentState?.pushNamed('/pushup-challenge');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FocusLock',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xff0a0a1a),
        primaryColor: const Color(0xff6c63ff),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xff6c63ff),
          secondary: Color(0xff00d4aa),
          surface: Color(0xff16213e),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xff0a0a1a),
          elevation: 0,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const InitialCheckScreen(),
        '/permissions': (context) => const PermissionsScreen(),
        '/home': (context) => const HomeScreen(),
        '/pushup-challenge': (context) => const PushupChallengeScreen(),
      },
    );
  }
}

class InitialCheckScreen extends StatefulWidget {
  const InitialCheckScreen({super.key});

  @override
  State<InitialCheckScreen> createState() => _InitialCheckScreenState();
}

class _InitialCheckScreenState extends State<InitialCheckScreen> {
  @override
  void initState() {
    super.initState();
    _performCheck();
  }

  Future<void> _performCheck() async {
    // Wait a brief moment for smooth transition
    await Future.delayed(const Duration(milliseconds: 800));
    final allGranted = await PermissionService.instance.areAllPermissionsGranted();
    if (mounted) {
      if (allGranted) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/permissions');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, size: 72, color: Color(0xff6c63ff)),
            SizedBox(height: 24),
            Text(
              "FocusLock",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 16),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xff6c63ff)),
            )
          ],
        ),
      ),
    );
  }
}
