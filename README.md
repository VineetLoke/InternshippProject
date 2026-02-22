# FocusLock – Android App to Block Instagram with Delayed Unlock & Physical Challenge

FocusLock is a Flutter-based Android application that blocks Instagram for personal productivity. The app works without root access and uses Android accessibility and usage permissions to detect and block Instagram.

## Features

✅ **App Blocking** - Detects and blocks Instagram transparently
✅ **30-Day Lock** - Default lock period with automatic expiration  
✅ **Secure Password** - AES-encrypted password storage  
✅ **Emergency Unlock** - 1-hour delay + 10,000 step challenge  
✅ **Persistence** - Lock survives app restarts and device reboots  
✅ **Beautiful UI** - Modern Flutter material design interface  

## Core Requirements

### 1. App Blocking
- Detects when Instagram (package: `com.instagram.android`) is opened
- Displays full-screen overlay lock screen
- Prevents all interaction with Instagram while locked

### 2. Lock Duration
- Default: 30 days
- Automatically expires after period
- Lock state persists across reboots

### 3. Password System
- User sets password during setup
- Stored encrypted using AES encryption
- Hidden from direct inspection
- Revealed only after emergency challenge completion

### 4. Emergency Unlock
- **Anti-Impulse Delay**: 1-hour waiting period
- **Physical Challenge**: 10,000 steps required in one day
- Both must complete before password is revealed

### 5. Security
- AES encryption for password storage
- Device ID-based key derivation
- Prevent bypass via file inspection or app restart

## Project Structure

```
focus_lock/
├── lib/
│   ├── main.dart                          # Entry point with routing
│   ├── providers/
│   │   └── lock_state_provider.dart      # State management
│   ├── services/
│   │   ├── app_block_service.dart        # Lock management
│   │   ├── password_manager.dart         # Encryption & storage
│   │   ├── step_challenge.dart           # Step counter
│   │   └── timer_service.dart            # 1-hour delay
│   └── screens/
│       ├── splash_screen.dart            # Splash screen
│       ├── setup_screen.dart             # Initial setup
│       ├── home_screen.dart              # Main dashboard
│       ├── lock_screen.dart              # Lock display
│       └── emergency_unlock_screen.dart  # Challenge screen
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml           # Permissions & services
│       ├── kotlin/
│       │   ├── MainActivity.kt           # Entry point
│       │   ├── AppBlockingAccessibilityService.kt
│       │   ├── LockScreenOverlayService.kt
│       │   ├── AppBlockingService.kt
│       │   └── BootReceiver.kt
│       └── res/
│           ├── xml/accessibility_service_config.xml
│           └── values/strings.xml
└── pubspec.yaml                          # Dependencies
```

## Required Dependencies

```yaml
flutter_secure_storage: ^9.0.0      # Secure password storage
device_info_plus: ^10.0.0            # Device-based key generation
permission_handler: ^11.4.3          # Permission requests
pedometer: ^3.1.3                    # Step counter
provider: ^6.0.0                     # State management
shared_preferences: ^2.2.0           # Lock state persistence
encrypt: ^5.0.1                      # AES encryption
```

## Android Permissions Required

```
android.permission.SYSTEM_ALERT_WINDOW
android.permission.PACKAGE_USAGE_STATS
android.permission.ACTIVITY_RECOGNITION
android.permission.FOREGROUND_SERVICE
android.permission.BODY_SENSORS
android.permission.RECEIVE_BOOT_COMPLETED
```

## Setup Instructions

### 1. Prerequisites
- Flutter SDK (3.0+)
- Android SDK (API 21+)
- Android Studio or Command Line Tools

### 2. Installation

```bash
# Clone the repository
git clone <repo-url>
cd focus_lock

# Get dependencies
flutter pub get

# Build and run
flutter run -d <device_id>
```

### 3. Initial Setup
1. Launch the app
2. Set a secure password
3. Agree to the 30-day lock
4. App will start blocking Instagram immediately

### 4. Enable Required Permissions
The app will request:
- **Accessibility Service** - For Instagram detection
- **Package Usage Stats** - To monitor app usage
- **Activity Recognition** - For step counting
- **Body Sensors** - For step counter access
- **Overlay Permission** - For lock screen display

### 5. User Flow

```
Install App
    ↓
Request Permissions
    ↓
Set Password & Agree to Lock (Setup Screen)
    ↓
Instagram Locked (Home Screen)
    ↓
Need to unlock? (Optional)
    ├→ Request Emergency Unlock
    ├→ Wait 1 hour
    ├→ Walk 10,000 steps
    └→ Password Revealed → Unlock
    ↓
After 30 Days: Automatically Unlocked
```

## Security Model

### Password Encryption
1. User enters password
2. AES-256 key generated
3. Password encrypted with IV
4. Key stored in secure storage
5. Both stored together

### Emergency Recovery
- Requires 1-hour delay (prevents impulsive unlock)
- Requires 10,000 steps (physical effort/commitment)
- Only after both complete is password revealed

### Persistence
- SharedPreferences stores lock start time
- Survives app restarts
- Survives device reboots (via BootReceiver)
- Survives app uninstall (data recoverable from secure storage)

## Building for Production

```bash
# Build APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release

# Sign APK
jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 \
  -keystore key.jks app-release-unsigned.apk alias
```

## Troubleshooting

### Issue: Accessibility Service Not Detecting Instagram
**Solution**: Ensure accessibility service is enabled in device settings:
- Settings → Accessibility → FocusLock → Enable

### Issue: Step Counter Not Working
**Solution**: 
- Ensure Google Fit or native step counter is available
- Check Body Sensors permission is granted
- May require device to have hardware step counter

### Issue: Lock Survives Uninstall
**Solution**: 
- Flutter secure storage persists even after uninstall
- Manual delete: `adb shell rm -r /data/data/com.example.focus_lock/`
- Or reinstall and use emergency unlock

## Success Criteria

✔ Instagram cannot be used during lock period  
✔ Lock automatically ends after 30 days  
✔ Password cannot be easily accessed  
✔ Emergency unlock requires physical effort and 1-hour delay  
✔ App continues working after reboot  
✔ Overlay cannot be dismissed with back button  
✔ Lock state persists across app restarts  

## Notes

- The overlay display is simplified in this implementation. For production, consider:
  - More sophisticated overlay animations
  - Gesture detection to prevent swipe-away
  - System-level integration for better blocking
  
- Step counter reliability varies by device. Test on target device.

- Password encryption uses standard AES-256 from the `encrypt` package.

## License

MIT License - See LICENSE file for details

## Support

For issues or feature requests, please create an issue in the repository.
