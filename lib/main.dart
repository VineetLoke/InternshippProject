import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/platform_channel_service.dart';
import 'core/services/permission_service.dart';
import 'features/setup/screens/permissions_screen.dart';
import 'features/dashboard/screens/home_screen.dart';
import 'features/challenges/screens/pushup_challenge_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FocusLockApp());
}

class FocusLockApp extends StatelessWidget {
  const FocusLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PlatformChannelService>(
          create: (_) => PlatformChannelService(),
        ),
        ProxyProvider<PlatformChannelService, PermissionService>(
          update: (_, platformService, __) =>
              PermissionService(platformService),
        ),
      ],
      child: MaterialApp(
        title: 'FocusLock',
        debugShowCheckedModeBanner: false,
        theme: _buildDarkTheme(),
        home: const _AppRouter(),
        routes: {
          '/permissions': (context) => const PermissionsScreen(),
          '/home': (context) => const HomeScreen(),
          '/pushup-challenge': (context) => const PushupChallengeScreen(),
        },
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const primaryColor = Color(0xFF7C4DFF);
    const backgroundColor = Color(0xFF0D0D1A);
    const surfaceColor = Color(0xFF1A1A2E);
    const cardColor = Color(0xFF16213E);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: Color(0xFF536DFE),
        surface: surfaceColor,
        error: Color(0xFFCF6679),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        onError: Colors.black,
      ),
      cardColor: cardColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Color(0xFFB0B0C0),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Color(0xFF8888A0),
        ),
      ),
    );
  }
}

/// Router widget that checks permissions on launch and directs
/// to the appropriate screen. Also handles deep links.
class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  bool _loading = true;
  String _initialRoute = '/home';

  @override
  void initState() {
    super.initState();
    _determineInitialRoute();
  }

  Future<void> _determineInitialRoute() async {
    final platformService =
        Provider.of<PlatformChannelService>(context, listen: false);
    final permissionService =
        Provider.of<PermissionService>(context, listen: false);

    // Check if opened via deep link
    final deepLinkRoute = await platformService.getInitialRoute();
    if (deepLinkRoute == '/pushup-challenge') {
      setState(() {
        _initialRoute = '/pushup-challenge';
        _loading = false;
      });
      return;
    }

    // Check if all permissions are granted
    final allGranted = await permissionService.areAllPermissionsGranted();
    setState(() {
      _initialRoute = allGranted ? '/home' : '/permissions';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF7C4DFF),
          ),
        ),
      );
    }

    switch (_initialRoute) {
      case '/permissions':
        return const PermissionsScreen();
      case '/pushup-challenge':
        return const PushupChallengeScreen();
      case '/home':
      default:
        return const HomeScreen();
    }
  }
}
