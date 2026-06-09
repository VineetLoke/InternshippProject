import 'dart:developer' as developer;

/// Stub notification service for FocusGuard.
///
/// The full implementation requires `flutter_local_notifications` which has
/// a compilation bug (`bigLargeIcon` ambiguity) when using compileSdk 35+.
/// This stub keeps the public API alive so `UnlockTimerManager` can still
/// call it; it simply logs instead of showing a real notification.
///
/// Re-enable native notifications by restoring the `flutter_local_notifications`
/// dependency in pubspec.yaml and replacing this stub with the full service.
class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  bool _isInitialized = false;

  /// No-op — kept for API compatibility.
  Future<void> initialize() async {
    _isInitialized = true;
  }

  /// Shows a persistent notification with a countdown timer.
  Future<void> showCountdownNotification({
    required String appName,
    required int remainingSeconds,
    required String packageName,
  }) async {
    // Stub: real implementation would show a native notification.
    developer.log('[NotificationService] Countdown: $remainingSeconds s');
  }

  /// Shows a simple notification indicating a blocked app was opened.
  Future<void> showBlockedAppNotification({required String appName}) async {
    developer.log('[NotificationService] Blocked: $appName');
  }

  /// Called when the timer expires to replace the countdown.
  Future<void> showTimerExpiredNotification({required String appName}) async {
    developer.log('[NotificationService] Expired: $appName');
  }

  /// Dismisses the countdown notification.
  Future<void> dismissCountdownNotification() async {
    // Stub: no-op.
  }
}
