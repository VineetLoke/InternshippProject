import 'package:flutter/services.dart';

/// Flutter interface to the deterministic Twitter/X blocker module.
///
/// All state lives in native Kotlin (TwitterBlocker singleton) using
/// a dedicated SharedPreferences file that Flutter's "Reset Focus"
/// flow cannot touch.
class TwitterBlockService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getTwitterBlockStatus');
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

  Future<int> getAttemptCount() async {
    try {
      final result = await _channel.invokeMethod('getTwitterAttemptCount');
      return (result as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getTempUnlockRemainingSeconds() async {
    try {
      final result =
          await _channel.invokeMethod('getTwitterTempUnlockRemaining');
      return (result as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> completeEmergencyChallenge() async {
    try {
      final result =
          await _channel.invokeMethod('completeTwitterEmergencyChallenge');
      return result == true;
    } catch (e) {
      return false;
    }
  }
}
