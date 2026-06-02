import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/platform_channel_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isInstagramBlocked = true;
  int _tempUnlockSecondsRemaining = 0;
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadState() async {
    final blocked = await PlatformChannelService.instance.isInstagramBlocked();
    final remaining = await PlatformChannelService.instance.getTempUnlockRemaining();
    if (mounted) {
      setState(() {
        _isInstagramBlocked = blocked;
        _tempUnlockSecondsRemaining = remaining;
        _loading = false;
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      final remaining = await PlatformChannelService.instance.getTempUnlockRemaining();
      setState(() {
        _tempUnlockSecondsRemaining = remaining;
      });
    });
  }

  Future<void> _toggleBlock(bool value) async {
    setState(() => _loading = true);
    await PlatformChannelService.instance.setInstagramBlocked(value);
    await _loadState();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentlyUnlocked = _tempUnlockSecondsRemaining > 0;

    return Scaffold(
      backgroundColor: const Color(0xff0a0a1a),
      appBar: AppBar(
        title: const Text(
          "FocusLock",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadState,
          )
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xff6c63ff)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Lock/Unlock Card
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: const Color(0xff16213e),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isCurrentlyUnlocked 
                            ? const Color(0xff00d4aa) 
                            : const Color(0xff6c63ff),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isCurrentlyUnlocked 
                                  ? const Color(0xff00d4aa) 
                                  : const Color(0xff6c63ff))
                              .withOpacity(0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(
                          isCurrentlyUnlocked ? Icons.lock_open : Icons.lock,
                          color: isCurrentlyUnlocked 
                              ? const Color(0xff00d4aa) 
                              : const Color(0xff6c63ff),
                          size: 80,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          isCurrentlyUnlocked ? "Instagram Unlocked" : "Instagram Blocked",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isCurrentlyUnlocked
                              ? "Temporary access window active."
                              : "Get pushup challenge ready to unlock.",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                        if (isCurrentlyUnlocked) ...[
                          const SizedBox(height: 24),
                          Text(
                            _formatDuration(_tempUnlockSecondsRemaining),
                            style: const TextStyle(
                              color: Color(0xff00d4aa),
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Simple circular progress for duration tracking
                          SizedBox(
                            width: 150,
                            child: LinearProgressIndicator(
                              value: _tempUnlockSecondsRemaining / 600.0, // max 10 min
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xff00d4aa)),
                            ),
                          )
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Blocker Configuration Switch Card
                  Card(
                    color: const Color(0xff1a1a2e),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.block, color: Color(0xff6c63ff), size: 28),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Instagram Protection",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isInstagramBlocked ? "Blocking Enabled" : "Blocking Disabled",
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Switch(
                            value: _isInstagramBlocked,
                            onChanged: _toggleBlock,
                            activeColor: const Color(0xff6c63ff),
                            activeTrackColor: const Color(0xff6c63ff).withOpacity(0.3),
                            inactiveThumbColor: Colors.white30,
                            inactiveTrackColor: Colors.white10,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Action Button
                  if (!isCurrentlyUnlocked && _isInstagramBlocked)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff6c63ff),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 4,
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/pushup-challenge');
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fitness_center),
                            SizedBox(width: 12),
                            Text(
                              "Do 10 Pushups to Unlock",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
