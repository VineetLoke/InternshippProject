import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Manages showing and hiding the FocusGuard quote overlay.
///
/// Uses both flutter_overlay_window (system-level window) and a
/// native MethodChannel (full-screen [LockScreenOverlay]) for robustness.
class OverlayService {
  OverlayService._();

  static final OverlayService _instance = OverlayService._();
  static OverlayService get instance => _instance;

  /// The shared MethodChannel used by all native ↔ Flutter communication.
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  bool _isOverlayShown = false;

  /// Checks if the system-level overlay permission is granted.
  Future<bool> hasPermission() async {
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      developer.log('OverlayService: permission check error: $e');
      return false;
    }
  }

  /// Requests overlay permission from the user.
  Future<bool> requestPermission() async {
    try {
      return await FlutterOverlayWindow.requestPermission();
    } catch (e) {
      developer.log('OverlayService: permission request error: $e');
      return false;
    }
  }

  /// Shows the full-screen quote overlay over other apps.
  ///
  /// Passes the real [quote], [author], and [category] to the native
  /// [LockScreenOverlay] so the user sees the actual quote text instead
  /// of a hardcoded message.
  Future<void> showQuoteOverlay({
    required String quote,
    required String author,
    required String category,
    String source = 'chrome_incognito',
  }) async {
    if (_isOverlayShown) {
      developer.log('OverlayService: overlay already shown, skipping');
      return;
    }

    try {
      // Ensure the system-level overlay window triggers via
      // flutter_overlay_window so Android knows we have an active overlay.
      try {
        final hasPerm = await hasPermission();
        if (!hasPerm) {
          developer.log('OverlayService: overlay permission not granted');
          return;
        }
        final shortQuote =
            quote.length > 60 ? '${quote.substring(0, 57)}...' : quote;
        await FlutterOverlayWindow.showOverlay(
          enableDrag: false,
          overlayTitle: source,
          overlayContent: shortQuote,
          flag: OverlayFlag.defaultFlag,
          alignment: OverlayAlignment.center,
          visibility: OverlayVisibility.unknown,
          positionGravity: PositionGravity.none,
        );
      } catch (e) {
        developer.log('OverlayService: flutter_overlay_window warning: $e');
      }

      // Launch the native full-screen overlay service with real quote data.
      await _channel.invokeMethod('showQuoteOverlay', {
        'source': source,
        'quote': quote,
        'author': author,
        'category': category,
      });

      _isOverlayShown = true;
      developer.log('OverlayService: quote overlay shown');
    } catch (e, st) {
      developer.log('OverlayService: error showing overlay: $e', stackTrace: st);
      _isOverlayShown = false;
      rethrow;
    }
  }

  /// Hides the quote overlay.
  Future<void> hideQuoteOverlay() async {
    if (!_isOverlayShown) return;

    try {
      // Close the flutter_overlay_window indicator first.
      try {
        await FlutterOverlayWindow.closeOverlay();
      } catch (e) {
        developer.log('OverlayService: closeOverlay warning: $e');
      }

      // Also close the native full-screen overlay.
      await _channel.invokeMethod('hideQuoteOverlay');

      _isOverlayShown = false;
      developer.log('OverlayService: quote overlay hidden');
    } catch (e, st) {
      developer.log('OverlayService: error hiding overlay: $e', stackTrace: st);
      _isOverlayShown = false;
    }
  }

  /// Is the overlay currently visible?
  bool get isOverlayShown => _isOverlayShown;
}
