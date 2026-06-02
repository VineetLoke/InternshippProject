import 'package:flutter/services.dart';

class PlatformChannelService {
  static const MethodChannel _channel = MethodChannel('com.focuslock.app/methods');

  // Private constructor
  PlatformChannelService._privateConstructor();
  static final PlatformChannelService instance = PlatformChannelService._privateConstructor();

  Future<bool> isAccessibilityEnabled() async {
    try {
      final bool enabled = await _channel.invokeMethod('isAccessibilityEnabled');
      return enabled;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (_) {
      // Handle error or ignore
    }
  }

  Future<bool> canDrawOverlays() async {
    try {
      final bool allowed = await _channel.invokeMethod('canDrawOverlays');
      return allowed;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (_) {
      // Handle error or ignore
    }
  }

  Future<bool> isInstagramBlocked() async {
    try {
      final bool blocked = await _channel.invokeMethod('isInstagramBlocked');
      return blocked;
    } on PlatformException catch (_) {
      return true;
    }
  }

  Future<void> setInstagramBlocked(bool blocked) async {
    try {
      await _channel.invokeMethod('setInstagramBlocked', {'blocked': blocked});
    } on PlatformException catch (_) {
      // Handle error or ignore
    }
  }

  Future<void> grantTempUnlock() async {
    try {
      await _channel.invokeMethod('grantTempUnlock');
    } on PlatformException catch (_) {
      // Handle error or ignore
    }
  }

  Future<int> getTempUnlockRemaining() async {
    try {
      final int remaining = await _channel.invokeMethod('getTempUnlockRemaining');
      return remaining;
    } on PlatformException catch (_) {
      return 0;
    }
  }

  Future<void> openPushupChallenge() async {
    try {
      await _channel.invokeMethod('openPushupChallenge');
    } on PlatformException catch (_) {
      // Handle error or ignore
    }
  }

  // Method to listen to callbacks from Kotlin (e.g. navigation requests)
  void setupMethodCallHandler(Future<dynamic> Function(MethodCall call) handler) {
    _channel.setMethodCallHandler(handler);
  }
}
