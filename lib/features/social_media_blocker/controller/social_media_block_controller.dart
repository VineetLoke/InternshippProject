import 'dart:async';
import 'package:flutter/services.dart';
import '../model/blocked_app.dart';
import '../model/blocked_app_status.dart';

/// Unified controller that replaces the three flat services
/// (InstagramBlockService, RedditBlockService, TwitterBlockService).
///
/// All state lives in native Kotlin; this thin controller merely
/// marshals calls through MethodChannel.
class SocialMediaBlockController {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  final BlockedApp app;

  SocialMediaBlockController(this.app);

  String get _methodPrefix => app.name[0].toUpperCase() + app.name.substring(1);
  String get _statusMethod => 'get${_methodPrefix}BlockStatus';
  String get _attemptsMethod => 'get${_methodPrefix}AttemptCount';
  String get _unlockRemainingMethod => _getUnlockMethodName();
  String get _completeMethod => 'complete${_methodPrefix}EmergencyChallenge';

  String _getUnlockMethodName() {
    // Reddit has a non-standard method name in Kotlin
    if (app == BlockedApp.reddit) {
      return 'getRedditTempUnlockRemainingNew';
    }
    return 'get${_methodPrefix}TempUnlockRemaining';
  }

  /// Full status map from the native module.
  Future<BlockedAppStatus> getStatus() async {
    try {
      final result = await _channel.invokeMethod(_statusMethod);
      return BlockedAppStatus.fromMap(
        Map<String, dynamic>.from(result as Map),
      );
    } catch (e) {
      return const BlockedAppStatus();
    }
  }

  /// Total number of blocked open attempts.
  Future<int> getAttemptCount() async {
    try {
      final result = await _channel.invokeMethod(_attemptsMethod);
      return (result as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Remaining seconds of active temp unlock, or 0.
  Future<int> getTempUnlockRemainingSeconds() async {
    try {
      final result = await _channel.invokeMethod(_unlockRemainingMethod);
      return (result as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Called after the user completes the pushup challenge.
  /// Grants temporary access for the configured duration.
  Future<bool> completeEmergencyChallenge() async {
    try {
      final result = await _channel.invokeMethod(_completeMethod);
      return result == true;
    } catch (e) {
      return false;
    }
  }
}

/// Convenience factory for all three apps.
class SocialMediaBlockers {
  // Names intentionally match the native blocker classes.
  // ignore: non_constant_identifier_names
  static SocialMediaBlockController InstagramBlocker() =>
      SocialMediaBlockController(BlockedApp.instagram);
  // ignore: non_constant_identifier_names
  static SocialMediaBlockController RedditBlocker() =>
      SocialMediaBlockController(BlockedApp.reddit);
  // ignore: non_constant_identifier_names
  static SocialMediaBlockController TwitterBlocker() =>
      SocialMediaBlockController(BlockedApp.twitter);
}
