enum PushupState { up, down }

class PushupCounter {
  static const double downAngleThreshold = 95.0; // Slightly higher for friendly detection
  static const double upAngleThreshold = 150.0;  // Slightly lower for friendly detection

  PushupState _state = PushupState.up;
  int _count = 0;

  int get count => _count;
  PushupState get state => _state;

  /// Updates the pushup state machine with the current elbow angle.
  /// Returns true if a pushup rep was completed.
  bool update(double elbowAngle) {
    if (_state == PushupState.up && elbowAngle < downAngleThreshold) {
      _state = PushupState.down;
    } else if (_state == PushupState.down && elbowAngle > upAngleThreshold) {
      _state = PushupState.up;
      _count++;
      return true;
    }
    return false;
  }

  void reset() {
    _count = 0;
    _state = PushupState.up;
  }
}
