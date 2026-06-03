import 'dart:async';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'pushup_counter.dart';

/// Orchestrates the camera + ML Kit pose detection pipeline.
/// Processes camera frames, extracts body landmarks, calculates
/// elbow angles, and drives the PushupCounter state machine.
class CameraPushupDetector {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;
  final PushupCounter _pushupCounter = PushupCounter();

  bool _isProcessing = false;
  bool _isInitialized = false;

  // Callbacks
  Function(int count)? onCountUpdate;
  Function(double angle)? onAngleUpdate;
  Function(String feedback)? onFeedbackUpdate;
  Function(Pose pose)? onPoseDetected;
  Function()? onChallengeComplete;

  final int targetCount;

  CameraPushupDetector({this.targetCount = 10});

  CameraController? get cameraController => _cameraController;
  bool get isInitialized => _isInitialized;
  int get currentCount => _pushupCounter.count;
  PushupCounter get pushupCounter => _pushupCounter;

  /// Initialize front camera and pose detector.
  Future<void> initialize() async {
    // Initialize pose detector
    final options = PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    );
    _poseDetector = PoseDetector(options: options);

    // Get available cameras and select the front camera
    final cameras = await availableCameras();
    CameraDescription? frontCamera;
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        frontCamera = camera;
        break;
      }
    }

    // Fall back to the first available camera if no front camera
    final selectedCamera = frontCamera ?? cameras.first;

    _cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController!.initialize();
    _isInitialized = true;

    // Start processing frames
    _cameraController!.startImageStream(_processCameraImage);
  }

  /// Process each camera frame through ML Kit.
  void _processCameraImage(CameraImage cameraImage) {
    if (_isProcessing) return;
    _isProcessing = true;

    _processFrame(cameraImage).then((_) {
      _isProcessing = false;
    }).catchError((e) {
      _isProcessing = false;
    });
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    if (_poseDetector == null || _cameraController == null) return;

    final inputImage = _convertCameraImage(cameraImage);
    if (inputImage == null) return;

    final poses = await _poseDetector!.processImage(inputImage);
    if (poses.isEmpty) return;

    final pose = poses.first;
    onPoseDetected?.call(pose);

    // Calculate elbow angle using both arms
    final angle = _calculateBestElbowAngle(pose);
    if (angle == null) return;

    onAngleUpdate?.call(angle);

    // Update pushup counter
    final repCompleted = _pushupCounter.update(angle);
    final feedback = _pushupCounter.getFormFeedback(angle);
    onFeedbackUpdate?.call(feedback);

    if (repCompleted) {
      onCountUpdate?.call(_pushupCounter.count);

      // Check if challenge is complete
      if (_pushupCounter.count >= targetCount) {
        onChallengeComplete?.call();
        // Stop processing
        await _cameraController?.stopImageStream();
      }
    }
  }

  /// Convert CameraImage to ML Kit InputImage.
  InputImage? _convertCameraImage(CameraImage cameraImage) {
    final camera = _cameraController!.description;

    // Determine rotation
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation rotation;
    switch (sensorOrientation) {
      case 0:
        rotation = InputImageRotation.rotation0deg;
        break;
      case 90:
        rotation = InputImageRotation.rotation90deg;
        break;
      case 180:
        rotation = InputImageRotation.rotation180deg;
        break;
      case 270:
        rotation = InputImageRotation.rotation270deg;
        break;
      default:
        rotation = InputImageRotation.rotation0deg;
    }

    // For NV21 format (Android)
    if (cameraImage.format.group == ImageFormatGroup.nv21) {
      final bytes = cameraImage.planes.first.bytes;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: ui.Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: cameraImage.planes.first.bytesPerRow,
        ),
      );
    }

    // For YUV420 format
    if (cameraImage.format.group == ImageFormatGroup.yuv420) {
      final allBytes = WriteBuffer();
      for (final plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      return InputImage.fromBytes(
        bytes: allBytes.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: ui.Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: rotation,
          format: InputImageFormat.yuv420,
          bytesPerRow: cameraImage.planes.first.bytesPerRow,
        ),
      );
    }

    return null;
  }

  /// Calculate elbow angle from pose landmarks.
  /// Uses both arms and picks the best (highest confidence) one.
  double? _calculateBestElbowAngle(Pose pose) {
    final landmarks = pose.landmarks;

    double? leftAngle;
    double? rightAngle;
    double leftConfidence = 0;
    double rightConfidence = 0;

    // Left arm: left shoulder → left elbow → left wrist
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];

    if (leftShoulder != null && leftElbow != null && leftWrist != null) {
      final minLikelihood = [
        leftShoulder.likelihood,
        leftElbow.likelihood,
        leftWrist.likelihood,
      ].reduce((a, b) => a < b ? a : b);

      if (minLikelihood > 0.5) {
        leftAngle = PushupCounter.calculateAngle(
          leftShoulder.x, leftShoulder.y,
          leftElbow.x, leftElbow.y,
          leftWrist.x, leftWrist.y,
        );
        leftConfidence = minLikelihood;
      }
    }

    // Right arm: right shoulder → right elbow → right wrist
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];

    if (rightShoulder != null && rightElbow != null && rightWrist != null) {
      final minLikelihood = [
        rightShoulder.likelihood,
        rightElbow.likelihood,
        rightWrist.likelihood,
      ].reduce((a, b) => a < b ? a : b);

      if (minLikelihood > 0.5) {
        rightAngle = PushupCounter.calculateAngle(
          rightShoulder.x, rightShoulder.y,
          rightElbow.x, rightElbow.y,
          rightWrist.x, rightWrist.y,
        );
        rightConfidence = minLikelihood;
      }
    }

    // Average both arms if both are available, else use whichever is available
    if (leftAngle != null && rightAngle != null) {
      return (leftAngle + rightAngle) / 2.0;
    }
    if (leftAngle != null) return leftAngle;
    if (rightAngle != null) return rightAngle;
    return null;
  }

  /// Dispose of camera and pose detector resources.
  Future<void> dispose() async {
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    await _cameraController?.dispose();
    await _poseDetector?.close();
    _cameraController = null;
    _poseDetector = null;
    _isInitialized = false;
  }
}
