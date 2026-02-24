import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lock_state_provider.dart';

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
    // Hard cap: splash MUST navigate within 3 seconds no matter what.
    // Heavy work (permissions, secure storage) is done on destination screens.
    await Future.any([
      _tryLoadState(),
      Future.delayed(const Duration(seconds: 3)),
    ]);

    if (!mounted) return;
    _navigate();
  }

  Future<void> _tryLoadState() async {
    // Minimum visual delay so the splash screen does not flash.
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    try {
      await context
          .read<LockStateProvider>()
          .updateLockStatus()
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      // Timeout or error — navigate anyway using safe default state.
      debugPrint('Splash init error (non-fatal): $e');
    }
  }

  void _navigate() {
    if (!mounted) return;
    final lockProvider = context.read<LockStateProvider>();
    if (lockProvider.isLocked) {
      Navigator.of(context).pushReplacementNamed('/lock');
    } else if (lockProvider.passwordSet) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
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
