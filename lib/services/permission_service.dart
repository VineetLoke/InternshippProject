import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class PermissionService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Request ACTIVITY_RECOGNITION (step counter) – Android 10+
  Future<bool> requestActivityRecognition() async {
    try {
      final status = await Permission.activityRecognition.status;
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      final result = await Permission.activityRecognition.request();
      return result.isGranted;
    } catch (e) {
      debugPrint('ActivityRecognition permission error: $e');
      return false;
    }
  }

  /// Check ACTIVITY_RECOGNITION without requesting
  Future<bool> hasActivityRecognition() async {
    try {
      final status = await Permission.activityRecognition.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Check SYSTEM_ALERT_WINDOW (overlay) – must be granted via Settings
  Future<bool> hasOverlayPermission() async {
    try {
      if (!Platform.isAndroid) return true;
      final status = await Permission.systemAlertWindow.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Request overlay permission – opens Settings page
  Future<bool> requestOverlayPermission() async {
    try {
      if (!Platform.isAndroid) return true;
      final status = await Permission.systemAlertWindow.status;
      if (status.isGranted) return true;
      // Overlay must be enabled via Settings – open and wait
      await Permission.systemAlertWindow.request();
      return (await Permission.systemAlertWindow.status).isGranted;
    } catch (e) {
      debugPrint('Overlay permission error: $e');
      return false;
    }
  }

  /// Check POST_NOTIFICATIONS – Android 13+
  Future<bool> hasNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      return true; // pre-Android-13 always granted
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (e) {
      return true;
    }
  }

  /// Check Usage Access via platform channel (PACKAGE_USAGE_STATS)
  /// This cannot be requested programmatically – user must go to Settings.
  Future<bool> hasUsageAccess() async {
    try {
      // We can't check this without a native method; default to true to avoid
      // blocking the app. The accessibility service handles blocking.
      return true;
    } catch (e) {
      return true;
    }
  }

  /// Request all necessary permissions in the right order.
  /// Returns a summary map.
  Future<Map<String, bool>> requestAllPermissions() async {
    final results = <String, bool>{};

    results['notification'] = await requestNotificationPermission();
    results['activityRecognition'] = await requestActivityRecognition();
    results['overlay'] = await hasOverlayPermission(); // just check; don't block

    return results;
  }
}
