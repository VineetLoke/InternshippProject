import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/platform_channel_service.dart';

/// Dashboard home screen showing Instagram block status,
/// temp unlock countdown, and the pushup challenge button.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isBlocked = true;
  int _unlockSecondsRemaining = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadState();
    }
  }

  Future<void> _loadState() async {
    final service =
        Provider.of<PlatformChannelService>(context, listen: false);
    final blocked = await service.isInstagramBlocked();
    final remaining = await service.getTempUnlockRemaining();

    if (!mounted) return;
    setState(() {
      _isBlocked = blocked;
      _unlockSecondsRemaining = remaining;
    });

    // Start countdown if there's time remaining
    _countdownTimer?.cancel();
    if (_unlockSecondsRemaining > 0) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _unlockSecondsRemaining--;
        if (_unlockSecondsRemaining <= 0) {
          _unlockSecondsRemaining = 0;
          timer.cancel();
        }
      });
    });
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  bool get _isTempUnlocked => _unlockSecondsRemaining > 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // App title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'FocusLock',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/permissions');
                    },
                    icon: const Icon(Icons.settings_rounded,
                        color: Color(0xFF8888A0)),
                  ),
                ],
              ),

              const SizedBox(height: 48),

              // Status card
              _buildStatusCard(),

              const SizedBox(height: 24),

              // Timer card (only when temp unlocked)
              if (_isTempUnlocked) _buildTimerCard(),

              const Spacer(),

              // Pushup challenge button
              _buildPushupButton(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final isLocked = !_isTempUnlocked && _isBlocked;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLocked
              ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
              : [const Color(0xFF1B3A1B), const Color(0xFF0D2B0D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isLocked
              ? const Color(0xFF7C4DFF).withOpacity(0.3)
              : const Color(0xFF4CAF50).withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isLocked
                    ? const Color(0xFF7C4DFF)
                    : const Color(0xFF4CAF50))
                .withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Lock/Unlock icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isLocked
                      ? const Color(0xFFFF5252)
                      : const Color(0xFF4CAF50))
                  .withOpacity(0.15),
            ),
            child: Center(
              child: Text(
                isLocked ? '🔒' : '🔓',
                style: const TextStyle(fontSize: 40),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Status text
          Text(
            isLocked ? 'Instagram is BLOCKED' : 'Instagram is UNLOCKED',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isLocked
                  ? const Color(0xFFFF5252)
                  : const Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(height: 8),

          Text(
            isLocked
                ? 'Complete pushups to earn access'
                : 'You earned this! Enjoy responsibly.',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF8888A0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2A1A), Color(0xFF0D1F0D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4CAF50).withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_rounded,
              color: Color(0xFF4CAF50), size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Time Remaining',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8888A0),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(_unlockSecondsRemaining),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    color: Color(0xFF4CAF50),
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPushupButton() {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: _isTempUnlocked
            ? null
            : () {
                Navigator.of(context).pushNamed('/pushup-challenge');
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C4DFF),
          disabledBackgroundColor: const Color(0xFF2A2A40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 8,
          shadowColor: const Color(0xFF7C4DFF).withOpacity(0.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💪', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Text(
              _isTempUnlocked
                  ? 'Already Unlocked!'
                  : 'Do 10 Pushups to Unlock',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
