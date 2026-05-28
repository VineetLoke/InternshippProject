import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class PermissionService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Check if *our* accessibility service is enabled (not just any).
  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final result = await _channel.invokeMethod('isAccessibilityEnabled');
      return result == true;
    } catch (e) {
      debugPrint('Error checking accessibility service: $e');
      return false;
    }
  }

  /// Open settings so the user can enable our accessibility service.
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      debugPrint('Error opening accessibility settings: $e');
    }
  }

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

  /// Check SYSTEM_ALERT_WINDOW (overlay) via native channel for accuracy
  Future<bool> hasOverlayPermission() async {
    try {
      if (!Platform.isAndroid) return true;
      final result = await _channel.invokeMethod('hasOverlayPermission');
      return result == true;
    } catch (e) {
      // Fall back to permission_handler
      try {
        final status = await Permission.systemAlertWindow.status;
        return status.isGranted;
      } catch (_) {
        return false;
      }
    }
  }

  /// Request overlay permission – opens Settings page
  Future<bool> requestOverlayPermission() async {
    try {
      if (!Platform.isAndroid) return true;
      final has = await hasOverlayPermission();
      if (has) return true;
      // Try native route first
      try {
        await _channel.invokeMethod('openOverlaySettings');
      } catch (_) {
        await Permission.systemAlertWindow.request();
      }
      return await hasOverlayPermission();
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
  Future<bool> hasUsageAccess() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasUsageStatsPermission');
      return result == true;
    } catch (e) {
      debugPrint('Error checking usage access: $e');
      return false;
    }
  }

  /// Tell the native side to start blocking now.
  Future<bool> startBlocking() async {
    try {
      final result = await _channel.invokeMethod('startBlocking');
      return result == true;
    } catch (e) {
      debugPrint('Error starting blocking: $e');
      return false;
    }
  }

  /// Request all necessary permissions in the right order.
  Future<Map<String, bool>> requestAllPermissions() async {
    final results = <String, bool>{};

    results['notification'] = await requestNotificationPermission();
    results['activityRecognition'] = await requestActivityRecognition();
    results['overlay'] = await hasOverlayPermission();
    results['accessibility'] = await isAccessibilityServiceEnabled();

    return results;
  }
}
