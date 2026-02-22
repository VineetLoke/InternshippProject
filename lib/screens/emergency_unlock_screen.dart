import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lock_state_provider.dart';
import '../services/timer_service.dart';

class EmergencyUnlockScreen extends StatefulWidget {
  const EmergencyUnlockScreen({Key? key}) : super(key: key);

  @override
  State<EmergencyUnlockScreen> createState() => _EmergencyUnlockScreenState();
}

class _EmergencyUnlockScreenState extends State<EmergencyUnlockScreen> {
  @override
  void initState() {
    super.initState();
    _checkCompletion();
  }

  Future<void> _checkCompletion() async {
    // Periodically check if challenge is complete
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      final lockProvider = context.read<LockStateProvider>();
      await lockProvider.checkStepChallenge();
      
      // If both conditions met, show password
      if (lockProvider.stepChallengeComplete && 
          lockProvider.remainingDelay.inSeconds == 0) {
        _showPasswordDialog(lockProvider);
      } else {
        _checkCompletion();
      }
    }
  }

  void _showPasswordDialog(LockStateProvider lockProvider) async {
    final password = await lockProvider.getPasswordAfterChallenge();
    
    if (mounted && password != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Password Revealed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your password is:'),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  password,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
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
              child: const Text('Unlock Instagram'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Emergency Unlock Challenge'),
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: Consumer<LockStateProvider>(
          builder: (context, lockProvider, _) {
            final delayComplete = lockProvider.remainingDelay.inSeconds == 0;
            final stepsComplete = lockProvider.stepChallengeComplete;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Complete Both Challenges to Unlock',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Challenge 1: Waiting Period
                  _buildChallengeCard(
                    title: 'Anti-Impulse Delay',
                    icon: Icons.schedule,
                    isComplete: delayComplete,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Wait 1 hour before unlocking. This prevents impulsive decisions.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 15),
                        if (!delayComplete)
                          _buildTimerDisplay(lockProvider.remainingDelay)
                        else
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Waiting period complete!',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Challenge 2: Step Challenge
                  _buildChallengeCard(
                    title: 'Physical Challenge',
                    icon: Icons.directions_walk,
                    isComplete: stepsComplete,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Complete 10,000 steps in one day to prove your commitment.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 15),
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
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
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${(lockProvider.getStepProgress() * 100).toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: lockProvider.getStepProgress(),
                                  minHeight: 8,
                                  backgroundColor: Colors.grey.shade300,
                                  valueColor: AlwaysStoppedAnimation(
                                    stepsComplete
                                        ? Colors.green
                                        : Colors.blue.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (stepsComplete)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Steps challenge complete!',
                                      style: TextStyle(
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  '${lockProvider.getRemainingSteps()} steps remaining',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Status
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: (delayComplete && stepsComplete)
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (delayComplete && stepsComplete)
                            ? Colors.green.shade200
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (delayComplete && stepsComplete)
                              ? Icons.check_circle
                              : Icons.info,
                          size: 24,
                          color: (delayComplete && stepsComplete)
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            (delayComplete && stepsComplete)
                                ? 'Both challenges complete! Your password will be revealed.'
                                : delayComplete
                                    ? 'Waiting period complete. Keep walking to reach your step goal!'
                                    : stepsComplete
                                        ? 'Steps goal reached! Wait for the 1-hour delay to complete.'
                                        : 'Complete both challenges to unlock your password.',
                            style: TextStyle(
                              fontSize: 13,
                              color: (delayComplete && stepsComplete)
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Cancel button
                  OutlinedButton(
                    onPressed: () async {
                      await context.read<LockStateProvider>().cancelEmergencyUnlock();
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel Emergency Unlock'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChallengeCard({
    required String title,
    required IconData icon,
    required bool isComplete,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isComplete ? Colors.green.shade50 : Colors.white,
        border: Border.all(
          color: isComplete ? Colors.green.shade300 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: isComplete ? Colors.green : Colors.grey),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isComplete ? Colors.green.shade700 : Colors.black,
                ),
              ),
              const Spacer(),
              if (isComplete)
                Icon(
                  Icons.check_circle,
                  color: Colors.green.shade700,
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTimerDisplay(Duration remaining) {
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, color: Colors.orange.shade700),
          const SizedBox(width: 15),
          Text(
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
