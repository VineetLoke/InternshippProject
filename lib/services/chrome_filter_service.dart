import 'package:flutter/services.dart';

/// Service for Chrome incognito mode policy control.
///
/// Uses Chrome's managed configuration policy (IncognitoModeAvailability: 1)
/// via DevicePolicyManager to disable incognito mode entirely.
/// Requires the app to be Device Owner or Profile Owner.
class ChromeFilterService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Get the current Chrome incognito policy status.
  ///
  /// Returns `{ "isActive": bool, "isDeviceOwner": bool, "policyApplied": bool }`
  Future<Map<String, dynamic>> getFilterStatus() async {
    try {
      final result = await _channel.invokeMethod('getChromeFilterStatus');
      if (result == null) {
        return {'isActive': false, 'isDeviceOwner': false, 'policyApplied': false};
      }
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      print('Error getting Chrome filter status: $e');
      return {
        'isActive': false,
        'isDeviceOwner': false,
        'policyApplied': false,
      };
    }
  }

  /// Apply the Chrome incognito policy.
  Future<bool> applyPolicy() async {
    try {
      final result = await _channel.invokeMethod('applyChromeIncognitoPolicy');
      return result == true;
    } catch (e) {
      print('Error applying Chrome policy: $e');
      return false;
    }
  }

  /// Remove the Chrome incognito policy.
  Future<bool> removePolicy() async {
    try {
      final result = await _channel.invokeMethod('removeChromeIncognitoPolicy');
      return result == true;
    } catch (e) {
      print('Error removing Chrome policy: $e');
      return false;
    }
  }

  /// Check if the app is Device Owner or Profile Owner.
  Future<bool> isDeviceOwnerOrProfileOwner() async {
    try {
      final result = await _channel.invokeMethod('isDeviceOwnerOrProfileOwner');
      return result == true;
    } catch (e) {
      print('Error checking device owner status: $e');
      return false;
    }
  }
}
