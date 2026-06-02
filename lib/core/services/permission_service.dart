import 'package:permission_handler/permission_handler.dart';
import 'platform_channel_service.dart';

class PermissionService {
  PermissionService._privateConstructor();
  static final PermissionService instance = PermissionService._privateConstructor();

  Future<bool> isAccessibilityEnabled() async {
    return await PlatformChannelService.instance.isAccessibilityEnabled();
  }

  Future<bool> isOverlayEnabled() async {
    return await PlatformChannelService.instance.canDrawOverlays();
  }

  Future<bool> isCameraEnabled() async {
    return await Permission.camera.isGranted;
  }

  Future<bool> areAllPermissionsGranted() async {
    final acc = await isAccessibilityEnabled();
    final over = await isOverlayEnabled();
    final cam = await isCameraEnabled();
    return acc && over && cam;
  }

  Future<void> requestCameraPermission() async {
    await Permission.camera.request();
  }
}
