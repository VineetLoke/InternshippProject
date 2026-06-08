import 'package:flutter/material.dart';
import '../controller/social_media_block_controller.dart';
import '../model/blocked_app.dart';
import '../model/blocked_app_status.dart';

/// Card that shows the block status for a single social media app.
/// Used on the home screen and in any other app list.
class BlockedAppCard extends StatefulWidget {
  final BlockedApp app;
  final IconData icon;
  final MaterialColor color;
  final VoidCallback? onRequestAccess;

  const BlockedAppCard({
    Key? key,
    required this.app,
    required this.icon,
    required this.color,
    this.onRequestAccess,
  }) : super(key: key);

  @override
  State<BlockedAppCard> createState() => _BlockedAppCardState();
}

class _BlockedAppCardState extends State<BlockedAppCard> {
  BlockedAppStatus _status = const BlockedAppStatus();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final controller = SocialMediaBlockController(widget.app);
    final status = await controller.getStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _isLoading = false;
      });
    }
  }

  String get _formattedRemaining {
    final s = _status.tempUnlockRemainingSeconds;
    if (s <= 0) return '0s';
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0 ? '${m}m ${sec}s' : '${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final color = widget.color;
    final isLocked = _status.isLocked;
    final isTempUnlock = _status.isTempUnlockActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isTempUnlock
            ? Colors.green.shade50
            : isLocked
                ? color.shade50
                : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTempUnlock
              ? Colors.green.shade200
              : isLocked
                  ? color.shade200
                  : Colors.grey.shade200,
        ),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isTempUnlock
                            ? Colors.green.shade100
                            : isLocked
                                ? color.shade100
                                : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon,
                          color: isTempUnlock
                              ? Colors.green.shade700
                              : isLocked
                                  ? color.shade700
                                  : Colors.grey.shade500,
                          size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.displayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            isTempUnlock
                                ? 'Unlocked: $_formattedRemaining remaining'
                                : isLocked
                                    ? 'Blocked · ${_status.attemptCount} attempts today'
                                    : 'Not blocked',
                            style: TextStyle(
                              fontSize: 12,
                              color: isTempUnlock
                                  ? Colors.green.shade700
                                  : isLocked
                                      ? color.shade700
                                      : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isTempUnlock)
                      _buildBadge('ACTIVE', Colors.green.shade600),
                  ],
                ),
                if (isLocked && !isTempUnlock && widget.onRequestAccess != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.fitness_center, size: 18),
                      label: Text(
                        'Do ${app.requiredPushups} Pushups for ${app.rewardText}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: widget.onRequestAccess,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  static Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
