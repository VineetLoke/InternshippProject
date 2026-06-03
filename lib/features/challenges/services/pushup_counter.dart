import 'dart:math';

/// State machine for counting pushups based on elbow angle.
///
/// Pushup cycle:
///   UP (arms extended, angle > 160°)
///   → DOWN (arms bent, angle < 90°)
///   → UP (arms extended again = 1 rep completed)
///
/// Hysteresis deadzone between 90°-160° prevents false counts
/// from minor arm movements.
enum PushupPhase { up, down }

class PushupCounter {
  static const double _downThreshold = 90.0;  // Below this = DOWN position
  static const double _upThreshold = 160.0;   // Above this = UP position

  PushupPhase _currentPhase = PushupPhase.up;
  int _count = 0;

  int get count => _count;
  PushupPhase get currentPhase => _currentPhase;

  /// Feed a new elbow angle measurement.
  /// Returns true if a rep was just completed (transition from DOWN → UP).
  bool update(double elbowAngle) {
    switch (_currentPhase) {
      case PushupPhase.up:
        // Waiting for user to go DOWN
        if (elbowAngle < _downThreshold) {
          _currentPhase = PushupPhase.down;
        }
        return false;

      case PushupPhase.down:
        // Waiting for user to come back UP
        if (elbowAngle > _upThreshold) {
          _currentPhase = PushupPhase.up;
          _count++;
          return true; // Rep completed!
        }
        return false;
    }
  }

  /// Returns a form feedback string based on current angle and phase.
  String getFormFeedback(double elbowAngle) {
    switch (_currentPhase) {
      case PushupPhase.up:
        if (elbowAngle > _upThreshold) {
          return 'Go down! 👇';
        }
        return 'Keep going down...';

      case PushupPhase.down:
        if (elbowAngle < _downThreshold) {
          return 'Push up! 👆';
        }
        return 'Keep pushing up...';
    }
  }

  /// Reset counter to zero.
  void reset() {
    _count = 0;
    _currentPhase = PushupPhase.up;
  }

  /// Calculate the angle between three points (in degrees).
  /// Used for elbow angle: shoulder → elbow → wrist.
  static double calculateAngle(
    double ax, double ay,  // Point A (shoulder)
    double bx, double by,  // Point B (elbow - vertex)
    double cx, double cy,  // Point C (wrist)
  ) {
    final ba = [ax - bx, ay - by]; // Vector BA
    final bc = [cx - bx, cy - by]; // Vector BC

    final dotProduct = ba[0] * bc[0] + ba[1] * bc[1];
    final magnitudeBA = sqrt(ba[0] * ba[0] + ba[1] * ba[1]);
    final magnitudeBC = sqrt(bc[0] * bc[0] + bc[1] * bc[1]);

    if (magnitudeBA == 0 || magnitudeBC == 0) return 180.0;

    final cosAngle = (dotProduct / (magnitudeBA * magnitudeBC))
        .clamp(-1.0, 1.0);
    return acos(cosAngle) * (180.0 / pi);
  }
}
