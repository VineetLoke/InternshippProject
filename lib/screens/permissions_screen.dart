import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

/// Walks users through every permission the app needs before setup begins.
/// Must be completed before the 30-day lock is activated.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({Key? key}) : super(key: key);

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  static const _platform =
      MethodChannel('com.example.focus_lock/app_block');

  bool _overlayGranted = false;
  bool _accessibilityEnabled = false;
  bool _activityRecognitionGranted = false;
  bool _notificationGranted = false;

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
      // Ask the native side; fall back to false if channel not set up yet.
      final enabled = await _platform
          .invokeMethod<bool>('isAccessibilityEnabled')
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (mounted) setState(() => _accessibilityEnabled = enabled ?? false);
    } catch (_) {
      // Channel not wired yet — treat as not enabled
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

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _requestOverlay() async {
    try {
      // On Android, systemAlertWindow.request() opens the Settings page.
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
      // If channel not ready, try app settings fallback
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

  void _proceed() {
    Navigator.of(context).pushReplacementNamed('/setup');
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Required Permissions'),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Icon(Icons.security, size: 60, color: Colors.blue.shade700),
          const SizedBox(height: 16),
          const Text(
            'FocusLock needs a few permissions to block Instagram.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'The first two are required. The rest are optional.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 28),

          // ── Required ─────────────────────────────────────────────────────
          _sectionLabel('Required', Colors.red.shade700),
          const SizedBox(height: 8),

          _permTile(
            icon: Icons.layers,
            title: 'Display Over Other Apps',
            subtitle:
                'Lets FocusLock show a block screen on top of Instagram.',
            granted: _overlayGranted,
            onTap: _requestOverlay,
            buttonLabel: 'Open Settings',
          ),
          const SizedBox(height: 12),

          _permTile(
            icon: Icons.accessibility_new,
            title: 'Accessibility Service',
            subtitle:
                'Detects when Instagram is opened so it can be blocked.',
            granted: _accessibilityEnabled,
            onTap: _openAccessibilitySettings,
            buttonLabel: 'Enable Service',
          ),
          const SizedBox(height: 28),

          // ── Optional ─────────────────────────────────────────────────────
          _sectionLabel('Optional', Colors.grey.shade700),
          const SizedBox(height: 8),

          _permTile(
            icon: Icons.directions_walk,
            title: 'Physical Activity',
            subtitle: 'Used for the 10,000-step emergency unlock challenge.',
            granted: _activityRecognitionGranted,
            onTap: _requestActivityRecognition,
            buttonLabel: 'Allow',
          ),
          const SizedBox(height: 12),

          _permTile(
            icon: Icons.notifications,
            title: 'Notifications',
            subtitle: 'Shows status notifications while the lock is active.',
            granted: _notificationGranted,
            onTap: _requestNotification,
            buttonLabel: 'Allow',
          ),
          const SizedBox(height: 36),

          // Continue button
          ElevatedButton(
            onPressed: _allRequiredGranted ? _proceed : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              backgroundColor: Colors.blue.shade700,
              disabledBackgroundColor: Colors.grey.shade300,
            ),
            child: Text(
              _allRequiredGranted
                  ? 'Continue to Setup'
                  : 'Grant required permissions above',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _allRequiredGranted ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ),

          if (!_allRequiredGranted) ...[
            const SizedBox(height: 10),
            Text(
              'Both required permissions must be granted before you can continue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.5,
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
    return Container(
      decoration: BoxDecoration(
        color: granted ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted ? Colors.green.shade300 : Colors.grey.shade300,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon,
              size: 32,
              color: granted ? Colors.green.shade700 : Colors.grey.shade600),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          granted
              ? Icon(Icons.check_circle, color: Colors.green.shade600, size: 28)
              : TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(buttonLabel,
                      style: TextStyle(
                          fontSize: 12, color: Colors.blue.shade700)),
                ),
        ],
      ),
    );
  }
}
