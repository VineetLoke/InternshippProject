import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

typedef TimerCallback = void Function(Duration);

class TimerService {
  static const String _emergencyUnlockRequestKey = 'emergency_unlock_requested_at';
  static const Duration _delayPeriod = Duration(hours: 1);

  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;
  TimerCallback? _onTick;

  /// Request emergency unlock (starts 1-hour delay)
  Future<bool> requestEmergencyUnlock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString(
        _emergencyUnlockRequestKey,
        now.toIso8601String(),
      );
      return true;
    } catch (e) {
      print('Error requesting emergency unlock: $e');
      return false;
    }
  }

  /// Check if emergency unlock request is valid (delay passed)
  Future<bool> isEmergencyUnlockDelayComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final requestTimeStr = prefs.getString(_emergencyUnlockRequestKey);
      
      if (requestTimeStr == null) return false;
      
      final requestTime = DateTime.parse(requestTimeStr);
      final now = DateTime.now();
      final elapsed = now.difference(requestTime);
      
      return elapsed >= _delayPeriod;
    } catch (e) {
      print('Error checking delay status: $e');
      return false;
    }
  }

  /// Get remaining time for emergency unlock
  Future<Duration> getRemainingTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final requestTimeStr = prefs.getString(_emergencyUnlockRequestKey);
      
      if (requestTimeStr == null) {
        return Duration.zero;
      }
      
      final requestTime = DateTime.parse(requestTimeStr);
      final now = DateTime.now();
      final elapsed = now.difference(requestTime);
      final remaining = _delayPeriod - elapsed;
      
      return remaining.isNegative ? Duration.zero : remaining;
    } catch (e) {
      print('Error getting remaining time: $e');
      return Duration.zero;
    }
  }

  /// Start countdown timer with callback
  void startCountdown(TimerCallback onTick) {
    _onTick = onTick;
    _countdownTimer?.cancel();
    
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      _remainingTime = await getRemainingTime();
      _onTick?.call(_remainingTime);
      
      if (_remainingTime.inSeconds <= 0) {
        timer.cancel();
      }
    });
  }

  /// Stop countdown timer
  void stopCountdown() {
    _countdownTimer?.cancel();
  }

  /// Cancel emergency unlock request
  Future<void> cancelEmergencyUnlock() async {
    try {
      stopCountdown();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_emergencyUnlockRequestKey);
    } catch (e) {
      print('Error cancelling emergency unlock: $e');
    }
  }

  /// Format duration as HH:MM:SS
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
