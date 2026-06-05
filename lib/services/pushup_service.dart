import 'dart:async';
import 'package:flutter/services.dart';
import 'camera_pushup_detector.dart';

enum DetectionMode { proximity, camera }

class PushupService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');
  static const _eventChannel =
      EventChannel('com.example.focus_lock/pushup_events');

  StreamSubscription? _subscription;
  final _controller = StreamController<int>.broadcast();
  int _lastCount = 0;
  DetectionMode _mode = DetectionMode.proximity;

  CameraPushupDetector? _cameraDetector;

  Stream<int> get onCountChanged => _controller.stream;
  int get currentCount => _lastCount;
  DetectionMode get mode => _mode;
  CameraPushupDetector? get cameraDetector => _cameraDetector;

  /// Check if camera-based detection is available on this device
  Future<bool> isCameraAvailable() async {
    try {
      final detector = CameraPushupDetector();
      final available = await detector.initialize();
      await detector.dispose();
      return available;
    } catch (_) {
      return false;
    }
  }

  /// Start pushup detection in the given mode
  Future<bool> start({DetectionMode mode = DetectionMode.proximity}) async {
    _mode = mode;

    if (mode == DetectionMode.camera) {
      return _startCameraDetection();
    }
    return _startProximityDetection();
  }

  Future<bool> _startCameraDetection() async {
    try {
      _cameraDetector?.dispose();
      _cameraDetector = CameraPushupDetector();

      final initialized = await _cameraDetector!.initialize();
      if (!initialized) return false;

      _cameraDetector!.onCountChanged.listen((count) {
        _lastCount = count;
        _controller.add(count);
      });

      _cameraDetector!.startDetection();
      _lastCount = 0;
      return true;
    } catch (e) {
      print('Error starting camera detection: $e');
      return false;
    }
  }

  Future<bool> _startProximityDetection() async {
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

  Future<void> stop() async {
    if (_mode == DetectionMode.camera) {
      _cameraDetector?.stopDetection();
    } else {
      await _subscription?.cancel();
      _subscription = null;
      try {
        await _channel.invokeMethod('stopPushupDetection');
      } catch (e) {
        print('Error stopping pushup detection: $e');
      }
    }
  }

  Future<int> getCount() async {
    if (_mode == DetectionMode.camera) {
      return _cameraDetector?.currentCount ?? _lastCount;
    }
    try {
      final result = await _channel.invokeMethod('getPushupCount');
      _lastCount = (result as int?) ?? 0;
      return _lastCount;
    } catch (e) {
      return _lastCount;
    }
  }

  Future<void> reset() async {
    if (_mode == DetectionMode.camera) {
      _cameraDetector?.reset();
    } else {
      try {
        await _channel.invokeMethod('resetPushupCount');
      } catch (e) {
        print('Error resetting pushup count: $e');
      }
    }
    _lastCount = 0;
    _controller.add(0);
  }

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

  void dispose() {
    _subscription?.cancel();
    _cameraDetector?.dispose();
    _cameraDetector = null;
    _controller.close();
  }
}
