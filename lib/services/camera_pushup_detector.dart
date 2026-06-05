import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum RepState { idle, goingDown, bottom, goingUp }

class CameraPushupDetector {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;
  StreamSubscription? _imageStreamSub;

  final _countController = StreamController<int>.broadcast();
  Stream<int> get onCountChanged => _countController.stream;

  int _count = 0;
  bool _isRunning = false;
  bool _isInitialized = false;

  RepState _repState = RepState.idle;
  static const double _downThreshold = 80.0;
  static const double _upThreshold = 150.0;

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

    _imageStreamSub = _cameraController!.startImageStream(_processImage);
    debugPrint('CameraPushupDetector: detection started');
  }

  void _processImage(CameraImage image) {
    if (_poseDetector == null) return;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      _poseDetector!.processImage(inputImage).then((poses) {
        if (poses.isNotEmpty) {
          _processPose(poses.first);
        }
      }).catchError((_) {});
    } catch (_) {}
  }

  InputImage? _buildInputImage(CameraImage image) {
    final camera = _cameraController?.description;
    if (camera == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    final isFrontCamera = camera.lensDirection == CameraLensDirection.front;
    final rotation = _rotation(
      isFrontCamera ? (360 - sensorOrientation) % 360 : sensorOrientation,
    );

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
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

    if (leftShoulder != null && leftElbow != null && leftWrist != null &&
        leftShoulder.inFrameLikelihood > 0.5 &&
        leftElbow.inFrameLikelihood > 0.5) {
      angle = _calculateAngle(leftShoulder, leftElbow, leftWrist);
      detected = true;
    } else if (rightShoulder != null && rightElbow != null &&
        rightWrist != null &&
        rightShoulder.inFrameLikelihood > 0.5 &&
        rightElbow.inFrameLikelihood > 0.5) {
      angle = _calculateAngle(rightShoulder, rightElbow, rightWrist);
      detected = true;
    }

    if (detected) _updateRepState(angle);
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
    _imageStreamSub?.cancel();
    _imageStreamSub = null;
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
