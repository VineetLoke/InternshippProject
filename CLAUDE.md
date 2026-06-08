# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**FocusGuard** is a **Flutter Android-only** productivity app. It blocks distracting apps (Instagram, Reddit, Twitter/X) and Chrome incognito mode behind a system-level overlay that shows motivational quotes. Temporary access can be earned by doing pushups detected via the phone's accelerometer or camera (ML Kit).

## Common Commands

### Build

```bash
# Install dependencies
flutter pub get

# Build APK (debug)
flutter build apk --debug

# Build APK (release)
flutter build apk --release --target-platform=android-arm64

# Build App Bundle (Play Store)
flutter build appbundle --release --target-platform=android-arm64
```

### Linting

```bash
# Run static analysis
flutter analyze --fatal-infos

# Run lints (from flutter_lints)
flutter analyze
```

### Testing

```bash
# Run all tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Run tests matching a pattern
flutter test --name "test_name"
```

### Running the app

```bash
# List connected devices
flutter devices

# Run on a specific device
flutter run -d <device_id>

# Run in release mode
flutter run --release

# Hot reload during development (press 'r' in the terminal)
flutter run --hot
```

## High-Level Architecture

```
Flutter (Dart) side                          Native (Kotlin) side
-------------------------------------------    --------------------------------
lib/                                            android/app/src/main/kotlin/
├── core/                                       ├── services/
│   ├── constants/app_colors.dart               │   ├── AccessibilityMonitor.kt      ← Core: monitors ALL foreground apps
│   ├── constants/app_strings.dart              │   ├── AppBlockingService.kt
│   └── theme/app_theme.dart                   │   ├── PushupDetectorService.kt
├── features/                                   │   ├── UninstallProtectionManager.kt
│   ├── incognito_blocker/                     │   ├── ChromeIncognitoBlocker.kt
│   │   ├── controller/quotes_loader.dart      │   └── FocusLockDeviceAdminReceiver.kt
│   │   ├── model/quote_model.dart             ├── blockers/                       ← Per-app blocking logic
│   │   └── screens/quote_overlay_screen.dart  │   ├── InstagramBlocker.kt         ← Own SharedPreferences
│   └── social_media_blocker/                  │   ├── RedditBlocker.kt            ← Temp unlock timer per app
│       ├── controller/                        │   └── TwitterBlocker.kt
│       ├── model/                             └── ui/
│       └── widgets/                               ├── LockScreenOverlay.kt      ← Full-screen overlay with quotes
├── providers/lock_state_provider.dart              └── UninstallChallengeOverlay.kt
├── screens/                                  └── MainActivity.kt                   ← MethodChannel bridge
├── services/                                       (CHANNEL = "com.example.focus_lock/app_block")
│   ├── notification/notification_service.dart
│   ├── notification/unlock_timer_manager.dart
│   └── overlay/overlay_service.dart
└── main.dart
```

### Key Architecture Concepts

**1. Android AccessibilityService is the heart of the app.**

`AccessibilityMonitor.kt` is an Android `AccessibilityService` that monitors `TYPE_WINDOW_STATE_CHANGED` events. When a foreground app matches one of the blocked packages (`com.instagram.android`, `com.reddit.frontpage`, `com.twitter.android`, `com.android.chrome`), it triggers the overlay.

```
Foreground app change detected
    ↓
AccessibilityMonitor.onAccessibilityEvent()
    ↓
[Instagram|Reddit|Twitter]Blocker.onXxxDetected()
    ↓
Launch LockScreenOverlay (native Kotlin full-screen overlay with quote)
```

**2. Each app has its own isolated blocker module.**

`InstagramBlocker`, `RedditBlocker`, and `TwitterBlocker` are **singleton Kotlin objects** each with **their own SharedPreferences file** (NOT FlutterSharedPreferences). This means the 30-day lock and temp-unlock timers are completely isolated per app and survive Flutter state resets.

Key constants per blocker:
- `TEMP_UNLOCK_DURATION_MS = 10L * 60 * 1000` (10 minutes)
- `LOCK_DURATION_DAYS = 17` (17-day hard lock)
- Stores: `KEY_LOCK_START`, `KEY_TEMP_UNLOCK_START`, `KEY_ATTEMPT_COUNT`

**3. MethodChannel is the Dart ↔ Kotlin bridge.**

Channel name: `com.example.focus_lock/app_block`

Key method calls FROM Dart TO Kotlin:
- `getInstagramBlockStatus`, `getRedditBlockStatus`, `getTwitterBlockStatus` → status maps
- `completeInstagramEmergencyChallenge`, etc. → grants 10-min temp unlock
- `showQuoteOverlay` / `hideQuoteOverlay` → triggers native overlay
- `startPushupDetection` / `getPushupCount` / `redeemPushups` → proximity pushup detection

**4. Quote delivery uses a two-path system.**

- **Path 1 (explicit,preferred):** `OverlayService.showQuoteOverlay(quote, author, category, source)` → `MainActivity.kt` passes as intent extras → `LockScreenOverlay.kt` uses the real quote text.
- **Path 2 (fallback):** `QuotesLoader.getRandomQuote()` stores the last selected quote in SharedPreferences as `overlay_quote_text`, `_author`, `_category`. `LockScreenOverlay.kt` reads these as a fallback when no explicit quote is passed.

**5. Unlock notifications are managed by polling.**

`UnlockTimerManager` (Dart) runs a `Timer.periodic(Duration(seconds: 1))` that:
1. Calls MethodChannel to get all three blockers' temp unlock status maps
2. Finds the active unlock with the most remaining time
3. Calls `NotificationService.showCountdownNotification()` to update the persistent Android notification

**6. Pushup detection has two modes.**

- **Proximity mode (default):** Native Kotlin `PushupDetectorService` uses proximity sensor. Triggered via `MethodChannel.invokeMethod('startPushupDetection')`.
- **Camera mode:** ML Kit pose detection in `camera_pushup_detector.dart`. Uses front camera and arm angle calculation. Only available if camera permissions are granted.

**7. Uninstall protection via Device Admin.**

- `FocusLockDeviceAdminReceiver` registers as a device admin
- Uninstall attempt → must complete 100 pushups → 24-hour cooldown window opens
- `UninstallProtectionManager.kt` tracks the cooldown (`COOLDOWN_WINDOW_MS = 24 * 60 * 60 * 1000`)

## Important Files for Debugging

- **Access blockers not working**: Check `AccessibilityMonitor.kt` logs (`TAG = "AppBlockingA11y"`) and ensure the Accessibility Service is enabled in device settings.
- **Overlay not showing**: Check `Settings.canDrawOverlays(context)` and ensure overlay permission is granted.
- **Pushups not detecting**: Check if proximity sensor available (`sensors_plus`). Camera mode requires `CAMERA` permission + ML Kit Pose Detection.
- **Quotes loading**: `assets/quotes.json` must be present and referenced in `pubspec.yaml`.
- **Temp unlock expiry not detected**: Each blocker's `getTempUnlockRemainingSeconds()` reads from its own SharedPreferences. Service restart calls `restoreTempUnlockTimer()`.

## pubspec.yaml Notes

- **Flutter version constraint**: `sdk: '>=3.0.0 <4.0.0'`
- **Platform**: Android only (uses Android-native APIs: AccessibilityService, DevicePolicyManager, AlarmManager, UsageStatsManager)
- **Key packages**: `sensors_plus`, `shared_preferences`, `provider`, `flutter_overlay_window`, `flutter_local_notifications`, `lottie`, `google_mlkit_pose_detection`, `camera`

## GitHub Actions

`.github/workflows/build.yml`: Runs on push to `main`/`develop` and PRs to `main`. Steps: `flutter pub get` → `flutter analyze --fatal-infos` → `flutter test` → `flutter build apk --release` → `flutter build appbundle --release`. Artifacts uploaded for 7 days.
