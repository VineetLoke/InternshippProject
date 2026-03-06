import 'package:flutter/services.dart';

/// Flutter interface to the deterministic Instagram blocker module.
///
/// All state lives in native Kotlin (InstagramBlocker singleton) using
/// a dedicated SharedPreferences file that Flutter's "Reset Focus"
/// flow cannot touch.
class InstagramBlockService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Full status map from the native module.
  ///
  /// Keys: isLocked, isTempUnlockActive, tempUnlockRemainingSeconds,
  ///       remainingDays, attemptCount, lockDurationDays
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getInstagramBlockStatus');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      return {
        'isLocked': false,
        'isTempUnlockActive': false,
        'tempUnlockRemainingSeconds': 0,
        'remainingDays': 0,
        'attemptCount': 0,
        'lockDurationDays': 17,
      };
    }
  }

  /// Total number of blocked Instagram open attempts.
  Future<int> getAttemptCount() async {
    try {
      final result = await _channel.invokeMethod('getInstagramAttemptCount');
      return (result as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Remaining seconds of active temp unlock, or 0.
  Future<int> getTempUnlockRemainingSeconds() async {
    try {
      final result =
          await _channel.invokeMethod('getInstagramTempUnlockRemaining');
      return (result as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Called after the user completes 50 pushups.
  /// Grants exactly 15 minutes of Instagram access.
  Future<bool> completeEmergencyChallenge() async {
    try {
      final result =
          await _channel.invokeMethod('completeInstagramEmergencyChallenge');
      return result == true;
    } catch (e) {
      return false;
    }
  }
}
