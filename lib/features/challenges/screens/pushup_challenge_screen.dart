import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../../core/services/platform_channel_service.dart';
import '../services/camera_pushup_detector.dart';

class PushupChallengeScreen extends StatefulWidget {
  final int targetCount;
  const PushupChallengeScreen({super.key, this.targetCount = 10});

  @override
  State<PushupChallengeScreen> createState() => _PushupChallengeScreenState();
}

class _PushupChallengeScreenState extends State<PushupChallengeScreen> {
  late CameraPushupDetector _detector;
  int _count = 0;
  double _currentAngle = 0;
  String _feedback = "Position yourself in the camera frame";
  Pose? _currentPose;
  bool _isInitialized = false;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
  }

  Future<void> _initializeDetector() async {
    _detector = CameraPushupDetector();
    
    _detector.onCountUpdate = (count) {
      if (!mounted) return;
      setState(() {
        _count = count;
      });
      if (count >= widget.targetCount && !_isCompleted) {
        _onChallengeComplete();
      }
    };

    _detector.onAngleUpdate = (angle) {
      if (!mounted) return;
      setState(() {
        _currentAngle = angle;
      });
    };

    _detector.onFeedbackUpdate = (feedback) {
      if (!mounted) return;
      setState(() {
        _feedback = feedback;
      });
    };

    _detector.onPoseDetected = (pose) {
      if (!mounted) return;
      setState(() {
        _currentPose = pose;
      });
    };

    await _detector.initialize();
    if (!mounted) return;
    setState(() {
      _isInitialized = true;
    });
    _detector.startDetection();
  }

  void _onChallengeComplete() async {
    setState(() {
      _isCompleted = true;
      _feedback = "Challenge Completed! 🎉";
    });
    _detector.stopDetection();

    // Vibrate or play a sound here if desired
    await PlatformChannelService.instance.grantTempUnlock();

    // Hold screen for 2.5 seconds to show celebration, then navigate back
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0x000a0a1a),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xff6c63ff)),
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final controller = _detector.cameraController!;

    return Scaffold(
      backgroundColor: const Color(0xff0a0a1a),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview (cropped/scaled to cover screen)
          Transform.scale(
            scale: 1 / (controller.value.aspectRatio * (size.width / size.height)),
            alignment: Alignment.topCenter,
            child: CameraPreview(controller),
          ),

          // Pose Skeleton Overlay
          if (_currentPose != null && controller.value.previewSize != null)
            CustomPaint(
              painter: PosePainter(
                _currentPose!,
                controller.value.previewSize!,
                controller.description.lensDirection,
              ),
            ),

          // Semi-transparent gradient overlay for better text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.0, 0.25, 0.75, 1.0],
              ),
            ),
          ),

          // Header: Back Button & Title & Counter
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xff16213e).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xff6c63ff), width: 1),
                      ),
                      child: Text(
                        "Angle: ${_currentAngle.toStringAsFixed(0)}°",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    "$_count / ${widget.targetCount}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Simple Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _count / widget.targetCount,
                    minHeight: 12,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xff6c63ff)),
                  ),
                ),
              ],
            ),
          ),

          // Feedback message in center-bottom
          Positioned(
            bottom: 120,
            left: 20,
            right: 20,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: _isCompleted 
                      ? const Color(0xff00d4aa).withOpacity(0.9) 
                      : const Color(0xff1a1a2e).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _isCompleted ? const Color(0xff00d4aa) : const Color(0xff6c63ff),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  _feedback,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: _isCompleted ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

          // Celebration overlay
          if (_isCompleted)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xff00d4aa), size: 100),
                    const SizedBox(height: 24),
                    const Text(
                      "DISCIPLINE EARNED",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Instagram unlocked for 10 minutes",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _detector.dispose();
    super.dispose();
  }
}

class PosePainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection;

  PosePainter(this.pose, this.imageSize, this.cameraLensDirection);

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = const Color(0xff00d4aa)
      ..strokeWidth = 6
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xff6c63ff)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Scale calculations
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    // Helper to translate coordinate
    Offset getOffset(PoseLandmark landmark) {
      double x = landmark.x * scaleX;
      double y = landmark.y * scaleY;
      
      // Front camera mirroring correction
      if (cameraLensDirection == CameraLensDirection.front) {
        x = size.width - x;
      }
      return Offset(x, y);
    }

    void drawLine(PoseLandmarkType startType, PoseLandmarkType endType) {
      final start = pose.landmarks[startType];
      final end = pose.landmarks[endType];
      if (start != null && end != null && start.likelihood > 0.5 && end.likelihood > 0.5) {
        canvas.drawLine(getOffset(start), getOffset(end), linePaint);
      }
    }

    // Draw lines
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
    drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
    drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
    drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);

    // Draw key points
    pose.landmarks.values.forEach((landmark) {
      if (landmark.likelihood > 0.5) {
        canvas.drawCircle(getOffset(landmark), 4, pointPaint);
      }
    });
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) => true;
}
