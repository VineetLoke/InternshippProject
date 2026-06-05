# PushLock Plan — ML Camera Pushup Detection & Reward System

## Research Summary

### Existing Apps (Market Analysis)

| App | Platform | Detection | Ratio | Pricing |
|-----|----------|-----------|-------|---------|
| **EarnScroll** | Android | AI camera (on-device) | 5 pushups = 15min | Free |
| **PushUp Time** | Android | AI camera + form validation | Customizable | Free |
| **Blockit** | Android | AI camera | 20 pushups = unlock | $12.99/mo |
| **Pushscroll** | Android | AI camera (pose detection) | 1 pushup = 1min | $30/yr |
| **PushLock** | iOS/Android | On-device AI | Configurable | Free |
| **Kinetic** | iOS | AI camera | 1 rep = 1min | $1.99/week |

### Tech Approaches for Pushup Detection

| Method | Accuracy | Complexity | Privacy |
|--------|----------|------------|---------|
| **Proximity Sensor** (current) | Low — can cheat | Trivial | 100% offline |
| **Angle Heuristics (ML Kit)** | ~90% | Medium | On-device |
| **k-NN Classifier** | ~85% | High (needs dataset) | On-device |
| **Custom TensorFlow Model** | ~95% | Very high | On-device |

### Key Libraries

- **`google_mlkit_pose_detection`** — Google's ML Kit for Flutter. 33 landmarks, on-device.
- **`pose_camera_view`** — Flutter widget, emits pushup states (init/middle/completed).
- **`pushupcount`** — Flutter package with ready pushup counter using ML Kit.
- **MediaPipe Pose Landmarker** — Cross-platform, 33 landmarks in 3D, lightweight.

### How Pushup Detection Works (Angle Heuristics)

```
Landmarks used for pushup detection:
- 11: Left Shoulder    12: Right Shoulder
- 13: Left Elbow       14: Right Elbow
- 15: Left Wrist       16: Right Wrist
- 23: Left Hip         24: Right Hip

Elbow angle (shoulder → elbow → wrist):
  - Up position:   ~160° (arms straight)
  - Down position: ~60°  (chest near ground)

FSM for rep counting:
  IDLE → MOVING_DOWN (angle decreasing)
  MOVING_DOWN → BOTTOM (angle < threshold, ~80°)
  BOTTOM → MOVING_UP (angle increasing)
  MOVING_UP → COUNTED (angle > threshold, ~150°)
```

---

## Implementation Plan

### Phase 1: Replace Proximity Sensor with ML Camera Detection

**Goal**: Swap current proximity-sensor pushup detection with on-device ML camera-based detection.

#### Steps:

1. **Add dependencies** to `pubspec.yaml`:
   ```yaml
   google_mlkit_pose_detection: ^0.12.0
   camera: ^0.11.0
   ```

2. **Add camera permission** to `AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.CAMERA" />
   <uses-feature android:name="android.hardware.camera" android:required="true" />
   <uses-feature android:name="android.hardware.camera.autofocus" />
   ```

3. **Create `CameraPushupDetector` service** in `lib/services/camera_pushup_detector.dart`:
   - Initialize camera
   - Run ML Kit pose detection on each frame
   - Calculate elbow angles (shoulder → elbow → wrist)
   - FSM for rep counting (IDLE → DOWN → UP → COUNT)
   - Emit count via stream (same interface as current `PushupService`)

4. **Update `PushupService`** to support both detection modes:
   - Option A: Proximity sensor (fallback for devices without camera permission)
   - Option B: ML Camera (primary, more accurate)

5. **Add camera preview UI** in pushup challenge screen:
   - Show live camera feed
   - Overlay pose skeleton (joint lines)
   - Show rep count + form feedback
   - Mirror front camera

6. **Update `PushupChallengeScreen`**:
   - New FAB/switch: "Camera Mode" vs "Proximity Mode"
   - Camera mode shows live preview with skeleton overlay
   - Proximity mode keeps current behavior

#### Files to modify:
- `pubspec.yaml` — add deps
- `android/app/src/main/AndroidManifest.xml` — camera permission
- `lib/services/pushup_service.dart` — add camera detection path
- `lib/screens/pushup_challenge_screen.dart` — camera UI + skeleton
- `lib/services/camera_pushup_detector.dart` — NEW: ML detection logic

---

### Phase 2: Enhanced Reward System

**Goal**: Make pushup-to-time ratios configurable per-app and add multiple exercise types.

#### Steps:

1. **Per-app reward configuration**:
   - `lib/models/app_block_config.dart` — NEW: per-app settings (pushup count, reward minutes, exercise type)
   - Store in SharedPreferences

2. **Multiple exercise support**:
   - Squats (track hip angle)
   - Planks (track body straightness + timer)
   - Situps (track torso angle)

3. **Time bank system**:
   - Users accumulate earned minutes
   - Minutes deducted while using the app
   - Persist across app restarts

4. **Emergency bypass improvements**:
   - Keep the 1hr wait + 10k steps for master unlock
   - Add option: "Do 200 pushups with camera verification" as alternative

#### Files to create/modify:
- `lib/models/app_block_config.dart` — NEW
- `lib/services/*_block_service.dart` — update with time bank
- `lib/services/camera_pushup_detector.dart` — add squat/plank detection

---

### Phase 3: Gamification & Analytics

**Goal**: Add streaks, progress tracking, and leaderboards.

#### Steps:

1. **Fitness progress tracking**:
   - Daily/weekly/monthly pushup counts
   - Screen time saved
   - Workout streaks (consecutive days)

2. **Level system**:
   - Unlock achievements
   - Reduce required pushups as level increases (or increase reward time)

3. **Stats dashboard**:
   - Add to home screen: "Today: 50 pushups → 10min earned"
   - Weekly comparison chart

4. **Reminders**:
   - Daily notification: "You haven't earned your screen time yet!"
   - Streak saver notification

#### Files to create/modify:
- `lib/providers/fitness_stats_provider.dart` — NEW
- `lib/services/fitness_stats_service.dart` — NEW
- `lib/screens/home_screen.dart` — add stats section
- `lib/screens/stats_screen.dart` — NEW: dedicated stats page

---

### Phase 4: Anti-Cheat & Security

**Goal**: Prevent bypassing the pushup requirement.

#### Steps:

1. **Form validation**:
   - Validate full ROM (range of motion) — elbow must straighten fully
   - Minimum rep duration (each rep ≥ 0.5s)
   - Maximum rep count per session (prevent rapid half-reps)

2. **Liveness detection**:
   - Random variation in expected rep speed
   - Face detection to ensure real person (bonus)

3. **Camera fallback protection**:
   - If camera fails, require more pushups via proximity sensor
   - Log suspicion score

---

## Architecture Overview (After Phase 1)

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App                        │
├──────────────┬──────────────────┬───────────────────┤
│  App Block   │  Pushup System   │  Master Lock      │
│  Services    │                  │  (30-day + pwd)   │
├──────────────┼──────────────────┼───────────────────┤
│ IG Blocker   │  PushupService   │  LockStateProvider │
│ Reddit Blkr  │  ├─ Proximity    │  AppBlockService  │
│ Twitter Blkr │  └─ CameraML     │  PasswordManager  │
│              │  CameraPushup    │  TimerService     │
│              │  Detector        │  StepChallenge    │
│              │  (ML Kit 33pts)  │                   │
└──────────────┴──────────────────┴───────────────────┘
                        │
              ┌─────────▼─────────┐
              │   Native Android   │
              │  (MethodChannel)   │
              ├───────────────────┤
              │ MediaPipe/ML Kit  │
              │ CameraX + Pose    │
              │ Detection          │
              └───────────────────┘
```

## Key Technical Details

### Elbow Angle Calculation (Dart)
```dart
double calculateElbowAngle(
  PoseLandmark shoulder,
  PoseLandmark elbow,
  PoseLandmark wrist,
) {
  final angle = atan2(wrist.y - elbow.y, wrist.x - elbow.x) -
                atan2(shoulder.y - elbow.y, shoulder.x - elbow.x);
  var result = (angle * 180 / pi).abs();
  if (result > 180) result = 360 - result;
  return result;
}
```

### Rep Counting FSM
```dart
enum RepState { idle, goingDown, bottom, goingUp }

class RepCounter {
  RepState _state = RepState.idle;
  int _count = 0;
  static const double downThreshold = 80.0;
  static const double upThreshold = 150.0;

  int update(double elbowAngle) {
    switch (_state) {
      case RepState.idle:
        if (elbowAngle > upThreshold) _state = RepState.goingDown;
      case RepState.goingDown:
        if (elbowAngle < downThreshold) _state = RepState.bottom;
      case RepState.bottom:
        if (elbowAngle > downThreshold) _state = RepState.goingUp;
      case RepState.goingUp:
        if (elbowAngle > upThreshold) {
          _state = RepState.goingDown;
          _count++;
        }
    }
    return _count;
  }
}
```

### ML Kit Stream Processing
```dart
final poseDetector = PoseDetector(options: PoseDetectorOptions(
  mode: PoseDetectionMode.stream,
));

// Inside camera image stream:
final poses = await poseDetector.processImage(inputImage);
if (poses.isNotEmpty) {
  final pose = poses.first;
  final shoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
  final elbow = pose.landmarks[PoseLandmarkType.leftElbow];
  final wrist = pose.landmarks[PoseLandmarkType.leftWrist];
  final angle = calculateElbowAngle(shoulder, elbow, wrist);
  final count = repCounter.update(angle);
  countStream.add(count);
}
```
