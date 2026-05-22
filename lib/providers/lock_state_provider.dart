import 'package:flutter/material.dart';
import '../services/app_block_service.dart';
import '../services/password_manager.dart';
import '../services/permission_service.dart';
import '../services/step_challenge.dart';
import '../services/timer_service.dart';

class LockStateProvider extends ChangeNotifier {
  final _appBlockService = AppBlockService();
  final _passwordManager = PasswordManager();
  final _stepChallenge = StepChallengeService();
  final _timerService = TimerService();
  final _permissionService = PermissionService();

  bool _isLocked = false;
  bool _passwordSet = false;
  int _remainingDays = 30;
  DateTime? _lockEndDate;
  bool _emergencyUnlockRequested = false;
  Duration _remainingDelay = Duration.zero;
  int _currentSteps = 0;
  bool _stepChallengeComplete = false;

  bool get isLocked => _isLocked;
  bool get passwordSet => _passwordSet;
  int get remainingDays => _remainingDays;
  DateTime? get lockEndDate => _lockEndDate;
  bool get emergencyUnlockRequested => _emergencyUnlockRequested;
  Duration get remainingDelay => _remainingDelay;
  int get currentSteps => _currentSteps;
  bool get stepChallengeComplete => _stepChallengeComplete;

  Future<bool> initializeLock() async {
    final success = await _appBlockService.initializeLock();
    if (!success) {
      return false;
    }
    await updateLockStatus();
    notifyListeners();
    return true;
  }

  Future<void> updateLockStatus() async {
    try {
      final status = await _appBlockService
          .getLockStatus()
          .timeout(const Duration(seconds: 2));
      _isLocked = status['locked'] ?? false;
      _remainingDays = status['remainingDays'] ?? 0;
      _lockEndDate = status['endDate'];
    } catch (e) {
      debugPrint('Error updating lock status: $e');
    }

    try {
      _passwordSet = await _passwordManager
          .hasPassword()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
    } catch (e) {
      debugPrint('Error checking password: $e');
    }

    try {
      _emergencyUnlockRequested = await _timerService
          .hasEmergencyUnlockRequest()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      _remainingDelay = await _timerService
          .getRemainingTime()
          .timeout(const Duration(seconds: 2), onTimeout: () => Duration.zero);
      if (_emergencyUnlockRequested) {
        await _stepChallenge.initialize();
        _currentSteps = _stepChallenge.getCurrentSteps();
        _stepChallengeComplete = await _stepChallenge
            .isChallengeComplete()
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
      } else {
        _currentSteps = 0;
        _stepChallengeComplete = false;
      }
    } catch (e) {
      debugPrint('Error restoring emergency unlock state: $e');
    }

    notifyListeners();
  }

  Future<bool> setPassword(String password) async {
    final success = await _passwordManager.setPassword(password);
    if (success) {
      _passwordSet = true;
      notifyListeners();
    }
    return success;
  }

  Future<bool> verifyPassword(String password) async {
    return await _passwordManager.verifyPassword(password);
  }

  Future<void> requestEmergencyUnlock() async {
    final requested = await _timerService.requestEmergencyUnlock();
    if (!requested) return;

    _emergencyUnlockRequested = true;
    _remainingDelay = await _timerService.getRemainingTime();

    _timerService.startCountdown((remaining) {
      _remainingDelay = remaining;
      notifyListeners();
    });

    final hasPermission = await _permissionService.requestActivityRecognition();
    if (hasPermission) {
      await _stepChallenge.initialize();
      _currentSteps = _stepChallenge.getCurrentSteps();
      _stepChallengeComplete = await _stepChallenge.isChallengeComplete();
      _stepChallenge.startMonitoring((steps) {
        _currentSteps = steps;
        _stepChallengeComplete = _stepChallenge.getRemainingSteps() == 0;
        notifyListeners();
      });
    } else {
      _currentSteps = 0;
      _stepChallengeComplete = false;
      debugPrint('ACTIVITY_RECOGNITION not granted - step challenge disabled');
    }

    notifyListeners();
  }

  Future<void> cancelEmergencyUnlock() async {
    await _timerService.cancelEmergencyUnlock();
    _stepChallenge.stopMonitoring();
    await _stepChallenge.resetProgress();
    _emergencyUnlockRequested = false;
    _remainingDelay = Duration.zero;
    _currentSteps = 0;
    _stepChallengeComplete = false;
    notifyListeners();
  }

  Future<void> checkStepChallenge() async {
    _stepChallengeComplete = await _stepChallenge.isChallengeComplete();
    _currentSteps = _stepChallenge.getCurrentSteps();
    notifyListeners();
  }

  Future<String?> getPasswordAfterChallenge() async {
    final isDelayComplete = await _timerService.isEmergencyUnlockDelayComplete();
    final isChallengeComplete = await _stepChallenge.isChallengeComplete();

    if (isDelayComplete && isChallengeComplete) {
      return await _passwordManager.getPasswordAfterChallenge();
    }
    return null;
  }

  Future<void> unlockApp() async {
    await _appBlockService.unlock();
    await _timerService.cancelEmergencyUnlock();
    _stepChallenge.stopMonitoring();
    await _stepChallenge.resetProgress();
    _isLocked = false;
    _emergencyUnlockRequested = false;
    _remainingDelay = Duration.zero;
    _currentSteps = 0;
    _stepChallengeComplete = false;
    _timerService.stopCountdown();
    notifyListeners();
  }

  double getStepProgress() {
    return _stepChallenge.getProgress();
  }

  int getRemainingSteps() {
    return _stepChallenge.getRemainingSteps();
  }

  @override
  void dispose() {
    _timerService.stopCountdown();
    _stepChallenge.stopMonitoring();
    super.dispose();
  }
}
