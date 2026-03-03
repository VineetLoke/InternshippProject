import 'dart:async';
import 'package:flutter/services.dart';

/// Flutter interface to the native proximity-sensor-based pushup detector.
///
/// Usage:
///   final service = PushupService();
///   service.onCountChanged.listen((count) => setState(() => _count = count));
///   await service.start();
///   // ... user does pushups ...
///   final redeemed = await service.redeemForRedditTime();
///   await service.stop();
class PushupService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');
  static const _eventChannel =
      EventChannel('com.example.focus_lock/pushup_events');

  StreamSubscription? _subscription;
  final _controller = StreamController<int>.broadcast();
  int _lastCount = 0;

  /// Live stream of pushup count updates.
  Stream<int> get onCountChanged => _controller.stream;

  /// Current pushup count.
  int get currentCount => _lastCount;

  /// Start the proximity-sensor pushup detector.
  /// Returns false if the device has no proximity sensor.
  Future<bool> start() async {
    try {
      final result = await _channel.invokeMethod('startPushupDetection');
      if (result == true) {
        _subscription = _eventChannel
            .receiveBroadcastStream()
            .listen((dynamic event) {
          final count = event as int;
          _lastCount = count;
          _controller.add(count);
        }, onError: (dynamic error) {
          print('Pushup event error: $error');
        });
        return true;
      }
      return false;
    } catch (e) {
      print('Error starting pushup detection: $e');
      return false;
    }
  }

  /// Stop the pushup detector and release sensor resources.
  Future<void> stop() async {
    try {
      await _subscription?.cancel();
      _subscription = null;
      await _channel.invokeMethod('stopPushupDetection');
    } catch (e) {
      print('Error stopping pushup detection: $e');
    }
  }

  /// Get the current count from native (in case the stream missed events).
  Future<int> getCount() async {
    try {
      final result = await _channel.invokeMethod('getPushupCount');
      _lastCount = (result as int?) ?? 0;
      return _lastCount;
    } catch (e) {
      return _lastCount;
    }
  }

  /// Reset the counter to zero.
  Future<void> reset() async {
    try {
      await _channel.invokeMethod('resetPushupCount');
      _lastCount = 0;
      _controller.add(0);
    } catch (e) {
      print('Error resetting pushup count: $e');
    }
  }

  /// Attempt to redeem 100 pushups for 10 minutes of Reddit time.
  /// Returns true if successful (count ≥ 100).
  Future<bool> redeemForRedditTime() async {
    try {
      final result = await _channel.invokeMethod('redeemPushups');
      if (result == true) {
        _lastCount = 0;
        _controller.add(0);
        return true;
      }
      return false;
    } catch (e) {
      print('Error redeeming pushups: $e');
      return false;
    }
  }

  /// Clean up resources.
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
