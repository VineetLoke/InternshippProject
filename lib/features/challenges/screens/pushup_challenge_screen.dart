import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:provider/provider.dart';
import '../../../core/services/platform_channel_service.dart';
import '../services/camera_pushup_detector.dart';
import '../services/pushup_counter.dart';

/// Full-screen pushup challenge screen with:
/// - Live camera preview
/// - Skeleton overlay (CustomPainter)
/// - Large counter display
/// - Real-time angle + form feedback
/// - Progress bar
/// - Celebration animation on completion
class PushupChallengeScreen extends StatefulWidget {
  const PushupChallengeScreen({super.key});

  @override
  State<PushupChallengeScreen> createState() => _PushupChallengeScreenState();
}

class _PushupChallengeScreenState extends State<PushupChallengeScreen>
    with TickerProviderStateMixin {
  static const int _targetPushups = 10;

  late CameraPushupDetector _detector;
  bool _isInitialized = false;
  bool _isCompleted = false;
  String _initError = '';

  int _currentCount = 0;
  double _currentAngle = 180.0;
  String _feedback = 'Get into position...';
  Pose? _currentPose;

  // Celebration animation
  late AnimationController _celebrationController;
  late Animation<double> _celebrationScale;

  @override
  void initState() {
    super.initState();
    _detector = CameraPushupDetector(targetCount: _targetPushups);

    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _celebrationScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _celebrationController,
        curve: Curves.elasticOut,
      ),
    );

    _initializeDetector();
  }

  Future<void> _initializeDetector() async {
    _detector.onCountUpdate = (count) {
      if (!mounted) return;
      setState(() => _currentCount = count);
    };

    _detector.onAngleUpdate = (angle) {
      if (!mounted) return;
      setState(() => _currentAngle = angle);
    };

    _detector.onFeedbackUpdate = (feedback) {
      if (!mounted) return;
      setState(() => _feedback = feedback);
    };

    _detector.onPoseDetected = (pose) {
      if (!mounted) return;
      setState(() => _currentPose = pose);
    };

    _detector.onChallengeComplete = () {
      if (!mounted) return;
      _onChallengeComplete();
    };

    try {
      await _detector.initialize();
      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = 'Camera error: ${e.toString()}';
      });
    }
  }

  Future<void> _onChallengeComplete() async {
    setState(() => _isCompleted = true);
    _celebrationController.forward();

    // Grant temp unlock
    final platformService =
        Provider.of<PlatformChannelService>(context, listen: false);
    await platformService.grantTempUnlock();

    // Wait for celebration, then navigate
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError.isNotEmpty) {
      return _buildErrorScreen();
    }

    if (!_isInitialized) {
      return _buildLoadingScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          _buildCameraPreview(),

          // Skeleton overlay
          if (_currentPose != null && !_isCompleted)
            CustomPaint(
              painter: _PoseSkeletonPainter(
                pose: _currentPose!,
                imageSize: Size(
                  _detector.cameraController!.value.previewSize!.height,
                  _detector.cameraController!.value.previewSize!.width,
                ),
                screenSize: MediaQuery.of(context).size,
                isFrontCamera: true,
              ),
            ),

          // Top overlay with back button and angle
          _buildTopOverlay(),

          // Bottom overlay with counter, progress, and feedback
          _buildBottomOverlay(),

          // Celebration overlay
          if (_isCompleted) _buildCelebration(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _detector.cameraController!;
    final previewSize = controller.value.previewSize!;
    final screenSize = MediaQuery.of(context).size;

    // Calculate scale to fill the screen
    final screenAspectRatio = screenSize.width / screenSize.height;
    final previewAspectRatio = previewSize.height / previewSize.width;

    double scale;
    if (screenAspectRatio > previewAspectRatio) {
      scale = screenSize.width / previewSize.height;
    } else {
      scale = screenSize.height / previewSize.width;
    }

    return Center(
      child: Transform.scale(
        scale: scale,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 16,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xCC000000),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Back button
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 28),
            ),
            const Spacer(),
            // Angle display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF7C4DFF).withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.straighten_rounded,
                      color: Color(0xFF7C4DFF), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${_currentAngle.toStringAsFixed(0)}°',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: 24,
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xEE000000),
              Color(0x88000000),
              Colors.transparent,
            ],
            stops: [0.0, 0.7, 1.0],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Form feedback
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _getFeedbackColor().withOpacity(0.2),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: _getFeedbackColor().withOpacity(0.5),
                ),
              ),
              child: Text(
                _feedback,
                style: TextStyle(
                  color: _getFeedbackColor(),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Counter
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$_currentCount',
                  style: const TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                Text(
                  ' / $_targetPushups',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF8888A0),
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pushups',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF8888A0),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _currentCount / _targetPushups,
                minHeight: 8,
                backgroundColor: const Color(0xFF2A2A40),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _currentCount >= _targetPushups
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF7C4DFF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getFeedbackColor() {
    if (_feedback.contains('Go down') || _feedback.contains('Push up')) {
      return const Color(0xFF7C4DFF);
    }
    if (_feedback.contains('Keep')) {
      return const Color(0xFFFFA726);
    }
    return const Color(0xFF8888A0);
  }

  Widget _buildCelebration() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: ScaleTransition(
          scale: _celebrationScale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🎉',
                style: TextStyle(fontSize: 80),
              ),
              const SizedBox(height: 24),
              const Text(
                'AMAZING!',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF4CAF50),
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '10 Pushups Completed!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Instagram unlocked for 10 minutes',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8888A0),
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      backgroundColor: Color(0xFF0D0D1A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF7C4DFF)),
            SizedBox(height: 24),
            Text(
              'Starting camera...',
              style: TextStyle(
                color: Color(0xFF8888A0),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFFF5252), size: 64),
              const SizedBox(height: 24),
              const Text(
                'Camera Error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _initError,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8888A0),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CustomPainter that draws the detected pose skeleton on top of the camera preview.
class _PoseSkeletonPainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final Size screenSize;
  final bool isFrontCamera;

  _PoseSkeletonPainter({
    required this.pose,
    required this.imageSize,
    required this.screenSize,
    this.isFrontCamera = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = const Color(0xFF7C4DFF)
      ..strokeWidth = 8
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF536DFE).withOpacity(0.7)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final highlightPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 10
      ..style = PaintingStyle.fill;

    // Draw connections
    final connections = [
      // Arms
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      // Torso
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    ];

    for (final connection in connections) {
      final p1 = pose.landmarks[connection[0]];
      final p2 = pose.landmarks[connection[1]];
      if (p1 != null && p2 != null && p1.likelihood > 0.5 && p2.likelihood > 0.5) {
        canvas.drawLine(
          _translatePoint(p1.x, p1.y, size),
          _translatePoint(p2.x, p2.y, size),
          linePaint,
        );
      }
    }

    // Draw key landmarks
    final keyLandmarks = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ];

    final elbowTypes = {PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow};

    for (final type in keyLandmarks) {
      final landmark = pose.landmarks[type];
      if (landmark != null && landmark.likelihood > 0.5) {
        final point = _translatePoint(landmark.x, landmark.y, size);
        final paint = elbowTypes.contains(type) ? highlightPaint : pointPaint;
        canvas.drawCircle(point, elbowTypes.contains(type) ? 8 : 6, paint);
      }
    }
  }

  Offset _translatePoint(double x, double y, Size canvasSize) {
    // Scale from image coordinates to screen coordinates
    final scaleX = canvasSize.width / imageSize.width;
    final scaleY = canvasSize.height / imageSize.height;

    double translatedX = x * scaleX;
    final translatedY = y * scaleY;

    // Mirror for front camera
    if (isFrontCamera) {
      translatedX = canvasSize.width - translatedX;
    }

    return Offset(translatedX, translatedY);
  }

  @override
  bool shouldRepaint(covariant _PoseSkeletonPainter oldDelegate) {
    return oldDelegate.pose != pose;
  }
}
