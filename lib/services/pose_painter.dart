import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Draws the 33 ML Kit pose landmarks and the skeleton connections in GREEN
/// on top of the camera preview, giving the user a "green stickman" that
/// confirms their body is being tracked.
///
/// Coordinates from ML Kit are in the analysed image's coordinate space
/// ([imageSize], in the image's natural orientation). We scale them to the
/// painter [size] and, for the front camera, mirror horizontally so the
/// overlay matches the mirrored preview.
class PosePainter extends CustomPainter {
  PosePainter({
    required this.pose,
    required this.imageSize,
    required this.rotation,
    required this.mirror,
  });

  final Pose? pose;
  final Size? imageSize;
  final InputImageRotation rotation;
  final bool mirror;

  // Skeleton connections between joints (shoulders, arms, torso, legs).
  static const List<List<PoseLandmarkType>> _connections = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final currentPose = pose;
    final imgSize = imageSize;
    if (currentPose == null || imgSize == null) return;

    // For 90/270 rotations the analysed image is effectively transposed
    // relative to the upright preview, so swap width/height for scaling.
    final rotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final srcW = rotated ? imgSize.height : imgSize.width;
    final srcH = rotated ? imgSize.width : imgSize.height;
    if (srcW == 0 || srcH == 0) return;

    final scaleX = size.width / srcW;
    final scaleY = size.height / srcH;

    Offset map(PoseLandmark lm) {
      var dx = lm.x * scaleX;
      final dy = lm.y * scaleY;
      if (mirror) dx = size.width - dx;
      return Offset(dx, dy);
    }

    final pointPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 6
      ..strokeCap = ui.StrokeCap.round;

    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    // Skeleton lines.
    for (final c in _connections) {
      final a = currentPose.landmarks[c[0]];
      final b = currentPose.landmarks[c[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(map(a), map(b), linePaint);
    }

    // All 33 landmarks.
    for (final lm in currentPose.landmarks.values) {
      canvas.drawPoints(ui.PointMode.points, [map(lm)], pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.pose != pose || oldDelegate.imageSize != imageSize;
  }
}
