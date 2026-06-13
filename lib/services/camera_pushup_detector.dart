import 'dart:async';
import 'dart:math';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum RepState { up, down }

class CameraPushupDetector {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;

  final _countController = StreamController<int>.broadcast();
  Stream<int> get onCountChanged => _countController.stream;

  /// Latest detected pose (null when none). Drives the green-skeleton overlay.
  final ValueNotifier<Pose?> poseNotifier = ValueNotifier<Pose?>(null);

  /// Whether a usable pose was detected in the most recent frame (debug HUD).
  final ValueNotifier<bool> poseDetected = ValueNotifier<bool>(false);

  /// Most recent elbow angle in degrees, or null (debug HUD).
  final ValueNotifier<double?> elbowAngle = ValueNotifier<double?>(null);

  /// Size of the analysed camera image, for the painter's coordinate mapping.
  final ValueNotifier<Size?> imageSize = ValueNotifier<Size?>(null);

  int _count = 0;
  bool _isRunning = false;
  bool _isInitialized = false;
  bool _isProcessing = false;

  RepState _repState = RepState.up;
  // Down position: elbow strongly bent. Up position: arm extended.
  static const double _downThreshold = 90.0;
  static const double _upThreshold = 160.0;
  static const double _minConfidence = 0.5;

  CameraController? get cameraController => _cameraController;
  int get currentCount => _count;
  bool get isInitialized => _isInitialized;
  bool get isFrontCamera =>
      _cameraController?.description.lensDirection ==
      CameraLensDirection.front;

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
        // Request NV21 so ML Kit receives a valid single-plane buffer.
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
        ),
      );
      _isInitialized = true;
      debugPrint('CameraPushupDetector: initialized (nv21)');
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
      imageSize.value = Size(image.width.toDouble(), image.height.toDouble());

      _poseDetector!.processImage(inputImage).then((poses) {
        if (poses.isNotEmpty) {
          poseNotifier.value = poses.first;
          _processPose(poses.first);
        } else {
          poseNotifier.value = null;
          poseDetected.value = false;
        }
        _isProcessing = false;
      }).catchError((Object e) {
        debugPrint('CameraPushupDetector: processImage error — $e');
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('CameraPushupDetector: _processImage error — $e');
      _isProcessing = false;
    }
  }

  /// Build an [InputImage] from a real NV21 stream. With
  /// imageFormatGroup: ImageFormatGroup.nv21 the plugin delivers a single
  /// plane already in NV21 layout, so we pass its bytes and stride directly.
  InputImage? _buildInputImage(CameraImage image) {
    final camera = _cameraController?.description;
    if (camera == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    final isFront = camera.lensDirection == CameraLensDirection.front;
    final rotation = _rotation(
      isFront ? (360 - sensorOrientation) % 360 : sensorOrientation,
    );

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
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

    double? angle;

    // Prefer the arm whose three joints are all confidently detected.
    if (_hasConfidentLandmarks(leftShoulder, leftElbow, leftWrist)) {
      angle = _elbowAngle(leftShoulder!, leftElbow!, leftWrist!);
    } else if (_hasConfidentLandmarks(rightShoulder, rightElbow, rightWrist)) {
      angle = _elbowAngle(rightShoulder!, rightElbow!, rightWrist!);
    } else if (leftShoulder != null && leftElbow != null && leftWrist != null) {
      angle = _elbowAngle(leftShoulder, leftElbow, leftWrist);
    } else if (rightShoulder != null &&
        rightElbow != null &&
        rightWrist != null) {
      angle = _elbowAngle(rightShoulder, rightElbow, rightWrist);
    }

    final detected = angle != null;
    poseDetected.value = detected;
    elbowAngle.value = angle;

    if (detected) {
      debugPrint(
          'CameraPushup: angle=${angle!.toStringAsFixed(1)}, '
          'state=$_repState, count=$_count');
      _updateRepState(angle);
    }
  }

  bool _hasConfidentLandmarks(
      PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) {
    if (a == null || b == null || c == null) return false;
    return a.likelihood >= _minConfidence &&
        b.likelihood >= _minConfidence &&
        c.likelihood >= _minConfidence;
  }

  /// Interior angle at vertex [elbow] formed by shoulder-elbow-wrist, degrees.
  /// Uses the dot product of the two limb vectors (ES and EW).
  double _elbowAngle(
      PoseLandmark shoulder, PoseLandmark elbow, PoseLandmark wrist) {
    final esx = shoulder.x - elbow.x;
    final esy = shoulder.y - elbow.y;
    final ewx = wrist.x - elbow.x;
    final ewy = wrist.y - elbow.y;

    final dot = esx * ewx + esy * ewy;
    final magEs = sqrt(esx * esx + esy * esy);
    final magEw = sqrt(ewx * ewx + ewy * ewy);
    if (magEs == 0 || magEw == 0) return 180.0;

    var cosA = dot / (magEs * magEw);
    cosA = cosA.clamp(-1.0, 1.0);
    return acos(cosA) * 180 / pi;
  }

  /// Simple UP -> DOWN -> UP state machine. One full transition = one rep.
  void _updateRepState(double angle) {
    switch (_repState) {
      case RepState.up:
        if (angle < _downThreshold) {
          _repState = RepState.down;
        }
      case RepState.down:
        if (angle > _upThreshold) {
          _repState = RepState.up;
          _count++;
          _countController.add(_count);
        }
    }
  }

  void reset() {
    _count = 0;
    _repState = RepState.up;
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
    poseNotifier.value = null;
    poseDetected.value = false;
    elbowAngle.value = null;
    imageSize.value = null;
    await _countController.close();
  }
}
