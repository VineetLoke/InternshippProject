import 'package:flutter/material.dart';

/// Centralized user-facing strings for FocusGuard.
/// All widget text should reference these constants.
@immutable
class AppStrings {
  const AppStrings._();

  // ── App ───────────────────────────────────────────────────────────────────
  static const String appName = 'FocusGuard';
  static const String appTagline = 'Stay focused on what matters';
  static const String loading = 'Loading...';
  static const String error = 'Something went wrong';
  static const String cancel = 'Cancel';
  static const String done = 'Done';
  static const String ok = 'OK';

  // ── Onboarding ──────────────────────────────────────────────────────────
  static const String onboardingWelcome = 'Welcome to FocusGuard';
  static const String onboardingDescription =
      'FocusGuard helps you stay productive by blocking distractions '
      'and replacing them with wisdom from the greatest minds in history.';
  static const String onboardingCta = 'Get Started';

  // ── Permissions ─────────────────────────────────────────────────────────
  static const String permTitle = 'Required Permissions';
  static const String permSubtitle =
      'FocusGuard needs a few permissions to protect your focus.';
  static const String permRequired = 'Required';
  static const String permOptional = 'Optional';
  static const String permOverlayTitle = 'Display Over Other Apps';
  static const String permOverlaySubtitle =
      'Lets FocusGuard show a protection screen on top of distracting apps.';
  static const String permAccessibilityTitle = 'Accessibility Service';
  static const String permAccessibilitySubtitle =
      'Detects when distracting apps are opened so they can be blocked.';
  static const String permActivityTitle = 'Physical Activity';
  static const String permActivitySubtitle =
      'Used for the step-based and pushup-based unlock challenges.';
  static const String permNotificationTitle = 'Notifications';
  static const String permNotificationSubtitle =
      'Shows status notifications while the lock is active.';
  static const String permUsageTitle = 'Usage Access';
  static const String permUsageSubtitle =
      'Enables screen time tracking for blocked apps.';
  static const String permContinue = 'Continue to Setup';

  // ── Setup ───────────────────────────────────────────────────────────────
  static const String setupTitle = 'Set Up Your Secure Password';
  static const String setupDescription =
      'This password will be hidden and only revealed after completing an emergency challenge.';
  static const String setupPasswordHint = 'Enter Password';
  static const String setupConfirmPasswordHint = 'Confirm Password';
  static const String setupAgreementTitle = '30-Day Lock Agreement';
  static const String setupAgreementItems =
      '• Instagram, Reddit & Twitter/X will be blocked for 30 days\n'
      '• Lock will automatically expire after 30 days\n'
      '• You can only unlock via emergency challenge:\n'
      '  - Wait 1 hour\n'
      '  - Complete 10,000 steps in one day\n'
      '  - Retrieve your password\n'
      '• App will continue working after device reboot';
  static const String setupAgreeCheckbox = 'I agree to the 30-day lock';
  static const String setupConfirmButton = 'Confirm & Lock Social Media';

  // ── Home ────────────────────────────────────────────────────────────────
  static const String homeTitle = 'FocusGuard';
  static const String statusLocked = 'Apps Locked';
  static const String statusUnlocked = 'Apps Unlocked';
  static const String daysRemaining = 'days remaining';
  static const String refresh = 'Refresh';
  static const String screenTimeTitle = 'Screen Time Today';
  static const String appOpensTitle = 'App Opens Today';
  static const String recentOpensTitle = 'Recent App Opens';
  static const String noOpensLogged = 'No app opens logged today.';
  static const String totalOpensSuffix = 'total';
  static const String lockInfoTitle = 'How It Works';
  static const String lockInfoBody =
      '• Instagram, Reddit & Twitter/X are blocked when launched\n'
      '• Master 30-day lock with password protection\n'
      '• Emergency unlock: 1hr wait + 10,000 steps\n'
      '• Pushup challenges grant temporary app access\n'
      '• Incognito mode is blocked with wisdom quotes\n'
      '• Uninstall protection prevents impulsive removal';

  // ── Quote Overlay ───────────────────────────────────────────────────────
  static const String quoteOverlayTitle = 'Focus, not Distraction';
  static const String quoteOverlaySubtitle =
      'This wisdom is here to remind you what truly matters.';
  static const String quoteCloseChrome = 'Close Chrome to continue';
  static const String quoteCloseApp = 'Close this app to continue';
  static const String quoteRequestAccess = 'Request Access (Do Pushups)';
  static const String quoteMinutesFor = 'minutes for';

  // ── Pushup Challenge ────────────────────────────────────────────────────
  static const String pushupEmergencyUnlock = 'Emergency Unlock';
  static const String pushupInstruction1 =
      'Place phone face-up on the floor';
  static const String pushupInstruction2 = 'Tap "Start" then get into position';
  static const String pushupInstruction3 =
      'Do pushups over the phone — chest near screen';
  static const String pushupInstruction4 =
      'Complete {count} pushups to unlock';
  static const String pushupStart = 'Start Pushup Detection';
  static const String pushupStop = 'Stop';
  static const String pushupCompleteTitle = 'Challenge Complete';
  static const String pushupCompleteBody =
      '{appName} {reward}. Use the time wisely.';
  static const String pushupMilestone25 = 'Quarter way there!';
  static const String pushupMilestone50 = 'Halfway! Keep pushing!';
  static const String pushupMilestone75 = 'Almost there!';
  static const String pushupMinutesLabel = 'minutes of access';

  // ── Device Admin / Uninstall ────────────────────────────────────────────
  static const String uninstallTitle = 'Protection Settings';
  static const String uninstallHideIcon = 'Hide App Icon';
  static const String uninstallHideIconOn =
      'Icon is hidden. Dial *#*#1717#*#* to access.';
  static const String uninstallHideIconOff = 'Icon is visible in app drawer.';
  static const String uninstallProtectionTitle = 'Uninstall Protection';
  static const String uninstallProtectionOn =
      'Device admin active. Uninstall blocked.';
  static const String uninstallProtectionOff =
      'Device admin inactive. App can be uninstalled.';
  static const String uninstallEnableButton = 'ENABLE FULL PROTECTION';
  static const String uninstallCooldownActive = 'COOLDOWN ACTIVE';
  static const String uninstallCooldownBody =
      'Uninstall is allowed during this window';
  static const String uninstallHowItWorks = 'How it works';
  static const String uninstallHowItWorksBody =
      '• Hide Icon: Removes the app from the drawer. '
      'Access via dialer: *#*#1717#*#*\n\n'
      '• Uninstall Protection: Registers as device administrator. '
      'Must be deactivated before uninstall.\n\n'
      '• Challenge: Complete 200 pushups to disable protection.'
      '• Cooldown: After completing the challenge, you have 5 minutes '
      'to uninstall. Protection reactivates after.';

  // ── Notification ──────────────────────────────────────────────────────────
  static const String notifTimerTitle = 'FocusGuard — Temporary Access Active';
  static const String notifTimerBody = '{appName} access expires in {time}';
  static const String notifTimerExpired = 'Access expired. Blocking resumed.';

  // ── Error ────────────────────────────────────────────────────────────────
  static const String errorOverlayPermission =
      'Overlay permission not granted. Blocking may not work.';
  static const String errorAccessibility =
      'Accessibility service is not enabled. Please enable it in Settings.';
  static const String errorGeneralRetry = 'Please try again.';
  static const String errorSensorUnavailable =
      'Detection not available. Check camera permissions or use proximity mode.';
}
