import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class AppBlockService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Initialize lock with default 30-day duration
  Future<bool> initializeLock() async {
    try {
      // Native code creates the lock only once and owns its lifecycle.
      await _channel.invokeMethod('startBlocking');
      return true;
    } catch (e) {
      debugPrint('Error initializing lock: $e');
      return false;
    }
  }

  /// Check if Instagram is currently locked
  Future<bool> isLocked() async {
    try {
      final status = await _channel.invokeMethod('getNativeLockStatus');
      return (status as Map)['locked'] == true;
    } catch (e) {
      debugPrint('Error checking lock status: $e');
      return false;
    }
  }

  /// Get remaining days until unlock
  Future<int> getRemainingDays() async {
    try {
      final status = await _channel.invokeMethod('getNativeLockStatus');
      return ((status as Map)['remainingDays'] as int?) ?? 0;
    } catch (e) {
      debugPrint('Error getting remaining days: $e');
      return 0;
    }
  }

  /// Get lock end date
  Future<DateTime?> getLockEndDate() async {
    try {
      return null; // Native state intentionally does not expose a mutable date.
    } catch (e) {
      debugPrint('Error getting lock end date: $e');
      return null;
    }
  }

  /// Flutter has no authority to clear the native lock.
  Future<void> unlock() async {
    debugPrint('Ignoring Flutter unlock request; native lock is authoritative.');
  }

  /// Re-checks native state; reset is deliberately unsupported.
  Future<void> resetLock() async {
    await getLockStatus();
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
