import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

typedef StepCallback = void Function(int);

class StepChallengeService {
  static const String _challengeStartDayKey = 'challenge_start_day';
  static const String _stepsCompletedKey = 'steps_completed_today';
  static const int _stepTarget = 10000;

  late StreamSubscription<StepCount> _stepCountStream;
  int _currentSteps = 0;
  StepCallback? _onStepUpdate;

  /// Initialize step counter (request permissions if needed)
  Future<bool> initialize() async {
    try {
      // Check step count permission
      StepCount steps = await Pedometer.stepCountStream.first;
      _currentSteps = steps.steps;
      return true;
    } catch (e) {
      print('Error initializing step counter: $e');
      return false;
    }
  }

  /// Start monitoring steps
  void startMonitoring(StepCallback onUpdate) {
    _onStepUpdate = onUpdate;
    _resetIfNewDay();
    
    _stepCountStream = Pedometer.stepCountStream.listen(
      (StepCount stepCount) {
        _currentSteps = stepCount.steps;
        _onStepUpdate?.call(_currentSteps);
      },
      onError: (error) {
        print('Step count error: $error');
      },
    );
  }

  /// Stop monitoring steps
  void stopMonitoring() {
    _stepCountStream.cancel();
  }

  /// Check if challenge is completed
  Future<bool> isChallengeComplete() async {
    _resetIfNewDay();
    return _currentSteps >= _stepTarget;
  }

  /// Get current step count
  int getCurrentSteps() {
    return _currentSteps;
  }

  /// Get remaining steps needed
  int getRemainingSteps() {
    final remaining = _stepTarget - _currentSteps;
    return remaining > 0 ? remaining : 0;
  }

  /// Get progress percentage
  double getProgress() {
    return (_currentSteps / _stepTarget).clamp(0.0, 1.0);
  }

  /// Reset counter for new day
  Future<void> _resetIfNewDay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toString().split(' ')[0]; // YYYY-MM-DD
      
      final lastDay = prefs.getString(_challengeStartDayKey);
      
      if (lastDay != today) {
        await prefs.setString(_challengeStartDayKey, today);
        await prefs.setInt(_stepsCompletedKey, 0);
        _currentSteps = 0;
      }
    } catch (e) {
      print('Error resetting step counter: $e');
    }
  }

  /// Persist current step count
  Future<void> persistSteps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_stepsCompletedKey, _currentSteps);
    } catch (e) {
      print('Error persisting steps: $e');
    }
  }
}
