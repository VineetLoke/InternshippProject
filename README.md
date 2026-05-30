# FocusLock

A Flutter + Kotlin Android app that blocks **Instagram, Reddit, and Twitter/X** with a delayed emergency unlock requiring physical effort (pushups or steps). Uses Android Accessibility Service, overlay permissions, device admin, and ML Kit pose detection to prevent bypasses.

## Architecture

```
lib/                          # Flutter/Dart UI & state
├── main.dart                 # Entry point, routing, theme
├── core/
│   ├── presentation/screens/ # SplashScreen, PermissionsScreen, SetupScreen
│   └── services/             # PasswordManager (flutter_secure_storage), PermissionService
└── features/
    ├── app_blocker/
    │   ├── presentation/     # LockScreen, EmergencyUnlockScreen, LockStateProvider
    │   └── services/         # AppBlockService, TimerService, Instagram/Reddit/Twitter block services
    ├── dashboard/
    │   ├── presentation/     # HomeScreen
    │   └── services/         # UsageService, RedditUsageService, AppLogService
    ├── challenges/
    │   ├── presentation/     # PushupChallengeScreen (camera ML Kit), step challenge UI
    │   └── services/         # CameraPushupDetector, StepChallengeService
    ├── chrome_filter/
    │   └── services/         # ChromeFilterService (incognito policy)
    └── uninstall_protection/
        ├── presentation/     # UninstallProtectionScreen
        └── services/         # UninstallProtectionService

android/                      # Kotlin native layer
└── app/src/main/kotlin/com/example/focus_lock/
    ├── MainActivity.kt       # MethodChannel hub (60+ methods)
    ├── blockers/
    │   ├── InstagramBlocker.kt   # Singleton: lock state, temp unlock, BACK spam
    │   ├── RedditBlocker.kt      # Same pattern
    │   ├── TwitterBlocker.kt     # Same pattern
    │   └── BrowserIncognitoBlocker.kt  # Private tab detection for Chrome/Firefox/Opera/Samsung
    ├── services/
    │   ├── AccessibilityMonitor.kt   # Core: foreground detection, state machine, overlays
    │   ├── AppBlockingService.kt     # Foreground watchdog service
    │   ├── ChromeIncognitoPolicy.kt  # DevicePolicyManager app restrictions
    │   ├── PushupDetectorService.kt  # Proximity-sensor pushup detection
    │   ├── AppIconManager.kt         # Hide/show launcher icon
    │   └── UninstallProtectionManager.kt  # Cooldown windows, challenge tracking
    ├── ui/
    │   ├── LockScreenOverlay.kt      # Full-screen block overlay with quotes
    │   ├── DisciplineWarningOverlay.kt  # Incognito browser warning overlay
    │   └── UninstallChallengeOverlay.kt  # 200-pushup challenge overlay
    ├── storage/database/
    │   ├── AppDatabase.kt, AppOpenLog.kt, AppOpenLogDao.kt  # Room DB
    ├── BootReceiver.kt        # Restart services after reboot
    ├── SecretCodeReceiver.kt  # Dial *#*#1717#*#* to restore hidden icon
    └── FocusLockDeviceAdminReceiver.kt  # Device admin for uninstall protection
```

## Core Features

| Feature | Implementation |
|---------|---------------|
| App blocking | AccessibilityService detects `com.instagram.android`, `com.reddit.frontpage`, `com.twitter.android` → overlay + GLOBAL_ACTION_BACK |
| 30-day lock | SharedPreferences + native prefs; survives reboot |
| Temp unlock | 100 verified pushups (camera ML Kit or proximity sensor) = 10 min access |
| Emergency unlock | 1-hour delay + 10,000 steps → password revealed |
| Browser incognito blocking | Accessibility node scanning for "incognito"/"private"/"secret" keywords |
| Uninstall protection | Device admin + hidden launcher icon + 200-pushup challenge to disable |
| Pushup verification | Camera ML Kit (elbow angle via PoseDetection) OR proximity sensor (chest near/far cycles) |
| Step counting | `pedometer_2` + `ACTIVITY_RECOGNITION` permission |
| App open logging | Room database records every blocked attempt |

## State Machine (DisciplineState)

```
IDLE → APP_BLOCKED (when blocked app opens)
     → CHROME_INCOGNITO_BLOCKED (private tab detected)
APP_BLOCKED → IDLE (user navigates away)
            → REDDIT_CHALLENGE_ACTIVE (pushups started)
REDDIT_CHALLENGE_ACTIVE → REDDIT_TEMP_UNLOCK (100 pushups done)
REDDIT_TEMP_UNLOCK → APP_BLOCKED (10 min expires)
CHROME_INCOGNITO_BLOCKED → IDLE (5 sec warning elapses)
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_secure_storage` | AES-256 encrypted password storage via Android Keystore |
| `permission_handler` | Runtime permission requests |
| `pedometer_2` | Step counter |
| `provider` | State management (ChangeNotifier) |
| `shared_preferences` | Lock state persistence |
| `google_mlkit_pose_detection` | Camera-based pushup form verification |
| `camera` | Camera preview for pushup detection |
| `intl` | Date/time formatting |
| **Native (Kotlin)** | Room DB, DevicePolicyManager, AccessibilityService, WindowManager overlays |

## Permissions

- `SYSTEM_ALERT_WINDOW` — overlay lock screen
- `PACKAGE_USAGE_STATS` — screen time tracking
- `ACTIVITY_RECOGNITION` — step counter
- `POST_NOTIFICATIONS` — foreground service
- `CAMERA` — pushup pose detection
- `BIND_ACCESSIBILITY_SERVICE` — app detection & blocking
- `BIND_DEVICE_ADMIN` — uninstall protection
- `RECEIVE_BOOT_COMPLETED` — restart after reboot
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — prevent background kill
- `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_SPECIAL_USE`

## Build

```bash
flutter pub get
flutter run -d <device>
flutter build apk --release
```

## Security Notes

- Password is stored in `flutter_secure_storage` (AES-256-GCM via Android Keystore) — not in SharedPreferences
- Blocker modules use **separate** SharedPreferences files (`instagram_blocker_prefs`, etc.) that Flutter's "Reset" flow cannot clear
- Device admin + hidden launcher icon prevents casual uninstall
- Emergency unlock requires both time delay AND physical steps — no single bypass
- AccessibilityService also monitors Settings/Installer for uninstall guard
- Volume-up 3x within 2s triggers emergency reset (removes stuck overlays)
