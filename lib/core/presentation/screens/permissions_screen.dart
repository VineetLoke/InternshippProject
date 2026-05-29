import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:io';

/// Walks users through every permission the app needs before setup begins.
/// Must be completed before the 30-day lock is activated.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  static const _platform = MethodChannel('com.example.focus_lock/app_block');

  bool _overlayGranted = false;
  bool _accessibilityEnabled = false;
  bool _activityRecognitionGranted = false;
  bool _notificationGranted = false;
  bool _usageAccessGranted = false;
  bool _batteryExempt = false;

  bool get _allRequiredGranted => _overlayGranted && _accessibilityEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check every time the user returns from the Settings screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _checkOverlay(),
      _checkAccessibility(),
      _checkActivityRecognition(),
      _checkNotification(),
      _checkUsageAccess(),
      _checkBatteryOptimization(),
    ]);
  }

  Future<void> _checkOverlay() async {
    try {
      final status = await Permission.systemAlertWindow.status;
      if (mounted) setState(() => _overlayGranted = status.isGranted);
    } catch (_) {}
  }

  Future<void> _checkAccessibility() async {
    try {
      final enabled = await _platform
          .invokeMethod<bool>('isAccessibilityEnabled')
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (mounted) setState(() => _accessibilityEnabled = enabled ?? false);
    } catch (_) {
      if (mounted) setState(() => _accessibilityEnabled = false);
    }
  }

  Future<void> _checkActivityRecognition() async {
    try {
      final status = await Permission.activityRecognition.status;
      if (mounted) {
        setState(() => _activityRecognitionGranted = status.isGranted);
      }
    } catch (_) {}
  }

  Future<void> _checkNotification() async {
    try {
      final status = await Permission.notification.status;
      if (mounted) setState(() => _notificationGranted = status.isGranted);
    } catch (_) {
      if (mounted) setState(() => _notificationGranted = true);
    }
  }

  Future<void> _checkUsageAccess() async {
    try {
      final result = await _platform
          .invokeMethod<bool>('hasUsageStatsPermission')
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (mounted) setState(() => _usageAccessGranted = result ?? false);
    } catch (_) {
      if (mounted) setState(() => _usageAccessGranted = false);
    }
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      if (!Platform.isAndroid) {
        if (mounted) setState(() => _batteryExempt = true);
        return;
      }
      final result = await _platform
          .invokeMethod<bool>('isIgnoringBatteryOptimizations')
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (mounted) setState(() => _batteryExempt = result ?? false);
    } catch (_) {
      if (mounted) setState(() => _batteryExempt = false);
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _requestOverlay() async {
    try {
      await Permission.systemAlertWindow.request();
      await _checkOverlay();
    } catch (e) {
      debugPrint('Overlay permission error: $e');
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _platform.invokeMethod('openAccessibilitySettings');
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<void> _requestActivityRecognition() async {
    try {
      await Permission.activityRecognition.request();
      await _checkActivityRecognition();
    } catch (e) {
      debugPrint('Activity recognition error: $e');
    }
  }

  Future<void> _requestNotification() async {
    try {
      await Permission.notification.request();
      await _checkNotification();
    } catch (e) {
      debugPrint('Notification permission error: $e');
    }
  }

  Future<void> _openUsageAccessSettings() async {
    try {
      await _platform.invokeMethod('openUsageStatsSettings');
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      await _platform.invokeMethod('requestIgnoreBatteryOptimizations');
      await _checkBatteryOptimization();
    } catch (e) {
      debugPrint('Battery optimization exemption error: $e');
    }
  }

  void _proceed() {
    Navigator.of(context).pushReplacementNamed('/setup');
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFC6A85A);
    const mutedGold = Color(0xFF8A7A6C);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Security Configuration',
          style: TextStyle(
            color: Color(0xFFC6A85A),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF14130E), Color(0xFF0A0A0C)],
            center: Alignment.topCenter,
            radius: 1.5,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            const SizedBox(height: 10),
            // Header Shield
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: goldColor.withValues(alpha: 0.08),
                    ),
                  ),
                  const Icon(Icons.shield_outlined, size: 48, color: goldColor),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unbypassable Defense System',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFFF0E6D2),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'FocusLock requires system permissions to secure your lock against modifications, settings bypasses, and task terminations.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: mutedGold,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 30),

            // ── Required Permissions ──
            _sectionLabel('CRITICAL DEFENSES', const Color(0xFFB54534)),
            const SizedBox(height: 12),

            _permTile(
              icon: Icons.layers_outlined,
              title: 'Display Over Other Apps',
              subtitle: 'Secures social apps instantly with a gold blocker overlay upon unauthorized entry.',
              granted: _overlayGranted,
              onTap: _requestOverlay,
              buttonLabel: 'Configure',
            ),
            const SizedBox(height: 12),

            _permTile(
              icon: Icons.accessibility_new_outlined,
              title: 'Accessibility Control',
              subtitle: 'Active background blocker daemon detecting and preventing unauthorized settings changes and package managers.',
              granted: _accessibilityEnabled,
              onTap: _openAccessibilitySettings,
              buttonLabel: 'Configure',
            ),
            const SizedBox(height: 28),

            // ── Optional/Recommended Permissions ──
            _sectionLabel('SYSTEM DURABILITY', const Color(0xFFC6A85A)),
            const SizedBox(height: 12),

            _permTile(
              icon: Icons.battery_saver_outlined,
              title: 'Battery Optimization Exemption',
              subtitle: 'Exempts FocusLock from background termination policies to guarantee continuous protection.',
              granted: _batteryExempt,
              onTap: _requestBatteryOptimization,
              buttonLabel: 'Exempt',
            ),
            const SizedBox(height: 12),

            _permTile(
              icon: Icons.bar_chart_outlined,
              title: 'App Usage Metrics',
              subtitle: 'Tracks real-time active screen-time metrics to accurately compute daily usage rules.',
              granted: _usageAccessGranted,
              onTap: _openUsageAccessSettings,
              buttonLabel: 'Configure',
            ),
            const SizedBox(height: 12),

            _permTile(
              icon: Icons.notifications_none_outlined,
              title: 'System Notifications',
              subtitle: 'Enables high-priority persistent notifications required to keep Android from killing the block service.',
              granted: _notificationGranted,
              onTap: _requestNotification,
              buttonLabel: 'Allow',
            ),
            const SizedBox(height: 12),

            _permTile(
              icon: Icons.directions_walk_outlined,
              title: 'Physical Activity Sensor',
              subtitle: 'Detects steps taken to unlock the fallback rescue door.',
              granted: _activityRecognitionGranted,
              onTap: _requestActivityRecognition,
              buttonLabel: 'Allow',
            ),
            const SizedBox(height: 40),

            // Continue action
            ElevatedButton(
              onPressed: _allRequiredGranted ? _proceed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _allRequiredGranted ? goldColor : const Color(0xFF222226),
                foregroundColor: _allRequiredGranted ? const Color(0xFF0F0E0B) : mutedGold,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _allRequiredGranted ? goldColor : Colors.transparent,
                    width: 1,
                  ),
                ),
                elevation: _allRequiredGranted ? 4 : 0,
                shadowColor: goldColor.withValues(alpha: 0.3),
              ),
              child: Text(
                _allRequiredGranted
                    ? 'ACTIVATE SHIELD SETUP'
                    : 'GRANT CRITICAL DEFENSES ABOVE',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Both critical defenses must be active to initiate setup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: _allRequiredGranted ? mutedGold.withValues(alpha: 0.6) : const Color(0xFFB54534),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, Color accentColor) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(1.5),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: accentColor,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Divider(
            color: accentColor.withValues(alpha: 0.15),
            thickness: 1,
          ),
        ),
      ],
    );
  }

  Widget _permTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
    required String buttonLabel,
  }) {
    const goldColor = Color(0xFFC6A85A);
    const forestGreen = Color(0xFF1B4332);
    const activeGreen = Color(0xFF4ADE80);
    
    final cardColor = granted ? const Color(0xFF0D0F0E) : const Color(0xFF131316);
    final borderColor = granted 
        ? forestGreen.withValues(alpha: 0.6)
        : goldColor.withValues(alpha: 0.25);
        
    final glowColor = granted 
        ? activeGreen.withValues(alpha: 0.03)
        : goldColor.withValues(alpha: 0.04);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor,
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: granted ? activeGreen.withValues(alpha: 0.06) : goldColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 24,
              color: granted ? activeGreen : goldColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFFF0E6D2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Small capsule status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: granted 
                            ? activeGreen.withValues(alpha: 0.1)
                            : goldColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        granted ? 'SECURED' : 'PENDING',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: granted ? activeGreen : goldColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF8A7A6C),
                    height: 1.4,
                  ),
                ),
                if (!granted) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 32,
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: goldColor.withValues(alpha: 0.12),
                          foregroundColor: goldColor,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: goldColor.withValues(alpha: 0.4), width: 1),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          buttonLabel.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
