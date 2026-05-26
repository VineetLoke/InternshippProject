import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppBlockService {
  static const String _lockStartTimeKey = 'lock_start_time';
  static const String _lockDurationDaysKey = 'lock_duration_days';
  static const int _defaultLockDays = 30;

  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Initialize lock with the app's canonical 30-day duration.
  Future<bool> initializeLock() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final now = DateTime.now();
      final startTimeStr = now.toUtc().toIso8601String();

      await prefs.setString(
        _lockStartTimeKey,
        startTimeStr,
      );
      await prefs.setInt(_lockDurationDaysKey, _defaultLockDays);

      try {
        await _channel.invokeMethod('startBlocking', {
          'lock_start_time': startTimeStr,
          'lock_duration_days': _defaultLockDays,
        });
      } catch (e) {
        debugPrint('Error calling startBlocking: $e');
        // Keep the lock active even if accessibility service isn't active/setup yet
      }

      return true;
    } catch (e) {
      await _clearLockPrefs(prefs);
      debugPrint('Error initializing lock: $e');
      return false;
    }
  }

  /// Check if the shared lock window is still active.
  Future<bool> isLocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockStartStr = prefs.getString(_lockStartTimeKey);
      if (lockStartStr == null) return false;

      final lockStart = DateTime.parse(lockStartStr);
      final lockDays = prefs.getInt(_lockDurationDaysKey) ?? _defaultLockDays;
      final lockEnd = lockStart.add(Duration(days: lockDays));

      return DateTime.now().isBefore(lockEnd);
    } catch (e) {
      debugPrint('Error checking lock status: $e');
      return false;
    }
  }

  /// Get remaining days until unlock.
  Future<int> getRemainingDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockStartStr = prefs.getString(_lockStartTimeKey);
      if (lockStartStr == null) return 0;

      final lockStart = DateTime.parse(lockStartStr);
      final lockDays = prefs.getInt(_lockDurationDaysKey) ?? _defaultLockDays;
      final lockEnd = lockStart.add(Duration(days: lockDays));

      final remaining = lockEnd.difference(DateTime.now()).inDays;
      return remaining > 0 ? remaining : 0;
    } catch (e) {
      debugPrint('Error getting remaining days: $e');
      return 0;
    }
  }

  /// Get lock end date.
  Future<DateTime?> getLockEndDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockStartStr = prefs.getString(_lockStartTimeKey);
      if (lockStartStr == null) return null;

      final lockStart = DateTime.parse(lockStartStr);
      final lockDays = prefs.getInt(_lockDurationDaysKey) ?? _defaultLockDays;
      return lockStart.add(Duration(days: lockDays));
    } catch (e) {
      debugPrint('Error getting lock end date: $e');
      return null;
    }
  }

  /// Clear the shared lock state.
  Future<void> unlock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _clearLockPrefs(prefs);
      try {
        await _channel.invokeMethod('unlock');
      } catch (e) {
        debugPrint('Error calling native unlock: $e');
      }
    } catch (e) {
      debugPrint('Error unlocking: $e');
    }
  }

  Future<void> resetLock() async {
    await unlock();
    await initializeLock();
  }

  Future<Map<String, dynamic>> getLockStatus() async {
    final locked = await isLocked();
    final remaining = await getRemainingDays();
    final endDate = await getLockEndDate();

    return {
      'locked': locked,
      'remainingDays': remaining,
      'endDate': endDate,
    };
  }

  Future<void> _clearLockPrefs(SharedPreferences prefs) async {
    await prefs.remove(_lockStartTimeKey);
    await prefs.remove(_lockDurationDaysKey);
  }
}
