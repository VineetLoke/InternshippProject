# FocusLock Codebase Documentation

This document explains how the Flutter UI, Dart services, native Kotlin services, Android permissions, storage, and GitHub Actions workflow fit together.

## Product Summary

FocusLock is an Android-only Flutter app with a native Kotlin enforcement layer. It blocks Instagram, Reddit, and Twitter/X during a lock period, detects private browser tabs, supports emergency unlock flows, and adds uninstall resistance through device admin, launcher-icon hiding, overlays, and physical challenges.

The important split is:

- Flutter/Dart owns screens, navigation, user-visible state, permission prompts, and service wrappers.
- Kotlin owns enforcement: accessibility monitoring, foreground services, overlays, device admin, Room logging, package detection, and sensor-based pushup counting.
- Flutter and Kotlin communicate through one main `MethodChannel`: `com.example.focus_lock/app_block`.
- Kotlin also exposes `EventChannel`: `com.example.focus_lock/pushup_events` for proximity-sensor pushup count updates.

## Repository Layout

```text
.
├── README.md
├── pubspec.yaml
├── analysis_options.yaml
├── .github/workflows/build-apk.yml
├── lib/
│   ├── main.dart
│   ├── core/
│   └── features/
└── android/
    ├── build.gradle
    ├── settings.gradle
    └── app/src/main/
        ├── AndroidManifest.xml
        ├── kotlin/com/example/focus_lock/
        └── res/
```

## Flutter Entry Point

`lib/main.dart`

- Initializes Flutter binding.
- Installs global Flutter and async error logging.
- Creates `FocusLockApp`.
- Registers `LockStateProvider` through `provider`.
- Defines the route table:
  - `/` -> splash
  - `/permissions` -> permissions setup
  - `/setup` -> password / initial lock setup
  - `/home` -> dashboard
  - `/lock` -> lock screen
  - `/emergency` -> emergency unlock
  - `/pushup_challenge` -> Reddit camera pushup challenge
  - `/instagram_pushup_challenge` -> Instagram challenge
  - `/app_pushup_challenge` -> generic app challenge
  - `/uninstall_protection` -> uninstall protection UI

## Flutter Core Layer

### `PermissionService`

File: `lib/core/services/permission_service.dart`

Central wrapper around permission checks and Android settings navigation.

It handles:

- Accessibility service checks through native `isAccessibilityEnabled`.
- Opening Accessibility settings through native `openAccessibilitySettings`.
- Activity recognition permission for step counting.
- Overlay permission through native `hasOverlayPermission` / `openOverlaySettings`.
- Notification permission.
- Usage access through native `hasUsageStatsPermission`.
- Battery optimization exemption through native methods.
- Starting native blocking through `startBlocking`.

### `PasswordManager`

File: `lib/core/services/password_manager.dart`

Stores the user password using `flutter_secure_storage` with Android encrypted shared preferences. It exposes:

- `setPassword`
- `verifyPassword`
- `getPasswordAfterChallenge`
- `hasPassword`
- `clearPassword`

The password is not stored in normal `SharedPreferences`.

## Flutter State Management

### `LockStateProvider`

File: `lib/features/app_blocker/presentation/providers/lock_state_provider.dart`

This is the main Flutter state holder for the lock lifecycle.

It combines:

- `AppBlockService` for 30-day lock state.
- `PasswordManager` for password state.
- `TimerService` for the one-hour emergency delay.
- `StepChallengeService` for the 10,000-step emergency challenge.
- `PermissionService` for permission requests.

Important state:

- `_isLocked`
- `_passwordSet`
- `_remainingDays`
- `_lockEndDate`
- `_emergencyUnlockRequested`
- `_remainingDelay`
- `_currentSteps`
- `_stepChallengeComplete`

Key flows:

- `initializeLock()` starts the lock and tells native Kotlin to begin blocking.
- `requestEmergencyUnlock()` stores the request time, starts the countdown, requests activity recognition, then starts step monitoring.
- `getPasswordAfterChallenge()` only returns the password if both the one-hour delay and step challenge are complete.
- `unlockApp()` clears lock state only when emergency conditions are complete.

## Flutter Feature Modules

### App Blocking Services

Files:

- `lib/features/app_blocker/services/app_block_service.dart`
- `lib/features/app_blocker/services/instagram_block_service.dart`
- `lib/features/app_blocker/services/reddit_block_service.dart`
- `lib/features/app_blocker/services/twitter_block_service.dart`
- `lib/features/app_blocker/services/timer_service.dart`

`AppBlockService` stores the shared 30-day lock start time and duration in Flutter shared preferences. It also calls native `startBlocking` and `unlock`.

The app-specific services are thin wrappers around native blocker singletons:

- Instagram: `getInstagramBlockStatus`, `getInstagramAttemptCount`, `getInstagramTempUnlockRemaining`, `completeInstagramEmergencyChallenge`
- Reddit: `getRedditBlockStatus`, `getRedditAttemptCount`, `getRedditTempUnlockRemainingNew`, `completeRedditEmergencyChallenge`
- Twitter/X: `getTwitterBlockStatus`, `getTwitterAttemptCount`, `getTwitterTempUnlockRemaining`, `completeTwitterEmergencyChallenge`

`TimerService` stores the emergency unlock request timestamp and calculates the remaining time for the one-hour delay.

### Dashboard Services

Files:

- `lib/features/dashboard/services/usage_service.dart`
- `lib/features/dashboard/services/reddit_usage_service.dart`
- `lib/features/dashboard/services/app_log_service.dart`

`UsageService` reads Android `UsageStatsManager` data through Kotlin.

`RedditUsageService` reads Reddit daily usage and temp unlock state through Kotlin.

`AppLogService` reads Room database logs through Kotlin. Logs include app name, package name, and timestamp for blocked-app open attempts.

### Challenge Services

Files:

- `lib/features/challenges/services/step_challenge.dart`
- `lib/features/challenges/services/camera_pushup_detector.dart`
- `lib/features/challenges/presentation/widgets/pose_painter.dart`

`StepChallengeService` uses `pedometer_2` and persists:

- challenge day
- baseline step count
- steps completed today

Target: 10,000 steps.

`CameraPushupDetector` uses:

- `camera`
- `google_mlkit_pose_detection`

It detects pushups by:

- Reading camera frames.
- Running ML Kit pose detection.
- Computing shoulder-elbow-wrist angle.
- Checking body alignment.
- Counting a rep on a valid down-to-up transition.

`PosePainter` draws the detected skeleton on top of the camera preview.

### Chrome Filter

File: `lib/features/chrome_filter/services/chrome_filter_service.dart`

Thin Flutter wrapper around native Chrome policy methods:

- `getChromeFilterStatus`
- `applyChromeIncognitoPolicy`
- `removeChromeIncognitoPolicy`
- `isDeviceOwnerOrProfileOwner`

The policy route only works if the app is Device Owner or Profile Owner. Otherwise the accessibility keyword scanner is the fallback.

### Uninstall Protection

File: `lib/features/uninstall_protection/services/uninstall_protection_service.dart`

Flutter wrapper around native uninstall protection:

- hide/show launcher icon
- request device admin
- enable full protection
- check uninstall cooldown
- launch uninstall challenge overlay
- remove device admin during the allowed cooldown window

## Native Android Entry Point

### `MainActivity`

File: `android/app/src/main/kotlin/com/example/focus_lock/MainActivity.kt`

`MainActivity` is the native bridge between Flutter and Kotlin.

Responsibilities:

- Handles deep links from native overlays into Flutter routes.
- Registers the main method channel.
- Registers the pushup event channel.
- Starts `AppBlockingService`.
- Requests notification permission before foreground service startup.
- Provides native implementations for permissions, usage stats, app logs, pushup detector, Chrome policy, blocker status, and uninstall protection.

Main channel:

```text
com.example.focus_lock/app_block
```

Pushup event channel:

```text
com.example.focus_lock/pushup_events
```

## Native Method Channel Surface

`MainActivity` handles these method names:

### Permissions and Startup

- `isIgnoringBatteryOptimizations`
- `requestIgnoreBatteryOptimizations`
- `isAccessibilityEnabled`
- `openAccessibilitySettings`
- `startBlocking`
- `unlock`
- `isServiceRunning`
- `hasOverlayPermission`
- `openOverlaySettings`

### Reddit Usage and Pushups

- `getRedditUsageStatus`
- `getRedditRemainingSeconds`
- `startPushupDetection`
- `stopPushupDetection`
- `getPushupCount`
- `resetPushupCount`
- `redeemPushups`
- `grantRedditCameraPushupReward`

### Usage Stats and Logs

- `getScreenTimeData`
- `hasUsageStatsPermission`
- `openUsageStatsSettings`
- `getAppOpenLogs`
- `getAppOpenCount`
- `getAllAppOpenCounts`

### Chrome and Discipline State

- `getChromeFilterStatus`
- `applyChromeIncognitoPolicy`
- `removeChromeIncognitoPolicy`
- `isChromeIncognitoPolicyActive`
- `isDeviceOwnerOrProfileOwner`
- `getDisciplineState`
- `getRedditTempUnlockRemaining`

### App-Specific Blockers

- `getInstagramBlockStatus`
- `getInstagramAttemptCount`
- `getInstagramTempUnlockRemaining`
- `completeInstagramEmergencyChallenge`
- `getRedditBlockStatus`
- `getRedditAttemptCount`
- `getRedditTempUnlockRemainingNew`
- `completeRedditEmergencyChallenge`
- `getTwitterBlockStatus`
- `getTwitterAttemptCount`
- `getTwitterTempUnlockRemaining`
- `completeTwitterEmergencyChallenge`

### Uninstall Protection

- `getProtectionStatus`
- `hideAppIcon`
- `showAppIcon`
- `isIconHidden`
- `requestDeviceAdmin`
- `isDeviceAdminActive`
- `enableProtection`
- `isUninstallAllowed`
- `getCooldownRemaining`
- `launchUninstallChallenge`
- `removeDeviceAdmin`

## Native Enforcement Layer

### `AccessibilityMonitor`

File: `android/app/src/main/kotlin/com/example/focus_lock/services/AccessibilityMonitor.kt`

This is the central enforcement component.

It is an `AccessibilityService` that monitors foreground packages and browser UI trees.

Tracked packages:

- Instagram: `com.instagram.android`
- Reddit: `com.reddit.frontpage`
- Twitter/X: `com.twitter.android`
- Chrome: `com.android.chrome`
- Firefox: `org.mozilla.firefox`
- Opera: `com.opera.browser`
- Samsung Browser: `com.sec.android.app.sbrowser`

Core responsibilities:

- Detect blocked apps from accessibility events.
- Delegate Instagram/Reddit/Twitter detection to deterministic blocker singletons.
- Detect private browser surfaces and typed input through `BrowserIncognitoBlocker`.
- Show or stop overlay services.
- Force-close blocked apps using global BACK actions.
- Track Reddit foreground usage time.
- Log app open attempts into Room.
- Detect uninstall-related Settings screens.
- Provide an emergency overlay reset with volume-up triple press.
- Maintain `DisciplineState`.

Important safety logic:

- Events are debounced to reduce duplicate work.
- Settings and package installer events bypass debounce so uninstall attempts are detected quickly.
- Overlays have a watchdog to avoid stuck overlays.
- Leaving a blocked context cleans up overlays and returns to `IDLE`.

### `DisciplineState`

File: `android/app/src/main/kotlin/com/example/focus_lock/controllers/DisciplineState.kt`

State enum used by `AccessibilityMonitor`.

Important states include:

- `IDLE`
- `APP_BLOCKED`
- `CHROME_INCOGNITO_BLOCKED`
- `REDDIT_CHALLENGE_ACTIVE`
- `REDDIT_TEMP_UNLOCK`

## Native Blocker Singletons

Files:

- `android/app/src/main/kotlin/com/example/focus_lock/blockers/InstagramBlocker.kt`
- `android/app/src/main/kotlin/com/example/focus_lock/blockers/RedditBlocker.kt`
- `android/app/src/main/kotlin/com/example/focus_lock/blockers/TwitterBlocker.kt`

Each app-specific blocker follows the same pattern:

- Keeps its state in a dedicated native `SharedPreferences` file.
- Determines whether the lock is active.
- Counts open attempts.
- Shows the lock overlay.
- Schedules force-close BACK actions.
- Grants a 10-minute temp unlock after challenge completion.
- Restores temp unlock timers after process restart.
- Exposes `getStatus()` for Flutter.

These native preferences are intentionally separate from Flutter's reset path.

### Browser Incognito Blocker

File: `android/app/src/main/kotlin/com/example/focus_lock/blockers/BrowserIncognitoBlocker.kt`

Scans accessibility node text and structure for private browsing indicators across supported browsers.

It uses:

- package-specific keyword lists
- debounce/cache state
- recursive accessibility tree scanning
- typing-event checks

If a private browser surface is detected, `AccessibilityMonitor` starts `DisciplineWarningOverlay`.

## Native Services

### `AppBlockingService`

File: `android/app/src/main/kotlin/com/example/focus_lock/services/AppBlockingService.kt`

Foreground watchdog service. It creates a notification channel and keeps the app process active with `START_STICKY`. Actual blocking is handled by `AccessibilityMonitor`.

### `PushupDetectorService`

File: `android/app/src/main/kotlin/com/example/focus_lock/services/PushupDetectorService.kt`

Native proximity/accelerometer-based pushup detector used by the method/event channel path.

It exposes:

- `start`
- `stop`
- `getCount`
- `reset`
- callbacks for count and error updates

### `ChromeIncognitoPolicy`

File: `android/app/src/main/kotlin/com/example/focus_lock/services/ChromeIncognitoPolicy.kt`

Applies/removes Chrome managed configuration for incognito availability through `DevicePolicyManager`.

Requires Device Owner or Profile Owner privileges.

### `AppIconManager`

File: `android/app/src/main/kotlin/com/example/focus_lock/services/AppIconManager.kt`

Hides/shows the launcher icon by changing component enabled state. Also supports temporary show.

### `UninstallProtectionManager`

File: `android/app/src/main/kotlin/com/example/focus_lock/services/UninstallProtectionManager.kt`

Tracks uninstall protection state and challenge completion.

Key concepts:

- required pushups: 200
- cooldown window after challenge completion
- device admin removal only during allowed window
- protection enabled flag

### `FocusLockDeviceAdminReceiver`

File: `android/app/src/main/kotlin/com/example/focus_lock/services/FocusLockDeviceAdminReceiver.kt`

Receives device admin enable/disable events. When disable is requested, it can return warning text instructing the user to complete the uninstall challenge first.

### `BootReceiver`

File: `android/app/src/main/kotlin/com/example/focus_lock/BootReceiver.kt`

Restarts app blocking after device reboot.

### `SecretCodeReceiver`

File: `android/app/src/main/kotlin/com/example/focus_lock/SecretCodeReceiver.kt`

Handles dialer secret code `*#*#1717#*#*` to restore access by showing the hidden app icon / launching the app path.

## Native Overlay UI

Files:

- `android/app/src/main/kotlin/com/example/focus_lock/ui/LockScreenOverlay.kt`
- `android/app/src/main/kotlin/com/example/focus_lock/ui/DisciplineWarningOverlay.kt`
- `android/app/src/main/kotlin/com/example/focus_lock/ui/UninstallChallengeOverlay.kt`

### `LockScreenOverlay`

Full-screen overlay shown when a blocked app opens. It presents lock messaging and routes challenge actions back into the app.

### `DisciplineWarningOverlay`

Short-lived warning overlay for private browser detection.

### `UninstallChallengeOverlay`

Full-screen native overlay for the uninstall protection challenge. It uses the proximity sensor to count pushups and marks uninstall as allowed when completed.

## Native Storage

### Room Database

Files:

- `android/app/src/main/kotlin/com/example/focus_lock/storage/database/AppDatabase.kt`
- `android/app/src/main/kotlin/com/example/focus_lock/storage/database/AppOpenLog.kt`
- `android/app/src/main/kotlin/com/example/focus_lock/storage/database/AppOpenLogDao.kt`

Room stores app open logs in `focuslock_db`.

DAO operations:

- insert log
- get logs for date
- get open count for date/package
- get logs for date/package
- delete older logs

### SharedPreferences

Flutter and Kotlin use several preference stores:

- Flutter shared preferences for lock timing, emergency request time, and step challenge state.
- `FlutterSharedPreferences` accessed by Kotlin for cross-layer Reddit usage and temp unlock keys.
- App-specific native preference files for Instagram/Reddit/Twitter blocker modules.
- Native uninstall protection preferences.

Be careful when changing keys. Flutter `shared_preferences` prefixes keys with `flutter.` on Android when accessed from native code.

## Android Manifest

File: `android/app/src/main/AndroidManifest.xml`

Declared permissions:

- `SYSTEM_ALERT_WINDOW`
- `PACKAGE_USAGE_STATS`
- `ACTIVITY_RECOGNITION`
- `POST_NOTIFICATIONS`
- `BODY_SENSORS`
- `RECEIVE_BOOT_COMPLETED`
- `INTERNET`
- `CAMERA`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_SPECIAL_USE`
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`

Declared Android components:

- `MainActivity`
- `AccessibilityMonitor`
- `LockScreenOverlay`
- `AppBlockingService`
- `DisciplineWarningOverlay`
- `BootReceiver`
- `FocusLockDeviceAdminReceiver`
- `SecretCodeReceiver`
- `UninstallChallengeOverlay`

Package queries are declared for Instagram, Reddit, Twitter/X, and Chrome.

## Core Runtime Flows

### First Setup

1. User opens the app.
2. `SplashScreen` decides whether to route to permissions, setup, or home.
3. `PermissionsScreen` guides the user through required Android settings.
4. `SetupScreen` stores the password and initializes the 30-day lock.
5. `AppBlockService.initializeLock()` stores lock timing and calls native `startBlocking`.
6. `MainActivity.startBlocking` persists native lock timing, initializes blocker singletons, and starts `AppBlockingService`.

### Blocking a Target App

1. User opens Instagram, Reddit, or Twitter/X.
2. `AccessibilityMonitor` receives a window event.
3. It delegates to the matching blocker singleton.
4. The blocker checks lock and temp unlock state.
5. If locked, it increments attempt count, shows `LockScreenOverlay`, and schedules BACK actions to leave the app.
6. `AccessibilityMonitor` logs the open attempt into Room.

### Reddit Camera Pushup Unlock

1. User opens `/pushup_challenge`.
2. Flutter asks camera permission.
3. `CameraPushupDetector` starts camera frame streaming.
4. ML Kit pose detection counts valid pushups.
5. At 100 reps, Flutter calls `grantRedditCameraPushupReward`.
6. Kotlin grants Reddit temp unlock through `RedditBlocker` / `AccessibilityMonitor`.
7. Reddit is allowed for 10 minutes.

### Emergency Unlock

1. User requests emergency unlock from Flutter.
2. `TimerService` records request time.
3. One-hour countdown starts.
4. `StepChallengeService` starts pedometer tracking.
5. After one hour and 10,000 steps, `LockStateProvider.getPasswordAfterChallenge()` can reveal the stored password.
6. `unlockApp()` clears the lock when both requirements are satisfied.

### Browser Private Mode Blocking

1. User opens a supported browser.
2. `AccessibilityMonitor` scans private browsing surfaces and typing events.
3. `BrowserIncognitoBlocker` checks package-specific keywords and cached state.
4. On detection, `DisciplineWarningOverlay` is shown briefly.
5. Normal tabs are intended to remain unaffected.

### Uninstall Protection

1. User enables protection from Flutter.
2. Native code hides the launcher icon and requests device admin.
3. `AccessibilityMonitor` watches Settings and package installer screens for FocusLock uninstall/disable attempts.
4. On a protected uninstall attempt, it backs out of Settings and launches `UninstallChallengeOverlay`.
5. User completes 200 pushups.
6. `UninstallProtectionManager` opens a cooldown window where uninstall/device-admin removal is allowed.

## CI/CD

File: `.github/workflows/build-apk.yml`

Workflow:

- Runs on pushes to `main` and manual dispatch.
- Uses Ubuntu runner.
- Checks out code.
- Sets Java 17.
- Sets Flutter `3.24.0` stable.
- Runs `flutter pub get`.
- Builds debug APK.
- Builds release APK.
- Uploads both APKs as artifacts.
- Creates a GitHub Release on `main`.

Current action majors are Node 24-compatible:

- `actions/checkout@v6`
- `actions/setup-java@v5`
- `actions/upload-artifact@v7`
- `softprops/action-gh-release@v3`

## Build Configuration

Flutter:

- SDK range: `>=3.0.0 <4.0.0`
- Main dependencies: `provider`, `shared_preferences`, `flutter_secure_storage`, `permission_handler`, `pedometer_2`, `camera`, `google_mlkit_pose_detection`, `intl`, `http`

Android:

- Gradle plugin: `8.3.0`
- Kotlin: `1.9.22`
- Compile SDK: `35`
- Target SDK: `34`
- Min SDK: `29`
- Java/Kotlin target: `1.8`
- Room: `2.6.1`

## Development Notes

- This repo does not include a Gradle wrapper script, so local Android builds require system Gradle or Flutter tooling.
- `flutter analyze` and builds require Flutter to be installed and available on PATH.
- Most enforcement behavior cannot be fully tested in an emulator/unit-test-only loop because it depends on Accessibility Service, overlays, device admin, usage access, sensors, and Android settings screens.
- Be cautious when changing package names, channel names, SharedPreferences keys, or manifest component names. Several Dart and Kotlin modules depend on exact strings.
- The app is Android-specific. iOS support is not implemented.

## High-Risk Areas

- Accessibility tree parsing can break when browser or Android Settings UI text changes.
- Foreground service restrictions vary by Android version and OEM.
- Overlay permission and device admin flows are user-mediated and can fail silently if permissions are denied.
- Sensor-based pushup detection depends on device hardware and placement.
- Flutter and native lock state can drift if shared keys are renamed or cleared inconsistently.
- Hidden launcher icon recovery depends on `SecretCodeReceiver` support on the device/dialer.

## Where To Start For Changes

- Add or change a blocked app: update `AccessibilityMonitor`, add/modify a native blocker singleton, add Flutter service/UI status if needed, update manifest package queries.
- Change emergency unlock rules: update `TimerService`, `StepChallengeService`, and `LockStateProvider`.
- Change pushup rules: update `CameraPushupDetector` for camera ML Kit flow and/or `PushupDetectorService` / `UninstallChallengeOverlay` for sensor flow.
- Change native channel behavior: update both the Dart service wrapper and `MainActivity`.
- Change permissions: update `AndroidManifest.xml`, `PermissionService`, and `PermissionsScreen`.
- Change CI Flutter/Java versions: update `.github/workflows/build-apk.yml` and verify Android Gradle compatibility.
