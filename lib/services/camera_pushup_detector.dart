import 'dart:async';
import 'dart:math';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum RepState { idle, goingDown, bottom, goingUp }

class CameraPushupDetector {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;

  final _countController = StreamController<int>.broadcast();
  Stream<int> get onCountChanged => _countController.stream;

  int _count = 0;
  bool _isRunning = false;
  bool _isInitialized = false;
  bool _isProcessing = false;

  RepState _repState = RepState.idle;
  static const double _downThreshold = 80.0;
  static const double _upThreshold = 150.0;
  static const double _minConfidence = 0.5;

  CameraController? get cameraController => _cameraController;
  int get currentCount => _count;
  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
        ),
      );
      _isInitialized = true;
      debugPrint('CameraPushupDetector: initialized');
      return true;
    } catch (e) {
      debugPrint('CameraPushupDetector: init error — $e');
      return false;
    }
  }

  void startDetection() {
    if (!_isInitialized || _cameraController == null) return;
    if (_isRunning) return;
    _isRunning = true;

    _cameraController!.startImageStream(_processImage);
    debugPrint('CameraPushupDetector: detection started');
  }

  void _processImage(CameraImage image) {
    if (_poseDetector == null || _isProcessing) return;
    _isProcessing = true;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      _poseDetector!.processImage(inputImage).then((poses) {
        if (poses.isNotEmpty) {
          _processPose(poses.first);
        }
        _isProcessing = false;
      }).catchError((_) {
        _isProcessing = false;
      });
    } catch (_) {
      _isProcessing = false;
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    final camera = _cameraController?.description;
    if (camera == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    final isFrontCamera = camera.lensDirection == CameraLensDirection.front;
    final rotation = _rotation(
      isFrontCamera ? (360 - sensorOrientation) % 360 : sensorOrientation,
    );

    // Concatenate ALL planes into one NV21 byte array.
    // planes[0] = Y (luminance), planes[1] = VU interleaved (chroma).
    // Using only planes[0].bytes (Y plane) would make ML Kit fail to detect poses.
    Uint8List fullBytes;
    if (image.planes.length >= 2) {
      final yPlane = image.planes[0];
      final vuPlane = image.planes[1];
      if (yPlane.bytesPerRow == image.width &&
          vuPlane.bytesPerRow == image.width) {
        fullBytes = Uint8List.fromList([...yPlane.bytes, ...vuPlane.bytes]);
      } else {
        // Handle stride mismatch: copy row by row
        final ySize = image.width * image.height;
        final uvSize = image.width * image.height ~/ 2;
        fullBytes = Uint8List(ySize + uvSize);
        int destIdx = 0;
        for (int row = 0; row < image.height; row++) {
          final srcStart = row * yPlane.bytesPerRow;
          fullBytes.setRange(destIdx, destIdx + image.width,
              yPlane.bytes.sublist(srcStart, srcStart + image.width));
          destIdx += image.width;
        }
        for (int row = 0; row < image.height ~/ 2; row++) {
          final srcStart = row * vuPlane.bytesPerRow;
          fullBytes.setRange(destIdx, destIdx + image.width,
              vuPlane.bytes.sublist(srcStart, srcStart + image.width));
          destIdx += image.width;
        }
      }
    } else {
      fullBytes = image.planes[0].bytes;
    }

    return InputImage.fromBytes(
      bytes: fullBytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

  InputImageRotation _rotation(int degrees) {
    switch (degrees) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  void _processPose(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    double angle = 0;
    bool detected = false;

    // Check for arm with highest average confidence
    if (_hasConfidentLandmarks(leftShoulder, leftElbow, leftWrist)) {
      angle = _calculateAngle(leftShoulder!, leftElbow!, leftWrist!);
      detected = true;
    } else if (_hasConfidentLandmarks(rightShoulder, rightElbow, rightWrist)) {
      angle = _calculateAngle(rightShoulder!, rightElbow!, rightWrist!);
      detected = true;
    } else if (leftShoulder != null && leftElbow != null && leftWrist != null) {
      angle = _calculateAngle(leftShoulder, leftElbow, leftWrist);
      detected = true;
    } else if (rightShoulder != null && rightElbow != null &&
        rightWrist != null) {
      angle = _calculateAngle(rightShoulder, rightElbow, rightWrist);
      detected = true;
    }

    if (detected) {
      debugPrint('CameraPushup: angle=$angle, state=$_repState, count=$_count');
      _updateRepState(angle);
    }
  }

  bool _hasConfidentLandmarks(PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) {
    if (a == null || b == null || c == null) return false;
    return a.likelihood >= _minConfidence &&
           b.likelihood >= _minConfidence &&
           c.likelihood >= _minConfidence;
  }

  double _calculateAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final angle = atan2(c.y - b.y, c.x - b.x) -
        atan2(a.y - b.y, a.x - b.x);
    var result = (angle * 180 / pi).abs();
    if (result > 180) result = 360 - result;
    return result;
  }

  void _updateRepState(double angle) {
    switch (_repState) {
      case RepState.idle:
        if (angle > _upThreshold) _repState = RepState.goingDown;
      case RepState.goingDown:
        if (angle < _downThreshold) _repState = RepState.bottom;
      case RepState.bottom:
        if (angle > _downThreshold) _repState = RepState.goingUp;
      case RepState.goingUp:
        if (angle > _upThreshold) {
          _count++;
          _countController.add(_count);
          _repState = RepState.goingDown;
        }
    }
  }

  void reset() {
    _count = 0;
    _repState = RepState.idle;
    _countController.add(0);
  }

  void stopDetection() {
    _isRunning = false;
    _isProcessing = false;
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
  }

  Future<void> dispose() async {
    stopDetection();
    await _poseDetector?.close();
    _poseDetector = null;
    await _cameraController?.dispose();
    _cameraController = null;
    _isInitialized = false;
    await _countController.close();
  }
}
