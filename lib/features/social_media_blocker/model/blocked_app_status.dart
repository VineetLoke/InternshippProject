/// Immutable status for a single blocked app.
class BlockedAppStatus {
  final bool isLocked;
  final bool isTempUnlockActive;
  final int tempUnlockRemainingSeconds;
  final int remainingDays;
  final int attemptCount;
  final int lockDurationDays;

  const BlockedAppStatus({
    this.isLocked = false,
    this.isTempUnlockActive = false,
    this.tempUnlockRemainingSeconds = 0,
    this.remainingDays = 0,
    this.attemptCount = 0,
    this.lockDurationDays = 17,
  });

  factory BlockedAppStatus.fromMap(Map<String, dynamic> map) {
    return BlockedAppStatus(
      isLocked: (map['isLocked'] ?? false) as bool,
      isTempUnlockActive: (map['isTempUnlockActive'] ?? false) as bool,
      tempUnlockRemainingSeconds: (map['tempUnlockRemainingSeconds'] ?? 0) as int,
      remainingDays: (map['remainingDays'] ?? 0) as int,
      attemptCount: (map['attemptCount'] ?? 0) as int,
      lockDurationDays: (map['lockDurationDays'] ?? 17) as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isLocked': isLocked,
      'isTempUnlockActive': isTempUnlockActive,
      'tempUnlockRemainingSeconds': tempUnlockRemainingSeconds,
      'remainingDays': remainingDays,
      'attemptCount': attemptCount,
      'lockDurationDays': lockDurationDays,
    };
  }
}
