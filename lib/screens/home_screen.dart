import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lock_state_provider.dart';
import '../services/reddit_usage_service.dart';
import '../services/usage_service.dart';
import '../services/app_log_service.dart';
import '../services/chrome_filter_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _redditService = RedditUsageService();
  final _usageService = UsageService();
  final _logService = AppLogService();
  final _chromeService = ChromeFilterService();

  Map<String, dynamic> _redditStatus = {};
  Map<String, dynamic> _screenTimeData = {};
  Map<String, int> _openCounts = {};
  List<Map<String, dynamic>> _appLogs = [];
  Map<String, dynamic> _chromeFilterStatus = {};
  bool _hasUsagePermission = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await context.read<LockStateProvider>().updateLockStatus();
    await Future.wait([
      _refreshRedditStatus(),
      _refreshScreenTime(),
      _refreshAppLogs(),
      _refreshChromeFilter(),
    ]);
  }

  Future<void> _refreshRedditStatus() async {
    final status = await _redditService.getUsageStatus();
    if (mounted) setState(() => _redditStatus = status);
  }

  Future<void> _refreshScreenTime() async {
    final hasPerm = await _usageService.hasUsageStatsPermission();
    if (hasPerm) {
      final data = await _usageService.getScreenTimeData();
      if (mounted) {
        setState(() {
          _hasUsagePermission = true;
          _screenTimeData = data;
        });
      }
    } else {
      if (mounted) setState(() => _hasUsagePermission = false);
    }
  }

  Future<void> _refreshAppLogs() async {
    final logs = await _logService.getTodayLogs();
    final counts = await _logService.getAllOpenCounts();
    if (mounted) {
      setState(() {
        _appLogs = logs;
        _openCounts = counts;
      });
    }
  }

  Future<void> _refreshChromeFilter() async {
    final status = await _chromeService.getFilterStatus();
    if (mounted) setState(() => _chromeFilterStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FocusLock'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield),
            tooltip: 'Protection Settings',
            onPressed: () {
              Navigator.pushNamed(context, '/uninstall_protection');
            },
          ),
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
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Card
                  _buildStatusCard(lockProvider),
                  const SizedBox(height: 20),

                  if (lockProvider.isLocked) ...[
                    _buildLockInfoCard(lockProvider),
                    const SizedBox(height: 20),
                    if (!lockProvider.emergencyUnlockRequested)
                      _buildEmergencyUnlockButton(lockProvider)
                    else
                      _buildEmergencyUnlockProgress(lockProvider),
                    const SizedBox(height: 20),
                  ],

                  // Screen Time Dashboard
                  _buildScreenTimeDashboard(),
                  const SizedBox(height: 20),

                  // App Open Counts
                  _buildAppOpenCountsCard(),
                  const SizedBox(height: 20),

                  // Reddit Usage
                  _buildRedditUsageCard(),
                  const SizedBox(height: 20),

                  // Chrome Filter Status
                  _buildChromeFilterCard(),
                  const SizedBox(height: 20),

                  // App Open Logs
                  _buildAppOpenLogsCard(),
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

  // ── Screen Time Dashboard ──────────────────────────────────────────

  Widget _buildScreenTimeDashboard() {
    if (!_hasUsagePermission) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.screen_lock_portrait, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Text(
                  'Screen Time Dashboard',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Usage access permission is required to display screen time data.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Grant Usage Access'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () async {
                  await _usageService.openUsageStatsSettings();
                },
              ),
            ),
          ],
        ),
      );
    }

    final apps = [
      {'pkg': 'com.instagram.android', 'name': 'Instagram', 'icon': Icons.camera_alt, 'color': Colors.pink},
      {'pkg': 'com.reddit.frontpage', 'name': 'Reddit', 'icon': Icons.forum, 'color': Colors.deepOrange},
      {'pkg': 'com.twitter.android', 'name': 'Twitter/X', 'icon': Icons.tag, 'color': Colors.blue},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.screen_lock_portrait, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Text(
                'Screen Time Today',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...apps.map((app) {
            final pkg = app['pkg'] as String;
            final name = app['name'] as String;
            final icon = app['icon'] as IconData;
            final color = app['color'] as MaterialColor;
            final appData = _screenTimeData[pkg];
            final screenTimeMs = (appData is Map ? appData['screenTimeMs'] : 0) as int? ?? 0;
            final formatted = UsageService.formatScreenTime(screenTimeMs);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color.shade700, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: screenTimeMs > 1800000
                          ? Colors.red.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      formatted,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: screenTimeMs > 1800000
                            ? Colors.red.shade700
                            : Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── App Open Counts ───────────────────────────────────────────────

  Widget _buildAppOpenCountsCard() {
    final apps = [
      {'pkg': 'com.instagram.android', 'name': 'Instagram', 'color': Colors.pink},
      {'pkg': 'com.reddit.frontpage', 'name': 'Reddit', 'color': Colors.deepOrange},
      {'pkg': 'com.twitter.android', 'name': 'Twitter/X', 'color': Colors.blue},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.touch_app, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              Text(
                'App Opens Today',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: apps.map((app) {
              final pkg = app['pkg'] as String;
              final name = app['name'] as String;
              final color = app['color'] as MaterialColor;
              final count = _openCounts[pkg] ?? 0;

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: color.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: color.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Chrome Filter Status ──────────────────────────────────────────

  Widget _buildChromeFilterCard() {
    final isActive = (_chromeFilterStatus['isActive'] ?? false) as bool;
    final isDeviceOwner = (_chromeFilterStatus['isDeviceOwner'] ?? false) as bool;

    String subtitle;
    if (isActive) {
      subtitle = 'Active — Incognito mode disabled by policy';
    } else if (!isDeviceOwner) {
      subtitle = 'Requires Device Owner setup';
    } else {
      subtitle = 'Inactive — Policy not applied';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.green.shade300 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive ? Colors.green.shade100 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.shield,
              color: isActive ? Colors.green.shade700 : Colors.grey.shade500,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chrome Incognito Policy',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? Colors.green.shade600 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? Colors.green.shade600 : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isActive ? 'ON' : 'OFF',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Open Logs ─────────────────────────────────────────────────

  Widget _buildAppOpenLogsCard() {
    final displayLogs = _appLogs.take(15).toList(); // Show last 15

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Text(
                'Recent App Opens',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Text(
                '${_appLogs.length} total',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (displayLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No app opens logged today.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            )
          else
            ...displayLogs.map((log) {
              final name = log['appName'] ?? '';
              final ts = log['timestamp'] ?? '';
              final timeOnly = ts.length > 10 ? ts.substring(11) : ts;
              Color dotColor;
              switch (name) {
                case 'Instagram':
                  dotColor = Colors.pink;
                  break;
                case 'Reddit':
                  dotColor = Colors.deepOrange;
                  break;
                case 'Twitter/X':
                  dotColor = Colors.blue;
                  break;
                default:
                  dotColor = Colors.grey;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      timeOnly,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── Existing cards (unchanged logic, kept) ────────────────────────

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
            lockProvider.isLocked ? 'Apps Locked' : 'Apps Unlocked',
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
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _buildEmergencyUnlockButton(LockStateProvider lockProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 10),
        const Text('Emergency Unlock',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        Text('Need access? Complete the emergency challenge:',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(height: 15),
        ElevatedButton(
          onPressed: () async {
            await lockProvider.requestEmergencyUnlock();
            if (mounted) Navigator.of(context).pushNamed('/emergency');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: const Text('Start Emergency Unlock',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              const Text('Emergency Unlock In Progress',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () async => await lockProvider.cancelEmergencyUnlock(),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildProgressSection(
              'Waiting Period', lockProvider.remainingDelay, '1 hour delay'),
          const SizedBox(height: 15),
          _buildProgressSection(
              'Step Challenge',
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
        Text(subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
          color: isLimitReached
              ? Colors.deepOrange.shade200
              : Colors.indigo.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isLimitReached ? Icons.block : Icons.timer,
                  color: isLimitReached
                      ? Colors.deepOrange.shade700
                      : Colors.indigo.shade700),
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
              Text('Used: ${RedditUsageService.formatDuration(usedSec)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              Text(
                'Remaining: ${RedditUsageService.formatDuration(remainSec)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color:
                      isLimitReached ? Colors.deepOrange : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          if (extraMin > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${extraMin}min earned from pushups today',
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
                  _refreshRedditStatus();
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
          const Text('How It Works',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text(
            '• Instagram, Reddit & Twitter/X are blocked when launched\n'
            '• Lock expires after 30 days\n'
            '• Reddit offers a pushup challenge for 10-min access\n'
            '• Chrome filters harmful content in incognito mode\n'
            '• Do 100 pushups to earn 10 minutes of Reddit\n'
            '• Emergency unlock requires physical effort',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
