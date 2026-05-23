import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pushup_service.dart';

/// Generic emergency unlock screen for any blocked app.
///
/// Pass the app name and the method channel name via route arguments:
///   Navigator.pushNamed(context, '/app_pushup_challenge', arguments: {
///     'appName': 'Reddit',
///     'challengeMethod': 'completeRedditEmergencyChallenge',
///   });
///
/// Requires 50 pushups to grant 15 minutes of access.
class AppPushupChallengeScreen extends StatefulWidget {
  const AppPushupChallengeScreen({Key? key}) : super(key: key);

  @override
  State<AppPushupChallengeScreen> createState() =>
      _AppPushupChallengeScreenState();
}

class _AppPushupChallengeScreenState extends State<AppPushupChallengeScreen>
    with SingleTickerProviderStateMixin {
  static const int _requiredPushups = 50;
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  final _pushupService = PushupService();
  StreamSubscription<int>? _countSub;

  int _count = 0;
  bool _isDetecting = false;
  bool _redeemed = false;
  bool _sensorError = false;

  String _appName = '';
  String _challengeMethod = '';

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
    if (args != null) {
      _appName = args['appName'] ?? 'App';
      _challengeMethod = args['challengeMethod'] ?? '';
    }
  }

  Future<void> _startDetection() async {
    await _pushupService.reset();
    final started = await _pushupService.start();
    if (!started) {
      setState(() => _sensorError = true);
      return;
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
            '$_appName unlocked for 15 minutes.\n\n'
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
    final colorScheme = Theme.of(context).colorScheme;
    final progress = (_count / _requiredPushups).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: Text('$_appName Emergency Unlock'),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 20),

              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
                ),
                child: Text(
                  '50 pushups = 15 min access',
                  style: TextStyle(color: colorScheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),

              const Spacer(flex: 1),

              ScaleTransition(
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
                          backgroundColor: const Color(0xFF222228),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0
                                ? const Color(0xFF2E7D63)
                                : colorScheme.primary,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_count',
                            style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          Text(
                            '/ $_requiredPushups',
                            style: TextStyle(
                                fontSize: 18,
                                color: colorScheme.secondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 1),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF222228)),
                ),
                child: Column(
                  children: [
                    Text(
                      'Emergency Unlock',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _instructionRow('1', 'Place phone face-up on the floor'),
                    _instructionRow('2', 'Tap "Start" then get into position'),
                    _instructionRow(
                        '3', 'Do pushups over the phone — chest near screen'),
                    _instructionRow(
                        '4', 'Complete 50 pushups to unlock for 15 min'),
                  ],
                ),
              ),

              const SizedBox(height: 24),

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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDetecting
                          ? colorScheme.error
                          : colorScheme.primary,
                      foregroundColor: _isDetecting ? Colors.white : colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        _isDetecting ? _stopDetection : _startDetection,
                  ),
                ),

              if (_sensorError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Proximity sensor not available on this device.',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instructionRow(String num, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style:
                      TextStyle(color: colorScheme.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: colorScheme.onSurface, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
