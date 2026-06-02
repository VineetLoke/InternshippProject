import 'package:flutter/material.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/platform_channel_service.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  bool _accessibilityGranted = false;
  bool _overlayGranted = false;
  bool _cameraGranted = false;
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
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _checking = true);
    final acc = await PermissionService.instance.isAccessibilityEnabled();
    final over = await PermissionService.instance.isOverlayEnabled();
    final cam = await PermissionService.instance.isCameraEnabled();
    if (mounted) {
      setState(() {
        _accessibilityGranted = acc;
        _overlayGranted = over;
        _cameraGranted = cam;
        _checking = false;
      });
    }
  }

  Widget _buildPermissionCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return Card(
      color: const Color(0xff16213e),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isGranted ? const Color(0xff00d4aa) : const Color(0xff6c63ff).withOpacity(0.3),
          width: 1,
        ),
      ),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isGranted ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isGranted ? const Color(0xff00d4aa) : const Color(0xff6c63ff)).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isGranted ? const Color(0xff00d4aa) : const Color(0xff6c63ff),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              isGranted
                  ? const Icon(Icons.check_circle, color: Color(0xff00d4aa), size: 28)
                  : const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allGranted = _accessibilityGranted && _overlayGranted && _cameraGranted;

    return Scaffold(
      backgroundColor: const Color(0xff0a0a1a),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 30),
              const Text(
                "Set Up FocusLock",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Complete these setup steps to activate the app blocker and camera verification.",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: _checking
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xff6c63ff)),
                        ),
                      )
                    : ListView(
                        children: [
                          _buildPermissionCard(
                            title: "Accessibility Service",
                            description: "Required to monitor and block distracting apps.",
                            icon: Icons.accessibility_new,
                            isGranted: _accessibilityGranted,
                            onTap: () => PlatformChannelService.instance.openAccessibilitySettings(),
                          ),
                          _buildPermissionCard(
                            title: "Draw Over Other Apps",
                            description: "Allows FocusLock to display blocking lock screens.",
                            icon: Icons.layers,
                            isGranted: _overlayGranted,
                            onTap: () => PlatformChannelService.instance.requestOverlayPermission(),
                          ),
                          _buildPermissionCard(
                            title: "Camera Access",
                            description: "Used for real-time pushup pose detection.",
                            icon: Icons.camera_alt,
                            isGranted: _cameraGranted,
                            onTap: () async {
                              await PermissionService.instance.requestCameraPermission();
                              _checkPermissions();
                            },
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: allGranted ? const Color(0xff6c63ff) : Colors.white10,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: allGranted ? 4 : 0,
                  ),
                  onPressed: allGranted
                      ? () {
                          Navigator.pushReplacementNamed(context, '/home');
                        }
                      : null,
                  child: Text(
                    "Activate Blocker",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: allGranted ? Colors.white : Colors.white30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
