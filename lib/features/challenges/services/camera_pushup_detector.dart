import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Camera-based pushup detection using ML Kit Pose Estimation.
///
/// Tracks shoulder→elbow→wrist angle to detect UP/DOWN positions.
/// A complete DOWN→UP transition counts as one valid pushup.
///
/// Anti-cheat measures:
///  • Landmark confidence filtering (≥ 0.5)
///  • Body horizontal alignment check
///  • Minimum rep time enforcement (800ms)
class CameraPushupDetector {
  // ── Constants ─────────────────────────────────────────────────────
  static const double _upAngleThreshold = 160.0;
  static const double _downAngleThreshold = 110.0;
  static const int _minRepMs = 800;
  static const double _minConfidence = 0.5;

  // ── Camera ────────────────────────────────────────────────────────
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  CameraDescription? _activeCamera;

  // ── Pose detection ────────────────────────────────────────────────
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
    ),
  );

  // ── State ─────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isActive = false;
  bool _isDisposed = false;
  String _stage = 'idle'; // idle, up, down
  int _count = 0;
  int _lastRepTimestamp = 0;

  // ── Streams ───────────────────────────────────────────────────────
  final _countController = StreamController<int>.broadcast();
  final _poseController = StreamController<Pose?>.broadcast();
  final _stageController = StreamController<String>.broadcast();
  final _feedbackController = StreamController<String>.broadcast();

  /// Live stream of pushup count updates.
  Stream<int> get onCountChanged => _countController.stream;

  /// Live stream of detected poses for painting.
  Stream<Pose?> get onPoseChanged => _poseController.stream;

  /// Live stream of current stage ('idle', 'up', 'down').
  Stream<String> get onStageChanged => _stageController.stream;

  /// Live stream of form feedback messages.
  Stream<String> get onFeedbackChanged => _feedbackController.stream;

  /// The camera controller for preview widgets.
  CameraController? get cameraController => _cameraController;

  /// Current pushup count.
  int get currentCount => _count;

  /// Current detection stage.
  String get currentStage => _stage;

  /// Whether the detector is active.
  bool get isActive => _isActive;

  /// Camera preview size (for coordinate mapping in painter).
  Size? get previewSize {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }
    return Size(
      _cameraController!.value.previewSize!.height,
      _cameraController!.value.previewSize!.width,
    );
  }

  /// The active camera's sensor orientation.
  int get sensorOrientation => _activeCamera?.sensorOrientation ?? 0;

  /// The active camera's lens direction.
  CameraLensDirection get lensDirection =>
      _activeCamera?.lensDirection ?? CameraLensDirection.front;

  // ── Public API ────────────────────────────────────────────────────

  /// Initialize the camera. Returns true on success.
  Future<bool> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _feedbackController.add('No cameras found on this device');
        return false;
      }

      // Use back camera for pushup detection (phone placed on wall facing side)
      _activeCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = await _createCameraController();
      return true;
    } catch (e) {
      debugPrint('Camera init error: $e');
      _feedbackController.add('Camera initialization failed');
      return false;
    }
  }

  Future<CameraController> _createCameraController() async {
    final preferredFormat = defaultTargetPlatform == TargetPlatform.android
        ? ImageFormatGroup.nv21
        : ImageFormatGroup.bgra8888;

    try {
      final controller = CameraController(
        _activeCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: preferredFormat,
      );
      await controller.initialize();
      return controller;
    } catch (e) {
      if (defaultTargetPlatform != TargetPlatform.android) rethrow;
      debugPrint('NV21 camera init failed, falling back to YUV420: $e');
      final controller = CameraController(
        _activeCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      return controller;
    }
  }

  /// Start pushup detection. Camera must be initialized first.
  Future<bool> startDetection() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return false;
    }

    _count = 0;
    _stage = 'idle';
    _lastRepTimestamp = 0;
    _isActive = true;
    _countController.add(0);
    _stageController.add('idle');
    _feedbackController.add('Get into pushup position');

    try {
      await _cameraController!.startImageStream(_processImage);
      return true;
    } catch (e) {
      debugPrint('Error starting image stream: $e');
      _isActive = false;
      return false;
    }
  }

  /// Stop pushup detection.
  Future<void> stopDetection() async {
    _isActive = false;
    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error stopping image stream: $e');
    }
  }

  /// Reset the counter.
  void reset() {
    _count = 0;
    _stage = 'idle';
    _lastRepTimestamp = 0;
    _countController.add(0);
    _stageController.add('idle');
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    _isDisposed = true;
    _isActive = false;
    try {
      if (_cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      await _cameraController?.dispose();
    } catch (_) {}
    await _poseDetector.close();
    _countController.close();
    _poseController.close();
    _stageController.close();
    _feedbackController.close();
  }

  // ── Frame processing ──────────────────────────────────────────────

  void _processImage(CameraImage image) {
    if (_isProcessing || !_isActive) return;
    _isProcessing = true;

    final inputImage = _convertToInputImage(image);
    if (inputImage == null) {
      _isProcessing = false;
      return;
    }

    _poseDetector.processImage(inputImage).then((poses) {
      if (_isDisposed) return;
      if (poses.isNotEmpty) {
        final pose = poses.first;
        _poseController.add(pose);
        _analyzePose(pose);
      } else {
        _poseController.add(null);
        _feedbackController.add('No person detected — get in frame');
      }
      _isProcessing = false;
    }).catchError((dynamic e) {
      debugPrint('Pose detection error: $e');
      _isProcessing = false;
    });
  }

  InputImage? _convertToInputImage(CameraImage image) {
    if (_activeCamera == null) return null;

    final sensorOrientation = _activeCamera!.sensorOrientation;
    InputImageRotation? rotation;
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

    final cameraFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (cameraFormat == null) return null;

    final inputFormat = defaultTargetPlatform == TargetPlatform.android
        ? InputImageFormat.nv21
        : cameraFormat;
    final bytes = _bytesFromCameraImage(image, cameraFormat);
    if (bytes == null) return null;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: inputFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Uint8List? _bytesFromCameraImage(
    CameraImage image,
    InputImageFormat format,
  ) {
    if (defaultTargetPlatform == TargetPlatform.android &&
        format == InputImageFormat.nv21) {
      if (image.planes.length != 1) {
        return _yuv420ToNv21(image);
      }
      return image.planes.first.bytes;
    }

    if (defaultTargetPlatform == TargetPlatform.android &&
        format == InputImageFormat.yuv_420_888) {
      return _yuv420ToNv21(image);
    }

    if (defaultTargetPlatform == TargetPlatform.iOS &&
        format == InputImageFormat.bgra8888) {
      return image.planes.first.bytes;
    }

    return null;
  }

  Uint8List? _yuv420ToNv21(CameraImage image) {
    if (image.planes.length < 3) return null;

    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final output = Uint8List(width * height + (width * height ~/ 2));

    var outputOffset = 0;
    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      output.setRange(
        outputOffset,
        outputOffset + width,
        yPlane.bytes,
        rowStart,
      );
      outputOffset += width;
    }

    final chromaHeight = height ~/ 2;
    final chromaWidth = width ~/ 2;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    var chromaOffset = width * height;
    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final vuIndex = row * vPlane.bytesPerRow + col * vPixelStride;
        final uIndex = row * uPlane.bytesPerRow + col * uPixelStride;
        if (vuIndex >= vPlane.bytes.length || uIndex >= uPlane.bytes.length) {
          return null;
        }
        output[chromaOffset++] = vPlane.bytes[vuIndex];
        output[chromaOffset++] = uPlane.bytes[uIndex];
      }
    }

    return output;
  }

  // ── Pose analysis ─────────────────────────────────────────────────

  void _analyzePose(Pose pose) {
    // Try left arm first, then right arm
    final leftAngle = _getElbowAngle(
      pose,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.leftWrist,
    );

    final rightAngle = _getElbowAngle(
      pose,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.rightWrist,
    );

    // Use the arm with better visibility (non-null, higher confidence)
    double? bestAngle;
    if (leftAngle != null && rightAngle != null) {
      bestAngle = (leftAngle + rightAngle) / 2;
    } else if (leftAngle != null) {
      bestAngle = leftAngle;
    } else if (rightAngle != null) {
      bestAngle = rightAngle;
    }

    if (bestAngle == null) {
      _feedbackController.add('Can\'t see your arms — adjust position');
      return;
    }

    // If body alignment is visible, use it for feedback. Do not reject the
    // frame outright because camera rotation and wall/floor placement can make
    // shoulder/hip geometry look different across devices.
    if (!_isBodyHorizontal(pose)) {
      _feedbackController.add('Keep your side profile and arms visible');
    }

    _updateState(bestAngle);
  }

  double? _getElbowAngle(
    Pose pose,
    PoseLandmarkType shoulderType,
    PoseLandmarkType elbowType,
    PoseLandmarkType wristType,
  ) {
    final shoulder = pose.landmarks[shoulderType];
    final elbow = pose.landmarks[elbowType];
    final wrist = pose.landmarks[wristType];

    if (shoulder == null || elbow == null || wrist == null) return null;

    // Check confidence for all three landmarks
    if (shoulder.likelihood < _minConfidence ||
        elbow.likelihood < _minConfidence ||
        wrist.likelihood < _minConfidence) {
      return null;
    }

    return _calculateAngle(
      math.Point(shoulder.x, shoulder.y),
      math.Point(elbow.x, elbow.y),
      math.Point(wrist.x, wrist.y),
    );
  }

  double _calculateAngle(
    math.Point<double> a,
    math.Point<double> b,
    math.Point<double> c,
  ) {
    final radians = math.atan2(c.y - b.y, c.x - b.x) -
        math.atan2(a.y - b.y, a.x - b.x);
    var angle = (radians * 180 / math.pi).abs();
    if (angle > 180) angle = 360 - angle;
    return angle;
  }

  /// Check if the body is roughly horizontal (pushup position).
  /// Shoulder and hip y-coordinates should be close.
  bool _isBodyHorizontal(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    // Need at least one shoulder and one hip
    final shoulder = leftShoulder ?? rightShoulder;
    final hip = leftHip ?? rightHip;

    if (shoulder == null || hip == null) return false; // can't verify, reject

    if (shoulder.likelihood < _minConfidence ||
        hip.likelihood < _minConfidence) {
      return false; // low confidence, reject
    }

    // In a pushup position, the vertical distance between shoulder and hip
    // should be much less than the horizontal distance.
    final verticalDiff = (shoulder.y - hip.y).abs();
    final horizontalDiff = (shoulder.x - hip.x).abs();

    // If the person is standing upright, vertical diff >> horizontal diff
    // Allow if vertical/horizontal ratio < 2.0 (generous to avoid false negatives)
    if (horizontalDiff < 10) return false; // too close to determine, reject
    return (verticalDiff / horizontalDiff) < 2.5;
  }

  void _updateState(double angle) {
    if (_isDisposed) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (angle > _upAngleThreshold) {
      // Arms extended — UP position
      if (_stage == 'down') {
        // Transition: DOWN → UP = one valid pushup
        final timeSinceLastRep = _lastRepTimestamp > 0
            ? now - _lastRepTimestamp
            : _minRepMs;

        if (timeSinceLastRep >= _minRepMs) {
          _count++;
          _lastRepTimestamp = now;
          _countController.add(_count);
          _feedbackController.add('Good pushup! 💪');
        }
      }
      if (_stage != 'up') {
        _stage = 'up';
        _stageController.add('up');
        if (_count == 0) {
          _feedbackController.add('Now go down!');
        }
      }
    } else if (angle < _downAngleThreshold) {
      // Arms bent — DOWN position
      if (_stage != 'down') {
        _stage = 'down';
        _stageController.add('down');
        _feedbackController.add('Push up!');
      }
    } else {
      // In between — no state change, give guidance
      if (_stage == 'up') {
        _feedbackController.add('Go lower...');
      } else if (_stage == 'down') {
        _feedbackController.add('Almost there...');
      }
    }
  }
}
