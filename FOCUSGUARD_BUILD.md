# FocusGuard — Product Build Instructions for Claude Code

## Role

You are the **Product Manager and Lead Engineer** for FocusGuard, a productivity-focused
Android application. You are building this as an enterprise-grade, modular product.
Your job is to first deeply understand the existing codebase (if any), create a structured
engineering plan, and then build the app feature by feature — never rushing, never skipping
architecture decisions.

Think like a PM: every feature must have a clear purpose, acceptance criteria, and edge
case handling before a single line of code is written.

---

## Phase 0 — Codebase Analysis (Do this FIRST, before anything else)

Before writing any code, do a full codebase audit.

```bash
# List entire project structure
find . -type f | sort

# Read the pubspec.yaml to understand dependencies
cat pubspec.yaml

# Read the AndroidManifest.xml
cat android/app/src/main/AndroidManifest.xml

# List all Dart files
find lib/ -name "*.dart" | sort

# Read every Dart file and understand what it does
# For each file, note: purpose, state management used, services declared
```

After reading everything, write a **Codebase Audit Report** as a comment block:

```
/*
CODEBASE AUDIT REPORT
=====================
Total files: X
State management: (Provider / Riverpod / Bloc / setState)
Services found: (list)
Features already implemented: (list)
Features missing: (list)
Code quality issues: (list)
Recommended refactors before building: (list)
*/
```

If there is no existing codebase, skip to Phase 1 and start fresh.

---

## Phase 1 — Architecture Plan (Do this SECOND, before writing code)

FocusGuard must be built as a **modular, maintainable Android app** using Flutter.
Plan the folder structure before creating any files:

```
lib/
├── core/                        # Shared utilities, constants, theme
│   ├── constants/
│   ├── theme/
│   └── utils/
├── features/
│   ├── social_blocker/          # Feature 1: Social media blocking
│   ├── pushup_unlock/           # Feature 2: 100 pushup unlock
│   ├── incognito_blocker/       # Feature 3 (TOP PRIORITY): Incognito blocking
│   └── app_protection/          # Feature 4: Uninstall prevention
├── services/
│   ├── accessibility_service/   # Core Android AccessibilityService
│   ├── overlay_service/         # System overlay (quote screens)
│   └── sensor_service/          # Accelerometer for pushup detection
├── data/
│   ├── quotes/                  # Quote bank (local JSON)
│   └── preferences/             # SharedPreferences wrapper
└── main.dart
```

Each feature folder must contain:
- `screens/` — UI screens
- `widgets/` — reusable widgets for that feature
- `controller/` — business logic
- `model/` — data models

---

## Product Features

---

### Feature 3 — Incognito Blocker (TOP PRIORITY — Build This First)

**What it does:**
Detects when the user opens Chrome in Incognito mode and immediately overlays
a full-screen quote screen, making Incognito unusable without closing the overlay.
It does NOT block regular Chrome browsing.

**Acceptance Criteria:**
- [ ] Regular Chrome browsing works completely unaffected
- [ ] Opening a new Incognito tab triggers the overlay within 1 second
- [ ] The overlay shows a motivational quote (random, from local quote bank)
- [ ] The overlay cannot be dismissed by pressing Back or Home — it stays until
      the user closes the Incognito tab
- [ ] Works on Android 10, 11, 12, 13, 14

**Technical Implementation:**

1. `AccessibilityService` monitors window state changes:
```dart
// Detect Chrome Incognito by window title or package + activity
// Chrome Incognito window title contains "Incognito" in accessibility node
// Package: com.android.chrome
// Look for: AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
//           where packageName == "com.android.chrome"
//           and the window title or node text contains "Incognito"
```

2. When Incognito is detected, launch `OverlayService` using
   `SYSTEM_ALERT_WINDOW` permission to draw over other apps

3. The overlay is a full-screen Flutter widget showing:
   - App logo / name
   - A random quote from the quote bank
   - A calm, dark-themed UI (not aggressive)
   - No dismiss button

4. `AccessibilityService` continues monitoring — when Chrome Incognito tab count
   drops to 0 or user switches away from Incognito, dismiss the overlay

**Permissions required in AndroidManifest.xml:**
```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.BIND_ACCESSIBILITY_SERVICE"/>

<service
    android:name=".services.FocusGuardAccessibilityService"
    android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
    android:exported="true">
    <intent-filter>
        <action android:name="android.accessibilityservice.AccessibilityService"/>
    </intent-filter>
    <meta-data
        android:name="android.accessibilityservice"
        android:resource="@xml/accessibility_service_config"/>
</service>
```

**accessibility_service_config.xml:**
```xml
<accessibility-service
    android:accessibilityEventTypes="typeWindowStateChanged|typeWindowContentChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagReportViewIds|flagRetrieveInteractiveWindows"
    android:canRetrieveWindowContent="true"
    android:packageNames="com.android.chrome"
    android:notificationTimeout="100"/>
```

**Edge Cases to handle:**
- User has Chrome Beta or Chrome Dev installed (different package names —
  check `com.chrome.beta`, `com.chrome.dev`, `com.chrome.canary` too)
- User dismisses overlay via recent apps — re-detect and re-show
- Overlay crashes — use a foreground service to keep it alive
- Android 13+ requires POST_NOTIFICATIONS permission for foreground service

---

### Feature 1 — Social Media Blocker

**What it does:**
Blocks Reddit, X (Twitter), and Instagram. When user opens any of these apps,
a full-screen overlay appears with a motivational quote instead of the app content.

**Target apps:**
| App | Package Name |
|---|---|
| Instagram | `com.instagram.android` |
| X (Twitter) | `com.twitter.android` |
| Reddit | `com.reddit.frontpage` |

**Acceptance Criteria:**
- [ ] Opening any of the 3 apps shows the quote overlay immediately
- [ ] Quote is random from local quote bank (different quotes for each app if possible)
- [ ] Overlay shows which app was blocked and why
- [ ] User can see a "Request Access" button that leads to the Pushup Unlock flow
- [ ] Blocking works even if user tries to open app from widget or notification

**Technical Implementation:**
- Reuse the same `AccessibilityService` from Feature 3
- Add the 3 social media package names to `accessibility_service_config.xml`
  `packageNames` list (comma-separated alongside Chrome)
- When a blocked app's window comes to foreground → show overlay
- The overlay for social media has a "Do 100 Pushups for 10 min access" button

**UI — Quote Overlay Screen:**
- Dark background (`#0D0D0D`)
- App icon of the blocked app shown greyed out at top
- Large quote text in white, serif font
- Quote author in smaller grey text
- "Request 10 min access" button at bottom (leads to Feature 2)
- Subtle animation — quote fades in

---

### Feature 2 — Pushup Unlock (10 Minutes Access)

**What it does:**
If the user genuinely wants to use a blocked social media app, they can earn
10 minutes of access by doing 100 pushups. The app uses the phone's accelerometer
to count pushups automatically.

**Acceptance Criteria:**
- [ ] Pushup counter uses accelerometer — no manual counting
- [ ] Counter is resistant to cheating (shaking the phone doesn't count)
- [ ] Clear UI showing current count out of 100
- [ ] On reaching 100, grants exactly 10 minutes of access to that specific app
- [ ] Timer is shown as a persistent notification during the 10-minute window
- [ ] When timer expires, blocking resumes automatically
- [ ] If user force-quits FocusGuard during the 10 minutes, blocking resumes on relaunch

**Technical Implementation:**

1. Pushup detection via accelerometer:
```dart
// A pushup = one full down + up cycle on the Z axis
// Threshold: acceleration crosses ~12 m/s² going down, then returns
// Minimum time between reps: 500ms (prevents false positives)
// Use: sensors_plus package
```

2. Unlock flow:
   - User taps "Do 100 Pushups" on the overlay
   - FocusGuard opens full-screen pushup counter
   - Live count shown: "47 / 100"
   - Encouraging messages at milestones (25, 50, 75)
   - On 100: confetti animation, then 10-minute timer starts

3. Timer management:
   - Store unlock expiry timestamp in SharedPreferences:
     `unlock_expiry_{packageName} = System.currentTimeMillis() + 600000`
   - `AccessibilityService` checks this before blocking
   - Show countdown in a persistent foreground notification

**Edge Cases:**
- Phone placed flat on table and tapped — filtered out (must detect vertical motion)
- User leaves pushup screen midway — progress is lost (no save, by design)
- Two apps unlocked at same time — each has independent timer

---

### Feature 4 — Uninstall Prevention

**What it does:**
Prevents the user from uninstalling FocusGuard without going through a deliberate
multi-step process. This makes it harder to remove the app impulsively.

**Acceptance Criteria:**
- [ ] User cannot uninstall FocusGuard directly from Settings → Apps
- [ ] Attempting to uninstall shows a warning screen first
- [ ] Uninstall requires a 24-hour cooldown confirmation (user must confirm twice,
      24 hours apart — prevents impulsive removal)
- [ ] Device admin status is clearly explained to user on first launch

**Technical Implementation:**

1. Register FocusGuard as a **Device Administrator**:
```xml
<!-- In AndroidManifest.xml -->
<receiver
    android:name=".services.FocusGuardDeviceAdmin"
    android:permission="android.permission.BIND_DEVICE_ADMIN"
    android:exported="true">
    <meta-data
        android:name="android.app.device_admin"
        android:resource="@xml/device_admin_config"/>
    <intent-filter>
        <action android:name="android.app.action.DEVICE_ADMIN_ENABLED"/>
    </intent-filter>
</receiver>
```

2. `device_admin_config.xml`:
```xml
<device-admin>
    <uses-policies>
        <limit-password/>
    </uses-policies>
</device-admin>
```

3. When Device Admin is active, Android requires the user to first deactivate
   Device Admin before uninstalling — FocusGuard intercepts this flow

4. On deactivation attempt, show a full-screen warning:
   - "Are you sure? Your focus streak will be lost."
   - "Come back in 24 hours to confirm removal."
   - Store timestamp of first uninstall attempt
   - Only allow actual deactivation if 24 hours have passed since first attempt

**Important Note for developer:**
Clearly explain Device Admin to the user on first launch. This is a powerful
permission — be transparent about what it does and does not do.

---

## Quote Bank

Store quotes locally in `assets/quotes.json`. Minimum 50 quotes.
Categories: focus, discipline, productivity, stoicism.

Example format:
```json
[
  {
    "text": "You have power over your mind, not outside events. Realize this, and you will find strength.",
    "author": "Marcus Aurelius",
    "category": "stoicism"
  },
  {
    "text": "Discipline is choosing between what you want now and what you want most.",
    "author": "Abraham Lincoln",
    "category": "discipline"
  }
]
```

Select quotes randomly but avoid repeating the same quote twice in a row.
Track last shown quote ID in SharedPreferences.

---

## Build Order

Build in this exact order. Do not skip ahead.

```
1. [ ] Project setup — folder structure, dependencies, theme
2. [ ] Quote bank — load and display a random quote (test this works first)
3. [ ] AccessibilityService — basic setup, confirm it detects window changes
4. [ ] Overlay service — draw a full-screen overlay over other apps
5. [ ] FEATURE 3: Incognito blocker — wire AccessibilityService → Overlay
6. [ ] FEATURE 1: Social media blocker — extend AccessibilityService + Overlay
7. [ ] FEATURE 2: Pushup unlock — accelerometer counter + timer
8. [ ] FEATURE 4: Uninstall prevention — Device Admin registration
9. [ ] Polish — animations, dark theme, onboarding flow
10.[ ] GitHub Actions — APK build workflow
```

---

## pubspec.yaml Dependencies to Add

```yaml
dependencies:
  flutter:
    sdk: flutter
  sensors_plus: ^4.0.0          # Accelerometer for pushup detection
  shared_preferences: ^2.2.0    # Storing unlock timers, settings
  flutter_overlay_window: ^0.3.0 # System overlay over other apps
  provider: ^6.1.0              # State management
  flutter_local_notifications: ^16.0.0  # 10-min access countdown notification
  lottie: ^3.0.0                # Animations (confetti on pushup completion)

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

---

## Code Quality Rules

- Every service must be in its own file — no god classes
- Every feature must work independently — no tight coupling between features
- Use `const` constructors everywhere possible
- No hardcoded strings — use a `AppStrings` constants class
- No hardcoded colors — use the theme system
- Write a brief doc comment (`///`) on every public method
- If a function is longer than 40 lines, break it into smaller functions
- Handle all async errors with try/catch — never let the app crash silently

---

## Definition of Done (for each feature)

A feature is only "done" when:
- [ ] It works on a real Android device (not just emulator)
- [ ] Edge cases listed above are handled
- [ ] No red lint warnings in the file
- [ ] A brief test scenario is written as a comment at the top of the main file
- [ ] The PM (developer) has manually tested it for 5 minutes

---

## First Message to Send Claude Code

When you start a Claude Code session, paste this exact message:

> "Read FOCUSGUARD_BUILD.md fully. Then do Phase 0 — audit the entire codebase
> and give me a report. Do not write any code yet. After the audit, propose the
> Phase 1 architecture and wait for my approval before building anything."
