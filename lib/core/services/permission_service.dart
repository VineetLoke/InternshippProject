import 'package:permission_handler/permission_handler.dart';
import 'platform_channel_service.dart';

/// Unified permission checker for all 3 required permissions:
/// 1. Accessibility Service (via native channel)
/// 2. Draw Over Other Apps (via native channel)
/// 3. Camera (via permission_handler)
class PermissionService {
  final PlatformChannelService _platformService;

  PermissionService(this._platformService);

  /// Check if our Accessibility Service is enabled.
  Future<bool> isAccessibilityEnabled() async {
    return await _platformService.isAccessibilityEnabled();
  }

  /// Open Accessibility Settings so user can enable our service.
  Future<void> openAccessibilitySettings() async {
    await _platformService.openAccessibilitySettings();
  }

  /// Check if we have overlay permission.
  Future<bool> canDrawOverlays() async {
    return await _platformService.canDrawOverlays();
  }

  /// Open overlay permission settings.
  Future<void> requestOverlayPermission() async {
    await _platformService.requestOverlayPermission();
  }

  /// Check if camera permission is granted.
  Future<bool> isCameraGranted() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Request camera permission.
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Returns true if ALL 3 required permissions are granted.
  Future<bool> areAllPermissionsGranted() async {
    final accessibility = await isAccessibilityEnabled();
    final overlay = await canDrawOverlays();
    final camera = await isCameraGranted();
    return accessibility && overlay && camera;
  }
}
