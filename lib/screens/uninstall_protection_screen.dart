import 'dart:async';
import 'package:flutter/material.dart';
import '../services/uninstall_protection_service.dart';

/// Settings screen for managing FocusLock uninstall protection.
/// Controls: hide icon, device admin, protection status, cooldown display.
class UninstallProtectionScreen extends StatefulWidget {
  const UninstallProtectionScreen({Key? key}) : super(key: key);

  @override
  State<UninstallProtectionScreen> createState() =>
      _UninstallProtectionScreenState();
}

class _UninstallProtectionScreenState extends State<UninstallProtectionScreen> {
  final _service = UninstallProtectionService();
  Map<String, dynamic> _status = {};
  Timer? _cooldownTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await _service.getProtectionStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _loading = false;
      });

      // Start cooldown timer if in cooldown window
      final remaining = status['cooldownRemainingSeconds'] ?? 0;
      if (remaining > 0) {
        _startCooldownTimer();
      }
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFC6A85A)),
        ),
      );
    }

    final isAdminActive = _status['isDeviceAdminActive'] ?? false;
    final isProtectionEnabled = _status['isProtectionEnabled'] ?? false;
    final isUninstallAllowed = _status['isUninstallAllowed'] ?? false;
    final cooldownSeconds = _status['cooldownRemainingSeconds'] ?? 0;
    final isIconHidden = _status['isIconHidden'] ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: const Color(0xFFC6A85A),
        title: const Text('Protection Settings'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            _buildStatusCard(isAdminActive, isProtectionEnabled),
            const SizedBox(height: 24),

            // Hide icon toggle
            _buildToggleCard(
              title: 'Hide App Icon',
              subtitle: isIconHidden
                  ? 'Icon is hidden. Dial *#*#1717#*#* to access.'
                  : 'Icon is visible in app drawer.',
              value: isIconHidden,
              onChanged: (value) async {
                if (value) {
                  await _service.hideAppIcon();
                } else {
                  await _service.showAppIcon();
                }
                _refreshStatus();
              },
            ),
            const SizedBox(height: 16),

            // Device admin toggle
            _buildToggleCard(
              title: 'Uninstall Protection',
              subtitle: isAdminActive
                  ? 'Device admin active. Uninstall blocked.'
                  : 'Device admin inactive. App can be uninstalled.',
              value: isAdminActive,
              onChanged: (value) async {
                if (value) {
                  await _service.requestDeviceAdmin();
                } else {
                  if (isUninstallAllowed) {
                    await _service.removeDeviceAdmin();
                  } else {
                    // Show challenge needed dialog
                    _showChallengeDialog();
                  }
                }
                // Delay refresh to allow system dialog
                Future.delayed(const Duration(seconds: 1), _refreshStatus);
              },
            ),
            const SizedBox(height: 16),

            // Enable full protection button
            if (!isProtectionEnabled)
              _buildActionButton(
                text: 'ENABLE FULL PROTECTION',
                onPressed: () async {
                  await _service.enableProtection();
                  _refreshStatus();
                },
              ),

            // Cooldown window display
            if (isUninstallAllowed) ...[
              const SizedBox(height: 24),
              _buildCooldownCard(cooldownSeconds),
            ],

            const SizedBox(height: 32),

            // Info section
            _buildInfoSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool adminActive, bool protectionEnabled) {
    final isProtected = adminActive && protectionEnabled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isProtected
              ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
              : const Color(0xFFC6A85A).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            isProtected ? Icons.shield : Icons.shield_outlined,
            color: isProtected
                ? const Color(0xFF4CAF50)
                : const Color(0xFFC6A85A),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            isProtected ? 'Protection Active' : 'Protection Inactive',
            style: TextStyle(
              color: isProtected
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFC6A85A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isProtected
                ? '200 pushups required to remove'
                : 'Enable protection to prevent impulsive deletion',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFC6A85A),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFC6A85A),
          foregroundColor: const Color(0xFF0D0D0D),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCooldownCard(int remainingSeconds) {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'COOLDOWN ACTIVE',
            style: TextStyle(
              color: Color(0xFF4CAF50),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Color(0xFF4CAF50),
              fontSize: 36,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Uninstall is allowed during this window',
            style: TextStyle(color: Color(0xFF888888), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: TextStyle(
              color: Color(0xFFC6A85A),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 12),
          Text(
            '• Hide Icon: Removes the app from the drawer. '
            'Access via dialer: *#*#1717#*#*\n\n'
            '• Uninstall Protection: Registers as device administrator. '
            'Must be deactivated before uninstall.\n\n'
            '• Challenge: Complete 200 pushups to disable protection. '
            'Uses proximity sensor or manual tap.\n\n'
            '• Cooldown: After completing the challenge, you have 5 minutes '
            'to uninstall. Protection reactivates after.',
            style: TextStyle(color: Color(0xFF888888), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  void _showChallengeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Challenge Required',
          style: TextStyle(color: Color(0xFFC6A85A)),
        ),
        content: const Text(
          'Complete 200 pushups to disable protection.\n\n'
          'The challenge will open as an overlay.',
          style: TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _service.launchUninstallChallenge();
            },
            child: const Text(
              'START CHALLENGE',
              style: TextStyle(color: Color(0xFFC6A85A)),
            ),
          ),
        ],
      ),
    );
  }
}
