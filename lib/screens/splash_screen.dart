import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lock_state_provider.dart';
import '../services/permission_service.dart';
import 'setup_screen.dart';
import 'home_screen.dart';
import 'lock_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Request essential permissions early — before using any platform features.
    // This prevents crashes from accessing sensors/notifications without them.
    try {
      final permService = PermissionService();
      await permService.requestNotificationPermission();
      await permService.requestActivityRecognition();
    } catch (e) {
      debugPrint('Permission request error (non-fatal): $e');
    }

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final lockProvider = context.read<LockStateProvider>();
    // updateLockStatus now also reloads the persisted passwordSet flag.
    await lockProvider.updateLockStatus();

    if (!mounted) return;

    // Navigate based on state
    if (lockProvider.isLocked) {
      Navigator.of(context).pushReplacementNamed('/lock');
    } else if (lockProvider.passwordSet) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      // New user — must grant permissions before setup
      Navigator.of(context).pushReplacementNamed('/permissions');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.blue.shade700,
            ),
            const SizedBox(height: 20),
            Text(
              'FocusLock',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Stay focused on what matters',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 40),
            CircularProgressIndicator(color: Colors.blue.shade700),
          ],
        ),
      ),
    );
  }
}
