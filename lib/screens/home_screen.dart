import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lock_state_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _refreshLockStatus();
  }

  Future<void> _refreshLockStatus() async {
    await context.read<LockStateProvider>().updateLockStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FocusLock'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLockStatus,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshLockStatus,
        child: Consumer<LockStateProvider>(
          builder: (context, lockProvider, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Card
                  _buildStatusCard(lockProvider),
                  const SizedBox(height: 20),

                  if (lockProvider.isLocked) ...[
                    // Lock Info
                    _buildLockInfoCard(lockProvider),
                    const SizedBox(height: 20),

                    // Emergency Unlock Section
                    if (!lockProvider.emergencyUnlockRequested)
                      _buildEmergencyUnlockButton(lockProvider)
                    else
                      _buildEmergencyUnlockProgress(lockProvider),

                    const SizedBox(height: 20),
                  ],

                  // Info Section
                  _buildInfoCard(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusCard(LockStateProvider lockProvider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: lockProvider.isLocked ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: lockProvider.isLocked ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            lockProvider.isLocked ? Icons.lock : Icons.lock_open,
            size: 50,
            color: lockProvider.isLocked ? Colors.red.shade700 : Colors.green.shade700,
          ),
          const SizedBox(height: 10),
          Text(
            lockProvider.isLocked ? 'Instagram is Locked' : 'Instagram is Unlocked',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: lockProvider.isLocked ? Colors.red.shade700 : Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 5),
          if (lockProvider.isLocked)
            Text(
              'Focus period: ${lockProvider.remainingDays} days remaining',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLockInfoCard(LockStateProvider lockProvider) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildLockInfoRow('Locked Until:', 
            lockProvider.lockEndDate?.toString().split('.').first ?? 'N/A'),
          const SizedBox(height: 10),
          _buildLockInfoRow('Days Remaining:', 
            '${lockProvider.remainingDays} days'),
        ],
      ),
    );
  }

  Widget _buildLockInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildEmergencyUnlockButton(LockStateProvider lockProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 10),
        const Text(
          'Emergency Unlock',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Text(
          'Need access? Complete the emergency challenge:',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 15),
        ElevatedButton(
          onPressed: () async {
            await lockProvider.requestEmergencyUnlock();
            if (mounted) {
              Navigator.of(context).pushNamed('/emergency');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: const Text(
            'Start Emergency Unlock',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyUnlockProgress(LockStateProvider lockProvider) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Emergency Unlock In Progress',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () async {
                  await lockProvider.cancelEmergencyUnlock();
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildProgressSection('Waiting Period', 
            lockProvider.remainingDelay, 
            '1 hour delay'),
          const SizedBox(height: 15),
          _buildProgressSection('Step Challenge', 
            Duration(seconds: (lockProvider.currentSteps / 10000 * 3600).toInt()), 
            '${lockProvider.currentSteps}/10000 steps'),
        ],
      ),
    );
  }

  Widget _buildProgressSection(String title, Duration duration, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              duration.inSeconds > 0 
                ? '${duration.inHours}h ${duration.inMinutes % 60}m remaining'
                : 'Complete',
              style: TextStyle(
                color: duration.inSeconds > 0 ? Colors.orange : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How It Works',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            '• Instagram is automatically blocked when launched\n'
            '• Lock expires after 30 days\n'
            '• Your password is securely encrypted\n'
            '• Emergency unlock requires physical effort',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
