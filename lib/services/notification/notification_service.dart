import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages local notifications for FocusGuard, specifically:
/// - 10-minute access countdown when an app is temporarily unlocked
/// - Blocked app reminder
/// - General status notifications
class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  final _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Platform channel fallback for pre-Android 13 (no notification permission)
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Initializes the notification plugin and creates required notification channels.
  Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('ic_launcher');

    await _flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: androidSettings),
    );

    // Create notification channels
    await _createChannels();
    _isInitialized = true;
    developer.log('NotificationService: initialized');
  }

  /// Creates Android notification channels for different notification types.
  Future<void> _createChannels() async {
    if (!Platform.isAndroid) return;

    const AndroidNotificationChannel mainChannel =
        AndroidNotificationChannel(
      'focus_guard_main', // channel ID
      'FocusGuard', // channel name
      description: 'Status and countdown notifications for blocked apps',
      importance: Importance.max,
      playSound: false,
    );

    final androidNotificationPlugin =
        _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidNotificationPlugin != null) {
      await androidNotificationPlugin.createNotificationChannel(mainChannel);
    }
  }

  /// Shows a persistent notification with a countdown timer.
  ///
  /// Call this every second from a timer to update the countdown.
  Future<void> showCountdownNotification({
    required String appName,
    required int remainingSeconds,
    required String packageName,
  }) async {
    if (!_isInitialized) await initialize();

    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    final timeString = '${_pad(minutes)}:${_pad(seconds)}';

    final androidDetails = AndroidNotificationDetails(
      'focus_guard_main',
      'FocusGuard',
      channelDescription:
          'Shows the remaining time for temporary app access',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
      onlyAlertOnce: true,
      ongoing: true,
      autoCancel: false,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _flutterLocalNotificationsPlugin.show(
      1001, // Unique ID for countdown notification
      'Temporary Access — $appName',
      'Expires in $timeString',
      notificationDetails,
    );
  }

  /// Shows a simple notification indicating a blocked app was opened.
  Future<void> showBlockedAppNotification({required String appName}) async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      'focus_guard_main',
      'FocusGuard',
      channelDescription: 'Notifications when a blocked app is opened',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    await _flutterLocalNotificationsPlugin.show(
      1002,
      'Blocked: $appName',
      'FocusGuard is keeping you focused on what matters.',
      NotificationDetails(android: androidDetails),
    );
  }

  /// Called when the timer expires to replace the countdown.
  Future<void> showTimerExpiredNotification({required String appName}) async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      'focus_guard_main',
      'FocusGuard',
      channelDescription:
          'Notification shown when temporary access expires',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _flutterLocalNotificationsPlugin.show(
      1001, // Reuse countdown ID to replace it
      'Access Expired',
      '$appName access has expired. Blocking resumed.',
      NotificationDetails(android: androidDetails),
    );
  }

  /// Dismisses the countdown notification.
  Future<void> dismissCountdownNotification() async {
    await _flutterLocalNotificationsPlugin.cancel(1001);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}