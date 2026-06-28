import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../services/pushup_service.dart';

class _SkeletonPainter extends CustomPainter {
  final Pose? pose;
  final Size imageSize;
  final bool isFrontCamera;

  _SkeletonPainter({required this.pose, required this.imageSize, this.isFrontCamera = true});

  static const _bones = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  Offset _toCanvas(PoseLandmark lm, Size canvasSize) {
    double x = lm.x / imageSize.width * canvasSize.width;
    double y = lm.y / imageSize.height * canvasSize.height;
    if (isFrontCamera) x = canvasSize.width - x;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null || imageSize == Size.zero) return;

    final bonePaint = Paint()
      ..color = const Color(0xFFC6A85A)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final jointFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final jointBorder = Paint()
      ..color = const Color(0xFFC6A85A)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final bone in _bones) {
      final a = pose!.landmarks[bone[0]];
      final b = pose!.landmarks[bone[1]];
      if (a != null && b != null && a.likelihood > 0.4 && b.likelihood > 0.4) {
        canvas.drawLine(_toCanvas(a, size), _toCanvas(b, size), bonePaint);
      }
    }

    for (final lm in pose!.landmarks.values) {
      if (lm.likelihood > 0.4) {
        final pt = _toCanvas(lm, size);
        canvas.drawCircle(pt, 6, jointFill);
        canvas.drawCircle(pt, 6, jointBorder);
      }
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => old.pose != pose;
}

class PushupChallengeScreen extends StatefulWidget {
  const PushupChallengeScreen({super.key});

  @override
  State<PushupChallengeScreen> createState() => _PushupChallengeScreenState();
}

class _PushupChallengeScreenState extends State<PushupChallengeScreen> {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  final _pushupService = PushupService();
  StreamSubscription<int>? _countSub;
  StreamSubscription<Pose?>? _poseSub;

  int _count = 0;
  bool _isDetecting = false;
  bool _redeemed = false;
  bool _cameraPermissionGranted = false;
  bool _showHint = true;
  Pose? _currentPose;
  Size _imageSize = Size.zero;

  String _appName = '';
  int _requiredPushups = 50;
  String _rewardText = '';
  String _challengeMethod = '';
  Color _accentColor = const Color(0xFFC6A85A);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final perm = await Permission.camera.request();
    if (!perm.isGranted) return;
    setState(() => _cameraPermissionGranted = true);

    final started = await _pushupService.start(mode: DetectionMode.camera);
    if (!started) return;

    final detector = _pushupService.cameraDetector;
    if (detector == null) return;

    _countSub = detector.onCountChanged.listen((count) {
      if (!mounted) return;
      setState(() => _count = count);
      if (count >= _requiredPushups && !_redeemed) _onChallengeComplete();
    });

    _poseSub = detector.onPoseChanged.listen((pose) {
      if (!mounted) return;
      setState(() {
        _currentPose = pose;
        _imageSize = detector.imageSize;
      });
    });

    setState(() => _isDetecting = true);

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _appName = args['appName'] ?? 'App';
      _requiredPushups = args['requiredPushups'] ?? 50;
      _rewardText = args['rewardText'] ?? '15 min access';
      _challengeMethod = args['challengeMethod'] ?? '';
      _accentColor = Color(args['accentColor'] ?? 0xFFC6A85A);
    }
  }

  Future<void> _stopDetection() async {
    await _countSub?.cancel();
    await _poseSub?.cancel();
    _countSub = null;
    _poseSub = null;
    await _pushupService.stop();
    setState(() => _isDetecting = false);
  }

  Future<void> _onChallengeComplete() async {
    await _stopDetection();
    bool success = false;
    if (_challengeMethod.isNotEmpty) {
      try {
        final result = await _channel.invokeMethod(_challengeMethod);
        success = result == true;
      } catch (e) {
        debugPrint('Error completing challenge: $e');
      }
    }
    setState(() => _redeemed = success);
    if (success && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Challenge Complete', style: TextStyle(color: Colors.white)),
          content: Text('$_appName $_rewardText.\n\nUse the time wisely.',
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: Text('OK', style: TextStyle(color: _accentColor)),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _stopDetection();
    _pushupService.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _pushupService.cameraDetector?.cameraController;
    final cameraReady = controller != null && controller.value.isInitialized;
    final progress = (_count / _requiredPushups).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full screen camera
          if (cameraReady) CameraPreview(controller),

          // Skeleton overlay
          if (cameraReady)
            CustomPaint(
              painter: _SkeletonPainter(
                pose: _currentPose,
                imageSize: _imageSize,
                isFrontCamera: true,
              ),
            ),

          // Top + bottom gradient for readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xCC000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC000000),
                  ],
                  stops: [0.0, 0.2, 0.75, 1.0],
                ),
              ),
            ),
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () async {
                      await _stopDetection();
                      if (mounted) Navigator.of(context).pop();
                    },
                  ),
                  Expanded(
                    child: Text(
                      '$_appName Emergency Unlock',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _accentColor.withOpacity(0.4)),
                    ),
                    child: Text(
                      '$_requiredPushups = $_rewardText',
                      style: TextStyle(color: _accentColor, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Hint card — fades after 4s
          if (_showHint)
            Positioned(
              top: 90,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accentColor.withOpacity(0.35)),
                ),
                child: const Column(
                  children: [
                    Text('Prop phone upright facing your side',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                    SizedBox(height: 4),
                    Text('Do pushups sideways so camera sees your full body',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),

          // Big rep counter centered
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_count',
                  style: const TextStyle(
                    fontSize: 100,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 24, color: Colors.black)],
                  ),
                ),
                Text(
                  '/ $_requiredPushups',
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.white.withOpacity(0.55),
                    shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ],
            ),
          ),

          // Bottom — pose status + progress bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPose != null ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _currentPose != null ? 'Pose detected' : 'No pose — get in position',
                          style: const TextStyle(color: Colors.white70, fontSize: 12,
                              shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress >= 1.0 ? Colors.greenAccent : _accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // No camera permission fallback
          if (!_cameraPermissionGranted)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
                    const SizedBox(height: 16),
                    const Text('Camera permission required',
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: openAppSettings,
                      style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFC6A85A)),
                      child: const Text('Open Settings', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
