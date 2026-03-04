import 'dart:async';
import 'package:flutter/material.dart';
import '../services/pushup_service.dart';
import '../services/reddit_usage_service.dart';

/// Full-screen pushup challenge to earn 10 more minutes of Reddit.
///
/// Uses the device's proximity sensor: place the phone face-up on the floor
/// and do pushups over it.  Each down-up cycle counts as one rep.
class PushupChallengeScreen extends StatefulWidget {
  const PushupChallengeScreen({Key? key}) : super(key: key);

  @override
  State<PushupChallengeScreen> createState() => _PushupChallengeScreenState();
}

class _PushupChallengeScreenState extends State<PushupChallengeScreen>
    with SingleTickerProviderStateMixin {
  static const int _requiredPushups = 100;

  final _pushupService = PushupService();
  final _redditService = RedditUsageService();
  StreamSubscription<int>? _countSub;

  int _count = 0;
  bool _isDetecting = false;
  bool _redeemed = false;
  bool _sensorError = false;
  String _redditRemaining = '--';

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

  Future<void> _startDetection() async {
    final started = await _pushupService.start();
    if (!started) {
      setState(() => _sensorError = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No proximity sensor found on this device.'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    final success = await _pushupService.redeemForRedditTime();
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
    _pushupService.stop();
    _pushupService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final progress = (_count / _requiredPushups).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('Pushup Challenge'),
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

              // ── Reddit status chip ─────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _redditRemaining,
                  style: TextStyle(
                      color: Colors.orange.shade200, fontSize: 14),
                ),
              ),

              const Spacer(flex: 1),

              // ── Circular progress ──────────────────────────────────
              ScaleTransition(
                scale: _isDetecting ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
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
                                : Colors.orange.shade400,
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

              // ── Instructions ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'How it works',
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
                        '4', 'Each down ↓ up ↑ = 1 pushup (≥0.8s each)'),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Start / Stop button ────────────────────────────────
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
                      backgroundColor:
                          _isDetecting ? Colors.red.shade700 : Colors.orange.shade700,
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
              color: Colors.orange.shade700,
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
