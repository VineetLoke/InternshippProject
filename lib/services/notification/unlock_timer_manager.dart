import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'notification_service.dart';

/// Manages countdown timers for temporary app unlocks.
///
/// Polls the native blockers (Instagram, Reddit, Twitter/X) for active
/// temp unlocks and updates a persistent notification every second.
class UnlockTimerManager {
  UnlockTimerManager._();
  static final UnlockTimerManager _instance = UnlockTimerManager._();
  static UnlockTimerManager get instance => _instance;

  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  Timer? _timer;

  /// Track the currently active unlock: packageName → expiry timestamp
  final Map<String, DateTime> _activeUnlocks = {};

  /// Start monitoring all blockers for temp unlocks.
  /// Call once during app startup.
  void startMonitoring() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    developer.log('UnlockTimerManager: started monitoring');
  }

  /// Stop all timers and clear state.
  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    _activeUnlocks.clear();
    NotificationService.instance.dismissCountdownNotification();
    developer.log('UnlockTimerManager: stopped monitoring');
  }

  /// Check native blockers and update notification state.
  Future<void> _tick() async {
    try {
      final statuses = await _fetchUnlockStatuses();
      final now = DateTime.now();

      // Update active unlocks map
      _activeUnlocks.clear();
      for (final entry in statuses.entries) {
        final remaining = (entry.value['remainingSeconds'] ?? 0) as int;
        if (remaining > 0) {
          _activeUnlocks[entry.key] = now.add(Duration(seconds: remaining));
        }
      }

      if (_activeUnlocks.isEmpty) {
        // No active unlocks — dismiss notification if it was showing
        await NotificationService.instance.dismissCountdownNotification();
        return;
      }

      // Find the unlock with the most remaining time to display
      final latest = _activeUnlocks.entries.reduce((a, b) =>
          a.value.isAfter(b.value) ? a : b,
        );
      final remaining = latest.value.difference(now).inSeconds;
      final appName = _packageToName(latest.key);

      if (remaining > 0) {
        await NotificationService.instance.showCountdownNotification(
          appName: appName,
          remainingSeconds: remaining,
          packageName: latest.key,
        );
      } else {
        // Expired — show expiry notification and remove
        await NotificationService.instance.showTimerExpiredNotification(
          appName: appName,
        );
        _activeUnlocks.remove(latest.key);
      }
    } catch (e) {
      developer.log('UnlockTimerManager: tick error: $e');
    }
  }

  /// Fetch temp unlock status from all three native blockers.
  Future<Map<String, Map<String, dynamic>>> _fetchUnlockStatuses() async {
    final results = <String, Map<String, dynamic>>{};

    // Instagram
    try {
      final result = await _channel.invokeMethod('getInstagramBlockStatus');
      results['com.instagram.android'] =
          Map<String, dynamic>.from(result as Map);
    } catch (_) {}

    // Reddit
    try {
      final result = await _channel.invokeMethod('getRedditBlockStatus');
      results['com.reddit.frontpage'] = Map<String, dynamic>.from(result as Map);
    } catch (_) {}

    // Twitter/X
    try {
      final result = await _channel.invokeMethod('getTwitterBlockStatus');
      results['com.twitter.android'] = Map<String, dynamic>.from(result as Map);
    } catch (_) {}

    return results;
  }

  String _packageToName(String pkg) {
    switch (pkg) {
      case 'com.instagram.android':
        return 'Instagram';
      case 'com.reddit.frontpage':
        return 'Reddit';
      case 'com.twitter.android':
        return 'Twitter/X';
      default:
        return pkg;
    }
  }
}
