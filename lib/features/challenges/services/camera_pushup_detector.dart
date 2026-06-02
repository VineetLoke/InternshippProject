import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'pushup_counter.dart';

class CameraPushupDetector {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;
  final PushupCounter _pushupCounter = PushupCounter();
  bool _isProcessing = false;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;

  // Callbacks
  Function(int count)? onCountUpdate;
  Function(Pose pose)? onPoseDetected;
  Function(double angle)? onAngleUpdate;
  Function(String feedback)? onFeedbackUpdate;

  int get pushupCount => _pushupCounter.count;
  CameraController? get cameraController => _cameraController;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    // Try to get front camera
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );

    _isInitialized = true;
  }

  void startDetection() {
    if (!_isInitialized || _cameraController == null) return;

    _cameraController!.startImageStream((CameraImage image) {
      if (_isProcessing) return;
      _isProcessing = true;
      _processFrame(image);
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final poses = await _poseDetector!.processImage(inputImage);
      if (poses.isEmpty) {
        onFeedbackUpdate?.call("Position your full body in the frame");
        _isProcessing = false;
        return;
      }

      final pose = poses.first;
      onPoseDetected?.call(pose);

      final leftAngle = _getElbowAngle(pose, isLeft: true);
      final rightAngle = _getElbowAngle(pose, isLeft: false);

      double? elbowAngle;
      if (leftAngle != null && rightAngle != null) {
        elbowAngle = (leftAngle + rightAngle) / 2;
      } else {
        elbowAngle = leftAngle ?? rightAngle;
      }

      if (elbowAngle != null) {
        onAngleUpdate?.call(elbowAngle);
        
        // Count update
        final newRep = _pushupCounter.update(elbowAngle);
        if (newRep) {
          onCountUpdate?.call(_pushupCounter.count);
        }

        // Feedback generation
        if (_pushupCounter.state == PushupState.up) {
          if (elbowAngle > 140) {
            onFeedbackUpdate?.call("Go down!");
          } else {
            onFeedbackUpdate?.call("Keep descending!");
          }
        } else {
          if (elbowAngle < 100) {
            onFeedbackUpdate?.call("Push up!");
          } else {
            onFeedbackUpdate?.call("Power up!");
          }
        }
      } else {
        onFeedbackUpdate?.call("Elbows not clearly visible");
      }
    } catch (e) {
      debugPrint('Pose detection error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  double? _getElbowAngle(Pose pose, {required bool isLeft}) {
    final shoulder = pose.landmarks[
      isLeft ? PoseLandmarkType.leftShoulder : PoseLandmarkType.rightShoulder
    ];
    final elbow = pose.landmarks[
      isLeft ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow
    ];
    final wrist = pose.landmarks[
      isLeft ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist
    ];

    if (shoulder == null || elbow == null || wrist == null) return null;

    if (shoulder.likelihood < 0.5 ||
        elbow.likelihood < 0.5 ||
        wrist.likelihood < 0.5) {
      return null;
    }

    return _calculateAngle(
      Point(shoulder.x, shoulder.y),
      Point(elbow.x, elbow.y),
      Point(wrist.x, wrist.y),
    );
  }

  double _calculateAngle(Point<double> a, Point<double> b, Point<double> c) {
    double radians = (atan2(c.y - b.y, c.x - b.x) -
                      atan2(a.y - b.y, a.x - b.x)).abs();
    double angle = radians * 180 / pi;
    if (angle > 180) angle = 360 - angle;
    return angle;
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraController == null) return null;
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isAndroid) {
      var rotationCompensation = {
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      }[_cameraController!.value.deviceOrientation] ?? 0;

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    } else if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  void stopDetection() {
    _cameraController?.stopImageStream();
  }

  Future<void> dispose() async {
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
    await _cameraController?.dispose();
    await _poseDetector?.close();
    _isInitialized = false;
  }
}
