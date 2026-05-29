import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:focus_lock/features/app_blocker/presentation/providers/lock_state_provider.dart';
import 'package:focus_lock/features/dashboard/services/reddit_usage_service.dart';
import 'package:focus_lock/features/dashboard/services/usage_service.dart';
import 'package:focus_lock/features/dashboard/services/app_log_service.dart';
import 'package:focus_lock/features/chrome_filter/services/chrome_filter_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
    const goldColor = Color(0xFFC6A85A);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FOCUSLOCK',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 2.0,
            color: Color(0xFFC6A85A),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined, size: 22),
            color: goldColor,
            tooltip: 'Uninstall Protection',
            onPressed: () {
              Navigator.pushNamed(context, '/uninstall_protection');
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            color: goldColor,
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF14130E), Color(0xFF0A0A0C)],
            center: Alignment.topCenter,
            radius: 1.5,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          color: goldColor,
          backgroundColor: const Color(0xFF131316),
          child: Consumer<LockStateProvider>(
            builder: (context, lockProvider, _) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status Header Card
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

                    // App Open Counts Grid
                    _buildAppOpenCountsCard(),
                    const SizedBox(height: 20),

                    // Reddit Usage Controller
                    _buildRedditUsageCard(),
                    const SizedBox(height: 20),

                    // Chrome Policy Badge Card
                    _buildChromeFilterCard(),
                    const SizedBox(height: 20),

                    // Recent App Open Daemon Logs
                    _buildAppOpenLogsCard(),
                    const SizedBox(height: 20),

                    // Instructional info card
                    _buildInfoCard(),
                    const SizedBox(height: 30),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Glassmorphic Card Wrapper ───────────────────────────────────────
  Widget _buildGlassCard({
    required Widget child,
    Color? borderColor,
    double? borderWidth,
    Color? glowColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131316),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? const Color(0xFF222226),
          width: borderWidth ?? 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor ?? Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }

  // ── Status Header Card ──────────────────────────────────────────────
  Widget _buildStatusCard(LockStateProvider lockProvider) {
    const goldColor = Color(0xFFC6A85A);
    const warningColor = Color(0xFFB54534);
    const successColor = Color(0xFF1B4332);
    const activeGreen = Color(0xFF4ADE80);

    final bannerColor = lockProvider.isLocked ? warningColor.withValues(alpha: 0.06) : successColor.withValues(alpha: 0.1);
    final outlineColor = lockProvider.isLocked ? warningColor.withValues(alpha: 0.4) : activeGreen.withValues(alpha: 0.4);

    return _buildGlassCard(
      borderColor: outlineColor,
      glowColor: lockProvider.isLocked 
          ? warningColor.withValues(alpha: 0.04)
          : activeGreen.withValues(alpha: 0.04),
      child: Container(
        decoration: BoxDecoration(
          color: bannerColor,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (lockProvider.isLocked ? warningColor : activeGreen).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                lockProvider.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 40,
                color: lockProvider.isLocked ? warningColor : activeGreen,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              lockProvider.isLocked ? 'SYSTEM LOCK ACTIVE' : 'SYSTEM DISARMED',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: lockProvider.isLocked ? warningColor : activeGreen,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              lockProvider.isLocked 
                  ? 'Instagram, Reddit, and Twitter/X are actively secured.' 
                  : 'Defense system loaded. Configure parameters to lock.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8A7A6C),
              ),
            ),
            if (lockProvider.isLocked) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${lockProvider.remainingDays} Days Left',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: goldColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Lock Info Details Card ──────────────────────────────────────────
  Widget _buildLockInfoCard(LockStateProvider lockProvider) {
    return _buildGlassCard(
      child: Column(
        children: [
          _buildLockInfoRow('System Lock Ends:',
              lockProvider.lockEndDate?.toString().split('.').first ?? 'N/A'),
          const Divider(color: Color(0xFF222226), height: 20),
          _buildLockInfoRow('Duration Stated:',
              '${lockProvider.remainingDays} days remaining'),
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
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF0E6D2),
          ),
        ),
        Text(
          value, 
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF8A7A6C),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ── Emergency Unlock Control ────────────────────────────────────────
  Widget _buildEmergencyUnlockButton(LockStateProvider lockProvider) {
    const goldColor = Color(0xFFC6A85A);
    const warningColor = Color(0xFFB54534);

    return _buildGlassCard(
      borderColor: warningColor.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: warningColor, size: 20),
              SizedBox(width: 8),
              Text(
                'Emergency Unlock System',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFFF0E6D2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Requires a 1-hour active buffer delay combined with a physical 10,000-step exercise challenge.',
            style: TextStyle(fontSize: 12, color: Color(0xFF8A7A6C), height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              await lockProvider.requestEmergencyUnlock();
              if (mounted) Navigator.of(context).pushNamed('/emergency');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1512),
              foregroundColor: goldColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: goldColor.withValues(alpha: 0.3)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              'INITIATE EMERGENCY BREAKDOWN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyUnlockProgress(LockStateProvider lockProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    const goldColor = Color(0xFFC6A85A);

    return _buildGlassCard(
      borderColor: goldColor.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.hourglass_bottom_rounded, color: Color(0xFFC6A85A), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Emergency Deactivation',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF0E6D2)),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () async => await lockProvider.cancelEmergencyUnlock(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ABORT',
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildProgressSection(
              'Cooldown Delay', lockProvider.remainingDelay, '1 hour buffer period'),
          const Divider(color: Color(0xFF222226), height: 20),
          _buildProgressSection(
              'Physique Challenge',
              Duration(seconds: (lockProvider.currentSteps / 10000 * 3600).toInt()),
              '${lockProvider.currentSteps} / 10,000 steps'),
        ],
      ),
    );
  }

  Widget _buildProgressSection(String title, Duration duration, String subtitle) {
    const goldColor = Color(0xFFC6A85A);
    const activeGreen = Color(0xFF4ADE80);

    final complete = duration.inSeconds <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title, 
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF0E6D2),
              ),
            ),
            Text(
              complete
                  ? 'COMPLETED'
                  : '${duration.inHours}h ${duration.inMinutes % 60}m Left',
              style: TextStyle(
                color: complete ? activeGreen : goldColor,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8A7A6C)),
        ),
      ],
    );
  }

  // ── Screen Time Dashboard ──────────────────────────────────────────
  Widget _buildScreenTimeDashboard() {
    const goldColor = Color(0xFFC6A85A);
    const warningColor = Color(0xFFB54534);

    if (!_hasUsagePermission) {
      return _buildGlassCard(
        borderColor: warningColor.withValues(alpha: 0.3),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.screen_lock_portrait_rounded, color: warningColor, size: 20),
                SizedBox(width: 8),
                Text(
                  'Screen Time Dashboard',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF0E6D2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Physical usage tracking permission is needed to compile screen time data.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF8A7A6C), height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('AUTHORIZE MONITORING'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: warningColor.withValues(alpha: 0.12),
                  foregroundColor: warningColor,
                  side: BorderSide(color: warningColor.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
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
      {'pkg': 'com.instagram.android', 'name': 'Instagram', 'icon': Icons.camera_alt_outlined, 'color': Colors.pink},
      {'pkg': 'com.reddit.frontpage', 'name': 'Reddit', 'icon': Icons.forum_outlined, 'color': Colors.deepOrange},
      {'pkg': 'com.twitter.android', 'name': 'Twitter/X', 'icon': Icons.tag_rounded, 'color': Colors.blue},
    ];

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_outlined, color: goldColor, size: 20),
              SizedBox(width: 8),
              Text(
                'Screen Time Today',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF0E6D2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...apps.map((app) {
            final pkg = app['pkg'] as String;
            final name = app['name'] as String;
            final icon = app['icon'] as IconData;
            final color = app['color'] as Color;
            final appData = _screenTimeData[pkg];
            final screenTimeMs = (appData is Map ? appData['screenTimeMs'] : 0) as int? ?? 0;
            final formatted = UsageService.formatScreenTime(screenTimeMs);
            final heavyUsage = screenTimeMs > 1800000; // > 30 minutes

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF0E6D2),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: heavyUsage ? warningColor.withValues(alpha: 0.08) : const Color(0xFF1C1B1F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: heavyUsage ? warningColor.withValues(alpha: 0.3) : const Color(0xFF222226),
                      ),
                    ),
                    child: Text(
                      formatted,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: heavyUsage ? warningColor : const Color(0xFFF0E6D2),
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

  // ── App Open Counts Card Grid ──────────────────────────────────────
  Widget _buildAppOpenCountsCard() {
    const goldColor = Color(0xFFC6A85A);
    final apps = [
      {'pkg': 'com.instagram.android', 'name': 'Instagram', 'color': Colors.pink},
      {'pkg': 'com.reddit.frontpage', 'name': 'Reddit', 'color': Colors.deepOrange},
      {'pkg': 'com.twitter.android', 'name': 'Twitter/X', 'color': Colors.blue},
    ];

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.touch_app_outlined, color: goldColor, size: 20),
              SizedBox(width: 8),
              Text(
                'Interceptions Today',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF0E6D2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: apps.map((app) {
              final pkg = app['pkg'] as String;
              final name = app['name'] as String;
              final color = app['color'] as Color;
              final count = _openCounts[pkg] ?? 0;

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17171C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A7A6C),
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

  // ── Chrome Filter Card ──────────────────────────────────────────────
  Widget _buildChromeFilterCard() {
    final isActive = (_chromeFilterStatus['isActive'] ?? false) as bool;
    const activeGreen = Color(0xFF4ADE80);
    const warningColor = Color(0xFFB54534);

    final statusColor = isActive ? activeGreen : warningColor;
    final statusText = isActive ? 'ENFORCED' : 'DISABLED';

    return _buildGlassCard(
      borderColor: statusColor.withValues(alpha: 0.3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.private_connectivity_outlined,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Multi-Browser Private Mode Blocker',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF0E6D2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isActive 
                      ? 'Chrome, Firefox, Opera & Samsung private tabs monitored.' 
                      : 'Requires Setup for Private Browsing Blocker',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A7A6C),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Open Logs Card ──────────────────────────────────────────────
  Widget _buildAppOpenLogsCard() {
    const goldColor = Color(0xFFC6A85A);
    final displayLogs = _appLogs.take(10).toList();

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_toggle_off_rounded, color: goldColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Recent Intercept Audit Logs',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF0E6D2),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_appLogs.length} intercepted',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF8A7A6C)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (displayLogs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No bypass events recorded today.',
                style: TextStyle(fontSize: 12, color: Color(0xFF8A7A6C)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayLogs.length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E1E24), height: 12),
              itemBuilder: (context, index) {
                final log = displayLogs[index];
                final name = log['appName'] ?? '';
                final ts = log['timestamp'] ?? '';
                final timeOnly = ts.length > 10 ? ts.substring(11, 19) : ts;
                
                Color dotColor = Colors.grey;
                if (name == 'Instagram') dotColor = Colors.pink;
                if (name == 'Reddit') dotColor = Colors.deepOrange;
                if (name == 'Twitter/X') dotColor = Colors.blue;

                return Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF0E6D2),
                        ),
                      ),
                    ),
                    Text(
                      timeOnly,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A7A6C),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Reddit Usage Card ───────────────────────────────────────────────
  Widget _buildRedditUsageCard() {
    const goldColor = Color(0xFFC6A85A);
    const warningColor = Color(0xFFB54534);

    final usedSec = (_redditStatus['usedSeconds'] ?? 0) as int;
    final limitSec = (_redditStatus['limitSeconds'] ?? 3600) as int;
    final remainSec = (_redditStatus['remainingSeconds'] ?? 3600) as int;
    final isLimitReached = (_redditStatus['isLimitReached'] ?? false) as bool;
    final extraMin = (_redditStatus['extraMinutesEarned'] ?? 0) as int;
    final progress = limitSec > 0 ? (usedSec / limitSec).clamp(0.0, 1.0) : 0.0;

    final activeAccent = isLimitReached ? warningColor : goldColor;

    return _buildGlassCard(
      borderColor: activeAccent.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLimitReached ? Icons.do_not_disturb_on_outlined : Icons.hourglass_top_rounded,
                color: activeAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Reddit Daily Allowance',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: activeAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFF1C1C22),
              valueColor: AlwaysStoppedAnimation<Color>(activeAccent),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Used: ${RedditUsageService.formatDuration(usedSec)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8A7A6C)),
              ),
              Text(
                'Remaining: ${RedditUsageService.formatDuration(remainSec)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isLimitReached ? warningColor : const Color(0xFFF0E6D2),
                ),
              ),
            ],
          ),
          if (extraMin > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+$extraMin min bonus unlocked today',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF4ADE80),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (isLimitReached) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.fitness_center_outlined, size: 18),
                label: const Text('EARN +10 MINUTES (100 PUSHUPS)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: warningColor.withValues(alpha: 0.12),
                  foregroundColor: warningColor,
                  side: BorderSide(color: warningColor.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
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

  // ── System Mechanics Information Card ──────────────────────────────
  Widget _buildInfoCard() {
    const goldColor = Color(0xFFC6A85A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E0B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: goldColor.withValues(alpha: 0.2), width: 1),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: goldColor, size: 18),
              SizedBox(width: 8),
              Text(
                'FocusLock Core Dynamics',
                style: TextStyle(fontWeight: FontWeight.bold, color: goldColor, fontSize: 13),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '• Immediate overlay shields block access to distraction apps.\n'
            '• Physical effort required to temporarily access Reddit.\n'
            '• Device Administrator prevents impulsive app uninstalls.\n'
            '• Settings monitoring daemon locks down bypass loopholes.\n'
            '• Private tabs are monitored and closed automatically.',
            style: TextStyle(fontSize: 11, color: Color(0xFF8A7A6C), height: 1.6),
          ),
        ],
      ),
    );
  }
}
