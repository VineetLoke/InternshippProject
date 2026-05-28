import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:focus_lock/features/app_blocker/presentation/providers/lock_state_provider.dart';
import 'package:focus_lock/features/app_blocker/services/timer_service.dart';

class EmergencyUnlockScreen extends StatefulWidget {
  const EmergencyUnlockScreen({Key? key}) : super(key: key);

  @override
  State<EmergencyUnlockScreen> createState() => _EmergencyUnlockScreenState();
}

class _EmergencyUnlockScreenState extends State<EmergencyUnlockScreen> {
  Timer? _poller;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshProgress();
    });
    _refreshProgress();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refreshProgress() async {
    if (!mounted) return;
    final lockProvider = context.read<LockStateProvider>();
    await lockProvider.checkStepChallenge();

    if (!_dialogShown &&
        lockProvider.stepChallengeComplete &&
        lockProvider.remainingDelay.inSeconds == 0) {
      _dialogShown = true;
      await _showPasswordDialog(lockProvider);
    }
  }

  Future<void> _showPasswordDialog(LockStateProvider lockProvider) async {
    final password = await lockProvider.getPasswordAfterChallenge();
    if (!mounted || password == null) {
      _dialogShown = false;
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Unlock Code Ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Both safeguards are complete. Your password is now available.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
              ),
              child: Text(
                password,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await lockProvider.unlockApp();
              if (mounted) {
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacementNamed('/home');
              }
            },
            child: const Text('Finish Unlock'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Emergency Unlock'),
          automaticallyImplyLeading: false,
        ),
        body: DecoratedBox(
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
          child: Consumer<LockStateProvider>(
            builder: (context, lockProvider, _) {
              final delayComplete = lockProvider.remainingDelay.inSeconds == 0;
              final stepsComplete = lockProvider.stepChallengeComplete;
              final ready = delayComplete && stepsComplete;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroCard(ready),
                    const SizedBox(height: 20),
                    _buildChallengeCard(
                      title: 'Impulse Delay',
                      subtitle: 'A full hour must pass before reveal is allowed.',
                      icon: Icons.hourglass_bottom_rounded,
                      accent: const Color(0xFFC87032),
                      isComplete: delayComplete,
                      child: delayComplete
                          ? _buildCompleteBanner('Delay complete. Time barrier cleared.')
                          : _buildTimerDisplay(lockProvider.remainingDelay),
                    ),
                    const SizedBox(height: 16),
                    _buildChallengeCard(
                      title: 'Movement Requirement',
                      subtitle: 'Walk 10,000 steps in a single day to prove intent.',
                      icon: Icons.directions_walk_rounded,
                      accent: const Color(0xFF2E7D63),
                      isComplete: stepsComplete,
                      child: _buildStepsPanel(lockProvider, stepsComplete),
                    ),
                    const SizedBox(height: 16),
                    _buildStatusStrip(lockProvider, ready, delayComplete, stepsComplete),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () async {
                        await context.read<LockStateProvider>().cancelEmergencyUnlock();
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('Cancel Emergency Unlock'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Live countdown: ${TimerService.formatDuration(lockProvider.remainingDelay)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(bool ready) {
    final successColor = const Color(0xFF2E7D63);
    final warningColor = const Color(0xFFC6A85A);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: ready
              ? [successColor, const Color(0xFF389A7B)]
              : [const Color(0xFF16161A), const Color(0xFF222228)],
        ),
        border: Border.all(
          color: ready ? successColor.withOpacity(0.5) : warningColor.withOpacity(0.3),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              ready ? Icons.verified_user_rounded : Icons.lock_clock_rounded,
              color: ready ? Colors.white : warningColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ready ? 'Unlock Ready' : 'Controlled Release',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ready
                ? 'Your password can now be revealed safely.'
                : 'Both safeguards must complete before the password is shown.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.86),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required bool isComplete,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isComplete ? accent.withOpacity(0.4) : const Color(0xFF222228),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isComplete)
                Icon(Icons.check_circle_rounded, color: accent, size: 28),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildStepsPanel(LockStateProvider lockProvider, bool stepsComplete) {
    final colorScheme = Theme.of(context).colorScheme;
    final successColor = const Color(0xFF2E7D63);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF222228)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${lockProvider.currentSteps}/10000 steps',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${(lockProvider.getStepProgress() * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: lockProvider.getStepProgress(),
              minHeight: 10,
              backgroundColor: const Color(0xFF222228),
              valueColor: AlwaysStoppedAnimation<Color>(
                stepsComplete ? successColor : colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            stepsComplete
                ? 'Step challenge complete. Physical requirement satisfied.'
                : '${lockProvider.getRemainingSteps()} steps remaining today.',
            style: TextStyle(
              fontSize: 13,
              color: stepsComplete ? successColor : colorScheme.secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStrip(
    LockStateProvider lockProvider,
    bool ready,
    bool delayComplete,
    bool stepsComplete,
  ) {
    String text;
    Color color;
    final successColor = const Color(0xFF2E7D63);
    final warningColor = const Color(0xFFC87032);
    final goldColor = Theme.of(context).colorScheme.primary;

    if (ready) {
      text = 'All safeguards complete. The password dialog will stay available until you finish the unlock.';
      color = successColor;
    } else if (delayComplete) {
      text = 'Time barrier cleared. Keep walking until the movement target is complete.';
      color = warningColor;
    } else if (stepsComplete) {
      text = 'Movement target reached. Wait for the delay to expire to finish the unlock.';
      color = successColor;
    } else {
      text = 'Both the delay and the movement requirement must complete before reveal is allowed.';
      color = goldColor;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteBanner(String text) {
    final successColor = const Color(0xFF2E7D63);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: successColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: successColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: successColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: successColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerDisplay(Duration remaining) {
    final colorScheme = Theme.of(context).colorScheme;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;
    final warningColor = const Color(0xFFC87032);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: warningColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: warningColor,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This cooldown is deliberate. It blocks impulse unlocks.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.secondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
