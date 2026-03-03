import 'package:flutter/services.dart';

/// Provides screen time data from Android UsageStatsManager for tracked apps.
class UsageService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Get screen time data for all tracked apps today.
  ///
  /// Returns a map keyed by package name:
  /// ```
  /// { "com.instagram.android": { "name": "Instagram", "screenTimeMs": 12345 }, ... }
  /// ```
  Future<Map<String, dynamic>> getScreenTimeData() async {
    try {
      final result = await _channel.invokeMethod('getScreenTimeData');
      if (result == null) return {};
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      print('Error getting screen time data: $e');
      return {};
    }
  }

  /// Check if usage stats permission is granted.
  Future<bool> hasUsageStatsPermission() async {
    try {
      final result = await _channel.invokeMethod('hasUsageStatsPermission');
      return result == true;
    } catch (e) {
      print('Error checking usage stats permission: $e');
      return false;
    }
  }

  /// Open usage stats settings page.
  Future<void> openUsageStatsSettings() async {
    try {
      await _channel.invokeMethod('openUsageStatsSettings');
    } catch (e) {
      print('Error opening usage stats settings: $e');
    }
  }

  /// Format milliseconds to "Xh Ym" or "Xm" string.
  static String formatScreenTime(int ms) {
    if (ms <= 0) return '0m';
    final hours = ms ~/ 3600000;
    final minutes = (ms % 3600000) ~/ 60000;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '<1m';
  }
}
