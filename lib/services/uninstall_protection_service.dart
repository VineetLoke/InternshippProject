import 'dart:async';
import 'package:flutter/services.dart';

/// Flutter interface to the native uninstall protection system.
///
/// Features:
/// - Hide/show app icon from launcher
/// - Device administrator management
/// - Pushup challenge for uninstall (200 pushups)
/// - 5-minute cooldown window after challenge completion
class UninstallProtectionService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Get full protection status.
  Future<Map<String, dynamic>> getProtectionStatus() async {
    try {
      final result = await _channel.invokeMethod('getProtectionStatus');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      print('Error getting protection status: $e');
      return {};
    }
  }

  /// Hide the app icon from the launcher.
  Future<bool> hideAppIcon() async {
    try {
      final result = await _channel.invokeMethod('hideAppIcon');
      return result == true;
    } catch (e) {
      print('Error hiding app icon: $e');
      return false;
    }
  }

  /// Show the app icon in the launcher.
  Future<bool> showAppIcon() async {
    try {
      final result = await _channel.invokeMethod('showAppIcon');
      return result == true;
    } catch (e) {
      print('Error showing app icon: $e');
      return false;
    }
  }

  /// Check if the app icon is currently hidden.
  Future<bool> isIconHidden() async {
    try {
      final result = await _channel.invokeMethod('isIconHidden');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Request device administrator activation.
  Future<void> requestDeviceAdmin() async {
    try {
      await _channel.invokeMethod('requestDeviceAdmin');
    } catch (e) {
      print('Error requesting device admin: $e');
    }
  }

  /// Check if device admin is active.
  Future<bool> isDeviceAdminActive() async {
    try {
      final result = await _channel.invokeMethod('isDeviceAdminActive');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Enable full protection (hide icon + activate device admin).
  Future<void> enableProtection() async {
    try {
      await _channel.invokeMethod('enableProtection');
    } catch (e) {
      print('Error enabling protection: $e');
    }
  }

  /// Check if uninstall is currently allowed (within cooldown).
  Future<bool> isUninstallAllowed() async {
    try {
      final result = await _channel.invokeMethod('isUninstallAllowed');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Get remaining cooldown seconds.
  Future<int> getCooldownRemaining() async {
    try {
      final result = await _channel.invokeMethod('getCooldownRemaining');
      return (result as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Launch the uninstall challenge overlay from native side.
  Future<void> launchUninstallChallenge() async {
    try {
      await _channel.invokeMethod('launchUninstallChallenge');
    } catch (e) {
      print('Error launching challenge: $e');
    }
  }

  /// Configure kiosk packages (device owner required).
  Future<bool> enableKiosk({List<String>? packages}) async {
    try {
      final result = await _channel.invokeMethod('enableKiosk', {'packages': packages});
      return result == true;
    } catch (e) {
      print('Error enabling kiosk: $e');
      return false;
    }
  }

  Future<bool> disableKiosk() async {
    try {
      final result = await _channel.invokeMethod('disableKiosk');
      return result == true;
    } catch (e) {
      print('Error disabling kiosk: $e');
      return false;
    }
  }

  Future<bool> enterLockTask() async {
    try {
      final result = await _channel.invokeMethod('enterLockTask');
      return result == true;
    } catch (e) {
      print('Error entering lock task: $e');
      return false;
    }
  }

  Future<bool> exitLockTask() async {
    try {
      final result = await _channel.invokeMethod('exitLockTask');
      return result == true;
    } catch (e) {
      print('Error exiting lock task: $e');
      return false;
    }
  }

  /// Retrieve the tamper log content for disable attempts.
  Future<String> getDisableAttemptsLog() async {
    try {
      final result = await _channel.invokeMethod('getDisableAttemptsLog');
      return result as String? ?? '';
    } catch (e) {
      print('Error fetching disable attempts log: $e');
      return '';
    }
  }

  /// Remove device admin (only works during cooldown window).
  Future<bool> removeDeviceAdmin() async {
    try {
      final result = await _channel.invokeMethod('removeDeviceAdmin');
      return result == true;
    } catch (e) {
      print('Error removing device admin: $e');
      return false;
    }
  }
}
