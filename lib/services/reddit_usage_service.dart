import 'package:flutter/services.dart';

/// Manages Reddit daily usage limit (1 hour) and pushup-based extra time.
class RedditUsageService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Returns the current Reddit usage status from native code.
  ///
  /// Keys: usedSeconds, limitSeconds, remainingSeconds, isLimitReached,
  ///       extraMinutesEarned
  Future<Map<String, dynamic>> getUsageStatus() async {
    try {
      final result = await _channel.invokeMethod('getRedditUsageStatus');
      return Map<String, dynamic>.from(result);
    } catch (e) {
      print('Error getting Reddit usage status: $e');
      return {
        'usedSeconds': 0,
        'limitSeconds': 3600,
        'remainingSeconds': 3600,
        'isLimitReached': false,
        'extraMinutesEarned': 0,
      };
    }
  }

  /// Remaining Reddit time today in seconds.
  Future<int> getRemainingSeconds() async {
    try {
      final result = await _channel.invokeMethod('getRedditRemainingSeconds');
      return (result as int?) ?? 3600;
    } catch (e) {
      print('Error getting remaining seconds: $e');
      return 3600;
    }
  }

  /// Whether the daily Reddit limit has been reached.
  Future<bool> isLimitReached() async {
    final status = await getUsageStatus();
    return status['isLimitReached'] == true;
  }

  /// Remaining seconds on the 10-minute temp unlock (0 if not active).
  Future<int> getTempUnlockRemainingSeconds() async {
    try {
      final result =
          await _channel.invokeMethod('getRedditTempUnlockRemaining');
      return (result as int?) ?? 0;
    } catch (e) {
      print('Error getting temp unlock remaining: $e');
      return 0;
    }
  }

  /// Get the current discipline state machine state.
  Future<String> getDisciplineState() async {
    try {
      final result = await _channel.invokeMethod('getDisciplineState');
      return (result as String?) ?? 'IDLE';
    } catch (e) {
      print('Error getting discipline state: $e');
      return 'IDLE';
    }
  }

  /// Format seconds into "Xh Ym Zs" string.
  static String formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0s';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
