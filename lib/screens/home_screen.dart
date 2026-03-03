import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lock_state_provider.dart';
import '../services/reddit_usage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _redditService = RedditUsageService();
  Map<String, dynamic> _redditStatus = {};

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await context.read<LockStateProvider>().updateLockStatus();
    await _refreshRedditStatus();
  }

  Future<void> _refreshRedditStatus() async {
    final status = await _redditService.getUsageStatus();
    if (mounted) setState(() => _redditStatus = status);
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
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
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
                  _buildRedditUsageCard(),
                  const SizedBox(height: 20),
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

  Widget _buildRedditUsageCard() {
    final usedSec = (_redditStatus['usedSeconds'] ?? 0) as int;
    final limitSec = (_redditStatus['limitSeconds'] ?? 3600) as int;
    final remainSec = (_redditStatus['remainingSeconds'] ?? 3600) as int;
    final isLimitReached = (_redditStatus['isLimitReached'] ?? false) as bool;
    final extraMin = (_redditStatus['extraMinutesEarned'] ?? 0) as int;
    final progress = limitSec > 0 ? (usedSec / limitSec).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLimitReached ? Colors.deepOrange.shade50 : Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLimitReached ? Colors.deepOrange.shade200 : Colors.indigo.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLimitReached ? Icons.block : Icons.timer,
                color: isLimitReached
                    ? Colors.deepOrange.shade700
                    : Colors.indigo.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                'Reddit Daily Limit',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isLimitReached
                      ? Colors.deepOrange.shade700
                      : Colors.indigo.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isLimitReached ? Colors.deepOrange : Colors.indigo.shade400,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Used: ${RedditUsageService.formatDuration(usedSec)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(
                'Remaining: ${RedditUsageService.formatDuration(remainSec)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isLimitReached ? Colors.deepOrange : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          if (extraMin > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '💪 +${extraMin}min earned from pushups today',
                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
              ),
            ),
          if (isLimitReached) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.fitness_center, size: 20),
                label: const Text('Do 100 Pushups for +10min'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () async {
                  await Navigator.of(context).pushNamed('/pushup_challenge');
                  _refreshRedditStatus(); // refresh after returning
                },
              ),
            ),
          ],
        ],
      ),
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
            '• Reddit has a 1-hour daily limit\n'
            '• Do 100 pushups to earn 10 extra minutes\n'
            '• Your password is securely encrypted\n'
            '• Emergency unlock requires physical effort',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
