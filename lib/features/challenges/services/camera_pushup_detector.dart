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
  bool _isPoseVisible = false;
  int _framesProcessed = 0;
  int _posesDetected = 0;
  String? _lastError;

  // Callbacks
  Function(int count)? onCountUpdate;
  Function(double angle)? onAngleUpdate;
  Function(String feedback)? onFeedbackUpdate;
  Function(Pose pose)? onPoseDetected;
  Function()? onChallengeComplete;
  Function(bool visible)? onPoseVisibilityChanged;
  Function(String error)? onError;
  Function(int framesProcessed, int posesDetected)? onDebugInfo;

  final int targetCount;

  /// Minimum confidence for a landmark to be considered valid.
  /// Lowered from 0.5 to 0.3 because pushup positions (far, angled)
  /// often produce lower confidence scores.
  static const double _minConfidence = 0.3;

  CameraPushupDetector({this.targetCount = 10});

  CameraController? get cameraController => _cameraController;
  bool get isInitialized => _isInitialized;
  bool get isPoseVisible => _isPoseVisible;
  int get currentCount => _pushupCounter.count;
  PushupCounter get pushupCounter => _pushupCounter;

  /// Initialize camera and pose detector.
  /// Tries front camera first, falls back to back camera.
  Future<void> initialize() async {
    // Initialize pose detector
    final options = PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    );
    _poseDetector = PoseDetector(options: options);

    // Get available cameras
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No cameras available on this device');
    }

    // Prefer front camera for pushup selfie view
    CameraDescription? selectedCamera;
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        selectedCamera = camera;
        break;
      }
    }
    // Fall back to back camera
    selectedCamera ??= cameras.first;

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
    }).catchError((dynamic e) {
      _isProcessing = false;
      final errorMsg = 'Frame processing error: $e';
      if (_lastError != errorMsg) {
        _lastError = errorMsg;
        onError?.call(errorMsg);
      }
    });
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    if (_poseDetector == null || _cameraController == null) return;

    final inputImage = _convertCameraImage(cameraImage);
    if (inputImage == null) {
      // Only report this error once
      if (_framesProcessed == 0) {
        onError?.call(
          'Cannot convert camera format: ${cameraImage.format.group}. '
          'Planes: ${cameraImage.planes.length}, '
          'Size: ${cameraImage.width}x${cameraImage.height}'
        );
      }
      _framesProcessed++;
      return;
    }

    _framesProcessed++;

    List<Pose> poses;
    try {
      poses = await _poseDetector!.processImage(inputImage);
    } catch (e) {
      onError?.call('ML Kit error: $e');
      return;
    }

    // Update debug info every 30 frames
    if (_framesProcessed % 30 == 0) {
      onDebugInfo?.call(_framesProcessed, _posesDetected);
    }

    if (poses.isEmpty) {
      // Signal that no pose is visible
      if (_isPoseVisible) {
        _isPoseVisible = false;
        onPoseVisibilityChanged?.call(false);
        onFeedbackUpdate?.call('No body detected — show your side profile 📐');
      }
      return;
    }

    _posesDetected++;
    final pose = poses.first;

    // Signal pose is now visible
    if (!_isPoseVisible) {
      _isPoseVisible = true;
      onPoseVisibilityChanged?.call(true);
    }

    onPoseDetected?.call(pose);

    // Calculate elbow angle using both arms
    final angle = _calculateBestElbowAngle(pose);
    if (angle == null) {
      onFeedbackUpdate?.call('Arms not visible — adjust position 🔄');
      return;
    }

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
        try {
          await _cameraController?.stopImageStream();
        } catch (_) {}
      }
    }
  }

  /// Convert CameraImage to ML Kit InputImage.
  InputImage? _convertCameraImage(CameraImage cameraImage) {
    final camera = _cameraController!.description;

    // Determine rotation based on sensor orientation
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

    // For NV21 format (Android default)
    if (cameraImage.format.group == ImageFormatGroup.nv21) {
      final plane = cameraImage.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: ui.Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // For YUV420 format (some Android devices)
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

    // For BGRA8888 format (iOS, shouldn't happen on Android but just in case)
    if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      final plane = cameraImage.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: ui.Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    return null;
  }

  /// Calculate elbow angle from pose landmarks.
  /// Uses both arms and picks the best (highest confidence) one.
  /// Returns the average if both are available.
  double? _calculateBestElbowAngle(Pose pose) {
    final landmarks = pose.landmarks;

    double? leftAngle;
    double? rightAngle;

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

      if (minLikelihood > _minConfidence) {
        leftAngle = PushupCounter.calculateAngle(
          leftShoulder.x, leftShoulder.y,
          leftElbow.x, leftElbow.y,
          leftWrist.x, leftWrist.y,
        );
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

      if (minLikelihood > _minConfidence) {
        rightAngle = PushupCounter.calculateAngle(
          rightShoulder.x, rightShoulder.y,
          rightElbow.x, rightElbow.y,
          rightWrist.x, rightWrist.y,
        );
      }
    }

    // Average both arms if both are available
    if (leftAngle != null && rightAngle != null) {
      return (leftAngle + rightAngle) / 2.0;
    }
    return leftAngle ?? rightAngle;
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
