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

  // Getters
  bool get isLocked => _isLocked;
  bool get passwordSet => _passwordSet;
  int get remainingDays => _remainingDays;
  DateTime? get lockEndDate => _lockEndDate;
  bool get emergencyUnlockRequested => _emergencyUnlockRequested;
  Duration get remainingDelay => _remainingDelay;
  int get currentSteps => _currentSteps;
  bool get stepChallengeComplete => _stepChallengeComplete;

  /// Initialize lock state
  Future<void> initializeLock() async {
    await _appBlockService.initializeLock();
    await updateLockStatus();
    notifyListeners();
  }

  /// Update lock status from service — also reloads persisted password flag.
  /// Internal operations are individually time-boxed so this never blocks
  /// the caller for more than ~2 seconds total.
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
      // Secure storage read is time-boxed: Keystore init can stall on first
      // launch and must not freeze the splash screen.
      _passwordSet = await _passwordManager
          .hasPassword()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
    } catch (e) {
      debugPrint('Error checking password: $e');
    }
    notifyListeners();
  }

  /// Set password
  Future<bool> setPassword(String password) async {
    final success = await _passwordManager.setPassword(password);
    if (success) {
      _passwordSet = true;
      notifyListeners();
    }
    return success;
  }

  /// Verify password
  Future<bool> verifyPassword(String password) async {
    return await _passwordManager.verifyPassword(password);
  }

  /// Request emergency unlock
  Future<void> requestEmergencyUnlock() async {
    await _timerService.requestEmergencyUnlock();
    _emergencyUnlockRequested = true;

    // Start countdown
    _timerService.startCountdown((remaining) {
      _remainingDelay = remaining;
      notifyListeners();
    });

    // Guard step challenge behind runtime permission
    final hasPermission = await _permissionService.requestActivityRecognition();
    if (hasPermission) {
      await _stepChallenge.initialize();
      _stepChallenge.startMonitoring((steps) {
        _currentSteps = steps;
        notifyListeners();
      });
    } else {
      debugPrint('ACTIVITY_RECOGNITION not granted — step challenge disabled');
    }

    notifyListeners();
  }

  /// Cancel emergency unlock
  Future<void> cancelEmergencyUnlock() async {
    await _timerService.cancelEmergencyUnlock();
    _stepChallenge.stopMonitoring();
    _emergencyUnlockRequested = false;
    _currentSteps = 0;
    _stepChallengeComplete = false;
    notifyListeners();
  }

  /// Check if step challenge is complete
  Future<void> checkStepChallenge() async {
    _stepChallengeComplete = await _stepChallenge.isChallengeComplete();
    notifyListeners();
  }

  /// Get password after challenge completion
  Future<String?> getPasswordAfterChallenge() async {
    final isDelayComplete = await _timerService.isEmergencyUnlockDelayComplete();
    final isChallengeComplete = await _stepChallenge.isChallengeComplete();
    
    if (isDelayComplete && isChallengeComplete) {
      return await _passwordManager.getPasswordAfterChallenge();
    }
    return null;
  }

  /// Unlock app
  Future<void> unlockApp() async {
    await _appBlockService.unlock();
    _isLocked = false;
    _emergencyUnlockRequested = false;
    _stepChallenge.stopMonitoring();
    _timerService.stopCountdown();
    notifyListeners();
  }

  /// Get step progress percentage
  double getStepProgress() {
    return _stepChallenge.getProgress();
  }

  /// Get remaining steps
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
