import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:focus_lock/features/app_blocker/presentation/providers/lock_state_provider.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late PageController _pageController;
  bool _hasNavigated = false;
  double _buttonScale = 1.0;

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
                if (!mounted) return;
                Navigator.of(context).pushReplacementNamed('/home');
              });
            }

            const goldColor = Color(0xFFC6A85A);
            const mutedGold = Color(0xFF8A7A6C);

            return Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0xFF1B1812), Color(0xFF060608)],
                  center: Alignment.center,
                  radius: 1.4,
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const Spacer(),
                    
                    // Top Icon Indicator
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: goldColor.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: goldColor.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        size: 36,
                        color: goldColor,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Main Headers
                    const Text(
                      'FOCUS MODE ACTIVE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFC6A85A),
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Impulsive apps are currently locked down.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF0E6D2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Instagram, Reddit, & Twitter/X are inaccessible.',
                      style: TextStyle(
                        fontSize: 12,
                        color: mutedGold,
                      ),
                    ),
                    
                    const Spacer(),

                    // Circular Countdown Tracker
                    _buildCircularCountdown(lockProvider),

                    const Spacer(),

                    // Action buttons
                    if (!lockProvider.emergencyUnlockRequested)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: GestureDetector(
                          onTapDown: (_) => setState(() => _buttonScale = 0.94),
                          onTapUp: (_) => setState(() => _buttonScale = 1.0),
                          onTapCancel: () => setState(() => _buttonScale = 1.0),
                          onTap: () async {
                            await lockProvider.requestEmergencyUnlock();
                            if (!mounted) return;
                            Navigator.of(context).pushNamed('/emergency');
                          },
                          child: AnimatedScale(
                            scale: _buttonScale,
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOutBack,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              decoration: BoxDecoration(
                                color: goldColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: goldColor.withValues(alpha: 0.25),
                                    blurRadius: 15,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shield_outlined, color: Color(0xFF0F0E0B), size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'EMERGENCY UNLOCK',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F0E0B),
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCircularCountdown(LockStateProvider lockProvider) {
    const goldColor = Color(0xFFC6A85A);
    const mutedGold = Color(0xFF8A7A6C);
    
    // Normal progress visual representation out of 30 days maximum
    final double progress = (lockProvider.remainingDays.clamp(0, 30)) / 30.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: goldColor.withValues(alpha: 0.03),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        
        // Progress Track
        SizedBox(
          width: 200,
          height: 200,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.02),
            valueColor: const AlwaysStoppedAnimation<Color>(goldColor),
          ),
        ),
        
        // Timer Text Box
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${lockProvider.remainingDays}',
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: Color(0xFFF0E6D2),
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'DAYS REMAINING',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: mutedGold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Text(
                'Ends: ${lockProvider.lockEndDate?.toString().split(' ').first ?? 'N/A'}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFF0E6D2),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
