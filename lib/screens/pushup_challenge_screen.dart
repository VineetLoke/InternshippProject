import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/camera_pushup_detector.dart';
import '../services/pose_painter.dart';
import '../services/reddit_usage_service.dart';

/// Full-screen pushup challenge to earn 10 minutes of Reddit.
///
/// Uses the device camera with ML Kit Pose Detection to verify real pushups.
/// Tracks elbow angle (shoulder→elbow→wrist) to detect UP/DOWN positions.
/// Cheat-proof: requires actual pushup form visible to camera.
class PushupChallengeScreen extends StatefulWidget {
  const PushupChallengeScreen({Key? key}) : super(key: key);

  @override
  State<PushupChallengeScreen> createState() => _PushupChallengeScreenState();
}

class _PushupChallengeScreenState extends State<PushupChallengeScreen>
    with SingleTickerProviderStateMixin {
  static const int _requiredPushups = 100;
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  final _redditService = RedditUsageService();
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
  String _redditRemaining = '--';
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
    _loadRedditStatus();
    _initCamera();
  }

  Future<void> _loadRedditStatus() async {
    final tempUnlock = await _redditService.getTempUnlockRemainingSeconds();
    if (tempUnlock > 0) {
      if (mounted) {
        setState(() {
          _redditRemaining =
              'Unlock active: ${RedditUsageService.formatDuration(tempUnlock)}';
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _redditRemaining = 'Reddit is locked';
        });
      }
    }
  }

  Future<void> _initCamera() async {
    // Request camera permission
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

    // Grant Reddit temp unlock via native side
    bool success = false;
    try {
      final result = await _channel.invokeMethod('grantRedditCameraPushupReward');
      success = result == true;
    } catch (e) {
      debugPrint('Error granting Reddit reward: $e');
      // Fallback: try the old method
      try {
        final result = await _channel.invokeMethod('completeRedditEmergencyChallenge');
        success = result == true;
      } catch (_) {}
    }

    setState(() => _redeemed = success);

    if (success && mounted) {
      await _loadRedditStatus();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('🎉 Challenge Complete!'),
          content: const Text(
            'Reddit unlocked for 10 minutes.\n\n'
            'Discipline is forged in resistance.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // back to home
              },
              child: const Text('Open Reddit'),
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

  // ── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = (_count / _requiredPushups).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Pushup Challenge'),
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _stopDetection();
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),

            // ── Reddit status chip ─────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
              ),
              child: Text(
                _redditRemaining,
                style: TextStyle(
                    color: colorScheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 12),

            // ── Camera Preview with Overlay ─────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildCameraPreview(colorScheme, progress),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Feedback bar ───────────────────────────────────────
            _buildFeedbackBar(colorScheme),

            const SizedBox(height: 8),

            // ── Instructions ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF222228)),
                ),
                child: Column(
                  children: [
                    Text(
                      'How it works',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _instructionRow('1', 'Prop phone up so camera can see you'),
                    _instructionRow('2', 'Get into pushup position (side view)'),
                    _instructionRow('3', 'Tap "Start" — camera verifies each rep'),
                    _instructionRow('4', '100 pushups = 10 min Reddit access'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Start / Stop button ────────────────────────────────
            if (!_redeemed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    icon: Icon(
                      _isDetecting ? Icons.stop : Icons.videocam,
                      size: 24,
                    ),
                    label: Text(
                      _isDetecting ? 'Stop' : 'Start Camera Detection',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isDetecting ? colorScheme.error : colorScheme.primary,
                      foregroundColor: _isDetecting ? Colors.white : colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview(ColorScheme colorScheme, double progress) {
    if (!_cameraReady || _detector.cameraController == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, size: 48, color: colorScheme.secondary),
              const SizedBox(height: 12),
              Text(
                _cameraError ? 'Camera unavailable' : 'Initializing camera...',
                style: TextStyle(color: colorScheme.secondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        CameraPreview(_detector.cameraController!),

        // Skeleton overlay
        if (_currentPose != null && _detector.previewSize != null)
          CustomPaint(
            painter: PosePainter(
              pose: _currentPose,
              imageSize: _detector.previewSize!,
              stage: _stage,
              lensDirection: _detector.lensDirection,
            ),
          ),

        // Counter overlay (top-right)
        Positioned(
          top: 16,
          right: 16,
          child: ScaleTransition(
            scale: _isDetecting ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.6),
                border: Border.all(
                  color: progress >= 1.0
                      ? const Color(0xFF2E7D63)
                      : colorScheme.primary,
                  width: 3,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$_count',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  Text(
                    '/$_requiredPushups',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Stage indicator (top-left)
        if (_isDetecting)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _stageColor.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _stage == 'up'
                        ? Icons.arrow_upward
                        : _stage == 'down'
                            ? Icons.arrow_downward
                            : Icons.remove,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _stage.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
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
            backgroundColor: Colors.black.withOpacity(0.4),
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1.0
                  ? const Color(0xFF2E7D63)
                  : colorScheme.primary,
            ),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _stageColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _stageColor.withOpacity(0.3)),
        ),
        child: Text(
          _feedback,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _stageColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Color get _stageColor {
    switch (_stage) {
      case 'up':
        return const Color(0xFF4CAF50);
      case 'down':
        return const Color(0xFFFF5722);
      default:
        return const Color(0xFFC6A85A);
    }
  }

  Widget _instructionRow(String num, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style:
                      TextStyle(color: colorScheme.onPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: Colors.grey.shade300, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
