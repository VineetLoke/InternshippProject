import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class AppBlockService {
  static const String _instagramPackage = 'com.instagram.android';
  static const String _lockStartTimeKey = 'lock_start_time';
  static const String _lockDurationDaysKey = 'lock_duration_days';
  static const int _defaultLockDays = 30;

  /// Initialize lock with default 30-day duration
  Future<bool> initializeLock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      
      await prefs.setString(
        _lockStartTimeKey,
        now.toIso8601String(),
      );
      
      await prefs.setInt(
        _lockDurationDaysKey,
        _defaultLockDays,
      );
      
      return true;
    } catch (e) {
      print('Error initializing lock: $e');
      return false;
    }
  }

  /// Check if Instagram is currently locked
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
      print('Error checking lock status: $e');
      return false;
    }
  }

  /// Get remaining days until unlock
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
      print('Error getting remaining days: $e');
      return 0;
    }
  }

  /// Get lock end date
  Future<DateTime?> getLockEndDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final lockStartStr = prefs.getString(_lockStartTimeKey);
      if (lockStartStr == null) return null;
      
      final lockStart = DateTime.parse(lockStartStr);
      final lockDays = prefs.getInt(_lockDurationDaysKey) ?? _defaultLockDays;
      
      return lockStart.add(Duration(days: lockDays));
    } catch (e) {
      print('Error getting lock end date: $e');
      return null;
    }
  }

  /// Manually unlock (for testing or admin purposes)
  Future<void> unlock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lockStartTimeKey);
      await prefs.remove(_lockDurationDaysKey);
    } catch (e) {
      print('Error unlocking: $e');
    }
  }

  /// Reset lock status
  Future<void> resetLock() async {
    await unlock();
    await initializeLock();
  }

  /// Get lock status details
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
}
