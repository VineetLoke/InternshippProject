/// Utility functions for date and duration formatting.
class DateHelpers {
  DateHelpers._();

  /// Formats a [Duration] as "Xh Ym Zs".
  static String formatDuration(Duration duration) {
    if (duration.isNegative) return '0s';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  /// Formats seconds as "HH:MM:SS" (for countdown timers).
  static String formatTimer(int totalSeconds) {
    if (totalSeconds <= 0) return '00:00:00';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${_pad(h)}:${_pad(m)}:${_pad(s)}';
  }

  /// Formats milliseconds to "Xh Ym" or "Xm" string.
  static String formatScreenTime(int ms) {
    if (ms <= 0) return '0m';
    final hours = ms ~/ 3600000;
    final minutes = (ms % 3600000) ~/ 60000;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '<1m';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
