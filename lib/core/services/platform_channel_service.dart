import 'package:flutter/services.dart';

/// Singleton wrapper around the native MethodChannel.
/// Provides typed Dart methods for all native Android interactions.
class PlatformChannelService {
  static const _channel = MethodChannel('com.focuslock.app/methods');

  // ─── Accessibility Service ───────────────────────────────────

  /// Returns true if our AccessibilityService is enabled in system settings.
  Future<bool> isAccessibilityEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system Accessibility Settings screen.
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } on PlatformException {
      // Silently handle — user will see the settings didn't open
    }
  }

  // ─── Overlay Permission ──────────────────────────────────────

  /// Returns true if we have the "Draw Over Other Apps" permission.
  Future<bool> canDrawOverlays() async {
    try {
      final result = await _channel.invokeMethod<bool>('canDrawOverlays');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system overlay permission settings for our app.
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException {
      // Silently handle
    }
  }

  // ─── Instagram Blocking ──────────────────────────────────────

  /// Returns true if Instagram blocking is currently enabled.
  Future<bool> isInstagramBlocked() async {
    try {
      final result = await _channel.invokeMethod<bool>('isInstagramBlocked');
      return result ?? true;
    } on PlatformException {
      return true;
    }
  }

  /// Sets whether Instagram should be blocked.
  Future<void> setInstagramBlocked(bool blocked) async {
    try {
      await _channel.invokeMethod('setInstagramBlocked', {'blocked': blocked});
    } on PlatformException {
      // Silently handle
    }
  }

  // ─── Temp Unlock ─────────────────────────────────────────────

  /// Grants a 10-minute temporary unlock window.
  Future<void> grantTempUnlock() async {
    try {
      await _channel.invokeMethod('grantTempUnlock');
    } on PlatformException {
      // Silently handle
    }
  }

  /// Returns the number of seconds remaining in the temp unlock window.
  /// Returns 0 if no active unlock.
  Future<int> getTempUnlockRemaining() async {
    try {
      final result = await _channel.invokeMethod<int>('getTempUnlockRemaining');
      return result ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  // ─── Deep Link / Initial Route ───────────────────────────────

  /// Returns the initial route if the app was opened via deep link.
  /// Returns null if opened normally.
  Future<String?> getInitialRoute() async {
    try {
      final result = await _channel.invokeMethod<String>('getInitialRoute');
      return result;
    } on PlatformException {
      return null;
    }
  }
}
