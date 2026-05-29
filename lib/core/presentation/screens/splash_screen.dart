import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:focus_lock/features/app_blocker/presentation/providers/lock_state_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

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

    // Check if the splash screen is the active (topmost) route.
    // If we launched directly into a challenge, wait until it is popped
    // and we become the topmost route before navigating to Home/Permissions.
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrent) {
      Timer.periodic(const Duration(milliseconds: 200), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          timer.cancel();
          _navigate();
        }
      });
      return;
    }

    final lockProvider = context.read<LockStateProvider>();
    if (lockProvider.passwordSet) {
      // Setup complete — always show the main dashboard.
      // The home screen handles locked vs unlocked state internally.
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
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'FocusLock',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Stay focused on what matters',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.secondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 40),
            CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
