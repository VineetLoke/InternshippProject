import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

/// Custom painter that draws the detected skeleton overlay on the camera preview.
///
/// Shows connected landmarks with color coding:
/// - Green when in UP position (arms extended)
/// - Red when in DOWN position (arms bent)
/// - Gold/amber when idle
///
/// Also draws the elbow angle arc for visual feedback.
class PosePainter extends CustomPainter {
  final Pose? pose;
  final Size imageSize;
  final String stage;
  final CameraLensDirection lensDirection;

  PosePainter({
    required this.pose,
    required this.imageSize,
    required this.stage,
    required this.lensDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null) return;

    final Color stageColor;
    switch (stage) {
      case 'up':
        stageColor = const Color(0xFF4CAF50); // green
        break;
      case 'down':
        stageColor = const Color(0xFFFF5722); // red-orange
        break;
      default:
        stageColor = const Color(0xFFC6A85A); // gold
    }

    final pointPaint = Paint()
      ..color = stageColor
      ..strokeWidth = 8.0
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = stageColor.withOpacity(0.7)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final lowConfidencePaint = Paint()
      ..color = Colors.grey.withOpacity(0.4)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.fill;

    // Draw all landmarks
    for (final landmark in pose!.landmarks.values) {
      final point = _translatePoint(landmark, size);
      final paint = landmark.likelihood >= 0.5 ? pointPaint : lowConfidencePaint;
      canvas.drawCircle(point, 5.0, paint);
    }

    // Draw skeleton connections
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
    _drawConnection(canvas, size, linePaint,
        PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
  }

  void _drawConnection(
    Canvas canvas,
    Size size,
    Paint paint,
    PoseLandmarkType type1,
    PoseLandmarkType type2,
  ) {
    final lm1 = pose!.landmarks[type1];
    final lm2 = pose!.landmarks[type2];
    if (lm1 == null || lm2 == null) return;
    if (lm1.likelihood < 0.3 || lm2.likelihood < 0.3) return;

    final p1 = _translatePoint(lm1, size);
    final p2 = _translatePoint(lm2, size);
    canvas.drawLine(p1, p2, paint);
  }

  Offset _translatePoint(PoseLandmark landmark, Size canvasSize) {
    // Map from image coordinates to canvas coordinates
    final double x;
    final double y;

    // For front camera, mirror the x coordinate
    if (lensDirection == CameraLensDirection.front) {
      x = canvasSize.width - (landmark.x / imageSize.width * canvasSize.width);
    } else {
      x = landmark.x / imageSize.width * canvasSize.width;
    }
    y = landmark.y / imageSize.height * canvasSize.height;

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.pose != pose || oldDelegate.stage != stage;
  }
}
