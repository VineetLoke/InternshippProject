import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/pushup_service.dart';

class PushupChallengeScreen extends StatefulWidget {
  const PushupChallengeScreen({super.key});

  @override
  State<PushupChallengeScreen> createState() => _PushupChallengeScreenState();
}

class _PushupChallengeScreenState extends State<PushupChallengeScreen>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  final _pushupService = PushupService();
  StreamSubscription<int>? _countSub;

  int _count = 0;
  bool _isDetecting = false;
  bool _redeemed = false;
  bool _sensorError = false;

  String _appName = '';
  int _requiredPushups = 50;
  String _rewardText = '';
  String _challengeMethod = '';
  Color _accentColor = Colors.teal;
  Color _accentColorShade = Colors.tealAccent;

  bool _cameraAvailable = false;
  bool _useCamera = false;
  bool _cameraPermissionGranted = false;

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
    _checkCameraAvailability();
  }

  Future<void> _checkCameraAvailability() async {
    final perm = await Permission.camera.status;
    final granted = perm.isGranted;
    final available = await _pushupService.isCameraAvailable();
    if (mounted) {
      setState(() {
        _cameraPermissionGranted = granted;
        _cameraAvailable = available;
        _useCamera = granted && available;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _appName = args['appName'] ?? 'App';
      _requiredPushups = args['requiredPushups'] ?? 50;
      _rewardText = args['rewardText'] ?? '15 min access';
      _challengeMethod = args['challengeMethod'] ?? '';
      _accentColor = Color(args['accentColor'] ?? 0xFF009688);
      _accentColorShade = _accentColor;
    }
  }

  Future<void> _toggleMode() async {
    if (_isDetecting) return;
    if (!_cameraPermissionGranted) {
      final status = await Permission.camera.request();
      if (!status.isGranted) return;
      setState(() => _cameraPermissionGranted = true);
    }
    setState(() => _useCamera = !_useCamera);
  }

  Future<void> _startDetection() async {
    final mode = _useCamera ? DetectionMode.camera : DetectionMode.proximity;

    if (mode == DetectionMode.proximity) {
      final started = await _pushupService.start(mode: mode);
      if (!started) {
        setState(() => _sensorError = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proximity sensor not available on this device.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    } else {
      await _pushupService.reset();
      final started = await _pushupService.start(mode: mode);
      if (!started) {
        setState(() => _sensorError = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera not available. Try proximity mode.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    _countSub = _pushupService.onCountChanged.listen((count) {
      if (mounted) {
        setState(() => _count = count);
        if (count >= _requiredPushups && !_redeemed) {
          _onChallengeComplete();
        }
      }
    });

    setState(() {
      _isDetecting = true;
      _count = 0;
    });
  }

  Future<void> _stopDetection() async {
    await _countSub?.cancel();
    _countSub = null;
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
          title: const Text('Challenge Complete'),
          content: Text(
            '$_appName $_rewardText.\n\n'
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
    _pushupService.stop();
    _pushupService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_count / _requiredPushups).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Text('$_appName Emergency Unlock'),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // Mode badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildModeBadge(),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_requiredPushups pushups = $_rewardText',
                      style: TextStyle(
                          color: _accentColorShade, fontSize: 14),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Camera preview takes most of the space in camera mode
              Expanded(
                flex: 3,
                child: _useCamera && _cameraAvailable
                    ? _buildCameraPreview()
                    : _buildProgressCircle(progress),
              ),

              const Spacer(flex: 1),

              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Emergency Unlock',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _instructionRow(
                        '1', 'Place phone face-up on the floor'),
                    _instructionRow(
                        '2', 'Tap "Start" then get into position'),
                    _instructionRow('3',
                        'Do pushups over the phone — chest near screen'),
                    _instructionRow(
                        '4', 'Complete $_requiredPushups pushups to unlock'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Start / Stop button
              if (!_redeemed)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    icon: Icon(
                      _isDetecting ? Icons.stop : Icons.play_arrow,
                      size: 28,
                    ),
                    label: Text(
                      _isDetecting ? 'Stop' : 'Start Pushup Detection',
                      style: const TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDetecting
                          ? Colors.red.shade700
                          : _accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        _isDetecting ? _stopDetection : _startDetection,
                  ),
                ),

              // Mode toggle
              if (!_isDetecting && _cameraAvailable)
                TextButton.icon(
                  icon: Icon(
                    _useCamera ? Icons.sensors : Icons.camera_alt,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                  label: Text(
                    _useCamera
                        ? 'Switch to proximity sensor'
                        : 'Switch to camera detection',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 13),
                  ),
                  onPressed: _toggleMode,
                ),

              if (_sensorError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Detection not available. Check camera permissions or use proximity mode.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red.shade300, fontSize: 12),
                  ),
                ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeBadge() {
    final icon = _useCamera ? Icons.camera_alt : Icons.sensors;
    final label = _useCamera ? 'Camera' : 'Proximity';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCircle(double progress) {
    return Center(
      child: ScaleTransition(
        scale: _isDetecting
            ? _pulseAnimation
            : const AlwaysStoppedAnimation(1.0),
        child: SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 12,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress >= 1.0
                        ? Colors.greenAccent
                        : _accentColorShade,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_count',
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '/ $_requiredPushups',
                    style: TextStyle(
                        fontSize: 18, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _pushupService.cameraDetector?.cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return _buildProgressCircle(
          (_count / _requiredPushups).clamp(0.0, 1.0));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CameraPreview(controller),
          // Overlay rep count on top of camera
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$_count',
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.8),
                      shadows: const [
                        Shadow(
                          blurRadius: 10,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '/ $_requiredPushups',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          // Progress ring
          Positioned(
            bottom: 16,
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                value: (_count / _requiredPushups).clamp(0.0, 1.0),
                strokeWidth: 4,
                backgroundColor: Colors.white12,
                valueColor:
                    AlwaysStoppedAnimation<Color>(_accentColorShade),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _instructionRow(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _accentColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style:
                    TextStyle(color: Colors.grey.shade300, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
