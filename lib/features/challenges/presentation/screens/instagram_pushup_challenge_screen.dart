import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:focus_lock/features/challenges/services/camera_pushup_detector.dart';
import 'package:focus_lock/features/challenges/presentation/widgets/pose_painter.dart';

/// Emergency unlock screen for Instagram.
///
/// Requires 100 pushups verified by camera to grant 10 minutes of access.
/// Uses ML Kit Pose Detection for cheat-proof pushup verification.
class InstagramPushupChallengeScreen extends StatefulWidget {
  const InstagramPushupChallengeScreen({super.key});

  @override
  State<InstagramPushupChallengeScreen> createState() =>
      _InstagramPushupChallengeScreenState();
}

class _InstagramPushupChallengeScreenState
    extends State<InstagramPushupChallengeScreen>
    with SingleTickerProviderStateMixin {
  static const int _requiredPushups = 100;
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  final _detector = CameraPushupDetector();

  StreamSubscription<int>? _countSub;
  StreamSubscription<Pose?>? _poseSub;
  StreamSubscription<String>? _stageSub;
  StreamSubscription<String>? _feedbackSub;

  int _count = 0;
  bool _isDetecting = false;
  bool _cameraReady = false;
  bool _redeemed = false;
  bool _cameraError = false;
  String _stage = 'idle';
  String _feedback = 'Tap Start to begin';
  Pose? _currentPose;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 1.0, end: 1.15).animate(_pulseController);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() => _cameraError = true);
        _feedback = 'Camera permission required';
      }
      return;
    }

    final initialized = await _detector.initialize();
    if (mounted) {
      setState(() {
        _cameraReady = initialized;
        _cameraError = !initialized;
        if (!initialized) _feedback = 'Camera initialization failed';
      });
    }
  }

  Future<void> _startDetection() async {
    if (!_cameraReady) {
      await _initCamera();
      if (!_cameraReady) return;
    }

    _detector.reset();

    _countSub = _detector.onCountChanged.listen((count) {
      if (mounted) {
        setState(() => _count = count);
        if (count >= _requiredPushups && !_redeemed) {
          _onChallengeComplete();
        }
      }
    });

    _poseSub = _detector.onPoseChanged.listen((pose) {
      if (mounted) setState(() => _currentPose = pose);
    });

    _stageSub = _detector.onStageChanged.listen((stage) {
      if (mounted) setState(() => _stage = stage);
    });

    _feedbackSub = _detector.onFeedbackChanged.listen((feedback) {
      if (mounted) setState(() => _feedback = feedback);
    });

    final started = await _detector.startDetection();
    if (mounted) {
      setState(() {
        _isDetecting = started;
        _count = 0;
        if (!started) _feedback = 'Failed to start detection';
      });
    }
  }

  Future<void> _stopDetection() async {
    await _countSub?.cancel();
    await _poseSub?.cancel();
    await _stageSub?.cancel();
    await _feedbackSub?.cancel();
    _countSub = null;
    _poseSub = null;
    _stageSub = null;
    _feedbackSub = null;
    await _detector.stopDetection();
    if (mounted) setState(() => _isDetecting = false);
  }

  Future<void> _onChallengeComplete() async {
    await _stopDetection();

    bool success = false;
    try {
      final result = await _channel.invokeMethod('completeInstagramEmergencyChallenge');
      success = result == true;
    } catch (e) {
      debugPrint('Error completing Instagram challenge: $e');
    }

    setState(() => _redeemed = success);

    if (success && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('🎉 Challenge Complete!'),
          content: const Text(
            'Instagram unlocked for 10 minutes.\n\n'
            'Use the time wisely.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _countSub?.cancel();
    _poseSub?.cancel();
    _stageSub?.cancel();
    _feedbackSub?.cancel();
    _detector.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = (_count / _requiredPushups).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Instagram Emergency Unlock',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _stopDetection();
            if (!mounted) return;
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF14130E), Color(0xFF0A0A0C)],
            center: Alignment.topCenter,
            radius: 1.5,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),

              // ── Status chip ────────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '100 pushups = 10 min access',
                  style: TextStyle(color: colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 12),

              // ── Camera Preview ─────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _stageColor,
                        width: 3.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _stageColor.withValues(alpha: 0.18),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(21),
                      child: _buildCameraPreview(colorScheme, progress),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── Feedback bar ───────────────────────────────────────
              _buildFeedbackBar(colorScheme),

              const SizedBox(height: 10),

              // ── Instructions ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131316),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF222226)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Emergency Unlock',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _instructionRow('1', 'Place phone on a wall facing your side'),
                      _instructionRow('2', 'Keep your full body visible in frame'),
                      _instructionRow('3', 'Tap "Start" — camera verifies each rep'),
                      _instructionRow('4', 'Every 100 pushups adds 10 min Instagram access'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── Start / Stop button ────────────────────────────────
              if (!_redeemed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: Icon(
                        _isDetecting ? Icons.stop_rounded : Icons.videocam_rounded,
                        size: 22,
                      ),
                      label: Text(
                        _isDetecting ? 'ABORT CHALLENGE' : 'START CAMERA DETECTION',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isDetecting
                            ? colorScheme.error
                            : colorScheme.primary,
                        foregroundColor: _isDetecting ? Colors.white : colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed:
                          _isDetecting ? _stopDetection : _startDetection,
                    ),
                  ),
                ),

              if (_cameraError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Camera not available. Please grant camera permission.',
                    style: TextStyle(color: colorScheme.error, fontSize: 13),
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview(ColorScheme colorScheme, double progress) {
    if (!_cameraReady || _detector.cameraController == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131316),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, size: 44, color: colorScheme.secondary),
              const SizedBox(height: 12),
              Text(
                _cameraError ? 'Camera unavailable' : 'Initializing camera...',
                style: TextStyle(color: colorScheme.secondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_detector.cameraController!),

        if (_currentPose != null && _detector.previewSize != null)
          CustomPaint(
            painter: PosePainter(
              pose: _currentPose,
              imageSize: _detector.previewSize!,
              stage: _stage,
              lensDirection: _detector.lensDirection,
            ),
          ),

        // Counter overlay
        Positioned(
          top: 16,
          right: 16,
          child: ScaleTransition(
            scale: _isDetecting ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.7),
                border: Border.all(
                  color: progress >= 1.0
                      ? const Color(0xFF4ADE80)
                      : colorScheme.primary,
                  width: 2.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$_count',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: progress >= 1.0
                          ? const Color(0xFF4ADE80)
                          : colorScheme.primary,
                    ),
                  ),
                  Text(
                    '/$_requiredPushups',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Stage indicator
        if (_isDetecting)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _stageColor.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _stage == 'up'
                        ? Icons.arrow_upward_rounded
                        : _stage == 'down'
                            ? Icons.arrow_downward_rounded
                            : Icons.remove_rounded,
                    color: const Color(0xFF0F0E0B),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _stage.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF0F0E0B),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Progress bar at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1.0
                  ? const Color(0xFF4ADE80)
                  : colorScheme.primary,
            ),
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _stageColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _stageColor.withValues(alpha: 0.25)),
        ),
        child: Text(
          _feedback,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _stageColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color get _stageColor {
    switch (_stage) {
      case 'up':
        return const Color(0xFF4ADE80);
      case 'down':
        return const Color(0xFFB54534);
      default:
        return const Color(0xFFC6A85A);
    }
  }

  Widget _instructionRow(String num, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: TextStyle(color: colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Color(0xFF8A7A6C), fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}
