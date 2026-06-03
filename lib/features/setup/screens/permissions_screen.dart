import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/permission_service.dart';

/// Step-by-step permission granting screen with premium dark UI.
/// Guides the user through enabling:
/// 1. Accessibility Service
/// 2. Draw Over Other Apps
/// 3. Camera Permission
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _accessibilityEnabled = false;
  bool _overlayEnabled = false;
  bool _cameraEnabled = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions when user returns from system settings
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final service = Provider.of<PermissionService>(context, listen: false);
    final accessibility = await service.isAccessibilityEnabled();
    final overlay = await service.canDrawOverlays();
    final camera = await service.isCameraGranted();

    if (!mounted) return;
    setState(() {
      _accessibilityEnabled = accessibility;
      _overlayEnabled = overlay;
      _cameraEnabled = camera;
      _checking = false;
    });
  }

  bool get _allGranted =>
      _accessibilityEnabled && _overlayEnabled && _cameraEnabled;

  void _showAccessibilityGuide() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.accessibility_new_rounded, color: Color(0xFF7C4DFF)),
            SizedBox(width: 10),
            Text(
              'Accessibility Permission',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FocusLock requires this service to run in the background and lock Instagram.',
                style: TextStyle(color: Color(0xFF8888A0), fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                '⚠️ Android 13+ "Restricted Setting":',
                style: TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                'If the switch is disabled or grayed out:\n\n'
                '1. Go to settings, find Apps > FocusLock.\n'
                '2. Click the 3-dots in top-right menu.\n'
                '3. Choose "Allow restricted settings".\n'
                '4. Return here, click this card, and turn on the FocusLock Accessibility Service.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8888A0))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final service = Provider.of<PermissionService>(context, listen: false);
              await service.openAccessibilitySettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              // Header
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)],
                ).createShader(bounds),
                child: const Text(
                  '🛡️ Setup FocusLock',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Grant these permissions to block Instagram and track your pushups.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 40),

              // Permission cards
              _buildPermissionCard(
                step: 1,
                title: 'Accessibility Service',
                subtitle: 'Detects when you open Instagram',
                icon: Icons.accessibility_new_rounded,
                isGranted: _accessibilityEnabled,
                onTap: _showAccessibilityGuide,
              ),

              const SizedBox(height: 16),

              _buildPermissionCard(
                step: 2,
                title: 'Draw Over Other Apps',
                subtitle: 'Shows the lock screen overlay',
                icon: Icons.layers_rounded,
                isGranted: _overlayEnabled,
                onTap: () async {
                  final service =
                      Provider.of<PermissionService>(context, listen: false);
                  await service.requestOverlayPermission();
                },
              ),
              const SizedBox(height: 16),

              _buildPermissionCard(
                step: 3,
                title: 'Camera',
                subtitle: 'Needed for pushup pose detection',
                icon: Icons.camera_alt_rounded,
                isGranted: _cameraEnabled,
                onTap: () async {
                  final service =
                      Provider.of<PermissionService>(context, listen: false);
                  final granted = await service.requestCameraPermission();
                  if (mounted) {
                    setState(() => _cameraEnabled = granted);
                  }
                },
              ),

              const Spacer(),

              // Continue button
              AnimatedOpacity(
                opacity: _allGranted ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _allGranted
                        ? () {
                            Navigator.of(context).pushReplacementNamed('/home');
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      disabledBackgroundColor: const Color(0xFF2A2A40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _allGranted ? 'Continue' : 'Grant All Permissions',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_allGranted) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required int step,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: isGranted
            ? const LinearGradient(
                colors: [Color(0xFF1B3A1B), Color(0xFF0D2B0D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted
              ? const Color(0xFF4CAF50).withOpacity(0.5)
              : const Color(0xFF7C4DFF).withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isGranted ? const Color(0xFF4CAF50) : const Color(0xFF7C4DFF))
                .withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isGranted ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Step number / check
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isGranted
                        ? const Color(0xFF4CAF50).withOpacity(0.2)
                        : const Color(0xFF7C4DFF).withOpacity(0.2),
                  ),
                  child: Center(
                    child: isGranted
                        ? const Icon(Icons.check_rounded,
                            color: Color(0xFF4CAF50), size: 24)
                        : Text(
                            '$step',
                            style: const TextStyle(
                              color: Color(0xFF7C4DFF),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isGranted
                              ? const Color(0xFF4CAF50)
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isGranted
                              ? const Color(0xFF4CAF50).withOpacity(0.7)
                              : const Color(0xFF8888A0),
                        ),
                      ),
                    ],
                  ),
                ),

                // Action icon
                Icon(
                  isGranted ? Icons.verified_rounded : Icons.arrow_forward_ios_rounded,
                  color: isGranted
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF7C4DFF),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
