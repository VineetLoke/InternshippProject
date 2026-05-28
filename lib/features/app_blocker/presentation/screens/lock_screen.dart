import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:focus_lock/features/app_blocker/presentation/providers/lock_state_provider.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({Key? key}) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late PageController _pageController;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _refreshStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    await context.read<LockStateProvider>().updateLockStatus();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Consumer<LockStateProvider>(
          builder: (context, lockProvider, _) {
            // Check if still locked
            if (!lockProvider.isLocked && !_hasNavigated) {
              // Auto-navigate to home if unlocked (one-shot guard)
              _hasNavigated = true;
              Future.microtask(() {
                Navigator.of(context).pushReplacementNamed('/home');
              });
            }

            final colorScheme = Theme.of(context).colorScheme;

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.surface,
                    colorScheme.surface,
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Lock Icon
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 30),

                  // Message
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        Text(
                          'Apps Locked',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                            letterSpacing: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 15),
                        Text(
                          'Instagram, Reddit & Twitter/X are locked for your focus period.',
                          style: TextStyle(
                            fontSize: 16,
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        _buildCountdownTimer(lockProvider),
                      ],
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Emergency Unlock Button
                  if (!lockProvider.emergencyUnlockRequested)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ElevatedButton(
                        onPressed: () async {
                          await lockProvider.requestEmergencyUnlock();
                          if (mounted) {
                            Navigator.of(context).pushNamed('/emergency');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 15,
                          ),
                        ),
                        child: const Text(
                          'Emergency Unlock',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCountdownTimer(LockStateProvider lockProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withOpacity(0.3), width: 1.2),
      ),
      child: Column(
        children: [
          Text(
            'Unlock Date',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.secondary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            lockProvider.lockEndDate?.toString().split(' ').first ?? 'N/A',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${lockProvider.remainingDays} days remaining',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
