import 'package:flutter/services.dart';

/// Service for accessing app open logs stored in the Room database.
class AppLogService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Get all app open logs for today (latest first).
  ///
  /// Each entry: `{ "appName": "Instagram", "packageName": "...", "timestamp": "2026-03-03 14:30:00" }`
  Future<List<Map<String, dynamic>>> getTodayLogs() async {
    try {
      final result = await _channel.invokeMethod('getAppOpenLogs');
      if (result == null) return [];
      return (result as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      print('Error getting app open logs: $e');
      return [];
    }
  }

  /// Get today's open count for a specific package.
  Future<int> getOpenCount(String packageName) async {
    try {
      final result = await _channel.invokeMethod('getAppOpenCount', {
        'packageName': packageName,
      });
      return (result as int?) ?? 0;
    } catch (e) {
      print('Error getting open count: $e');
      return 0;
    }
  }

  /// Get open counts for all tracked apps today.
  ///
  /// Returns `{ "com.instagram.android": 5, "com.reddit.frontpage": 3, ... }`
  Future<Map<String, int>> getAllOpenCounts() async {
    try {
      final result = await _channel.invokeMethod('getAllAppOpenCounts');
      if (result == null) return {};
      return Map<String, int>.from(result as Map);
    } catch (e) {
      print('Error getting all open counts: $e');
      return {};
    }
  }
}
