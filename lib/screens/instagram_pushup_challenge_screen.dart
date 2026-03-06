import 'dart:async';
import 'package:flutter/material.dart';
import '../services/pushup_service.dart';
import '../services/instagram_block_service.dart';

/// Emergency unlock screen for Instagram.
///
/// Requires exactly 50 pushups to grant 15 minutes of access.
/// Uses the proximity sensor (same as the Reddit pushup challenge).
class InstagramPushupChallengeScreen extends StatefulWidget {
  const InstagramPushupChallengeScreen({Key? key}) : super(key: key);

  @override
  State<InstagramPushupChallengeScreen> createState() =>
      _InstagramPushupChallengeScreenState();
}

class _InstagramPushupChallengeScreenState
    extends State<InstagramPushupChallengeScreen>
    with SingleTickerProviderStateMixin {
  static const int _requiredPushups = 50;

  final _pushupService = PushupService();
  final _igService = InstagramBlockService();
  StreamSubscription<int>? _countSub;

  int _count = 0;
  bool _isDetecting = false;
  bool _redeemed = false;
  bool _sensorError = false;

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
    final success = await _igService.completeEmergencyChallenge();
    setState(() => _redeemed = success);

    if (success && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Challenge Complete'),
          content: const Text(
            'Instagram unlocked for 15 minutes.\n\n'
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
        title: const Text('Instagram Emergency Unlock'),
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
              const SizedBox(height: 20),

              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '50 pushups = 15 min access',
                  style: TextStyle(color: Colors.purpleAccent, fontSize: 14),
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
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0
                                ? Colors.greenAccent
                                : Colors.purpleAccent,
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
                                fontSize: 18,
                                color: Colors.grey.shade400),
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
                      style: const TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDetecting
                          ? Colors.red.shade700
                          : Colors.purple.shade700,
                      foregroundColor: Colors.white,
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
                    style: TextStyle(color: Colors.red.shade300),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.purple.shade700,
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
                style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
