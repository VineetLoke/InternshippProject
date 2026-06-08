import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'quotes_loader.dart';
import '../../../services/overlay/overlay_service.dart';
import '../model/quote_model.dart';

/// Coordinates incognito mode detection with the quote overlay.
///
/// Bridges the native [AccessibilityMonitor] with the Flutter quote
/// display by polling the incognito state and managing the overlay lifecycle.
class IncognitoController {
  IncognitoController._();

  static final IncognitoController _instance = IncognitoController._();
  static IncognitoController get instance => _instance;

  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  QuoteModel? _currentQuote;
  Timer? _pollTimer;
  bool _isOverlayShown = false;

  /// Currently displayed quote (or null if none shown).
  QuoteModel? get currentQuote => _currentQuote;

  /// Is the incognito overlay currently visible?
  bool get isOverlayShown => _isOverlayShown;

  /// Starts polling for incognito state changes.
  /// Call this when the app is active (e.g. from a lifecycle observer).
  void startMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _checkAndToggleOverlay(),
    );
  }

  /// Stops polling. Call on app pause/dispose.
  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Manually triggers the quote overlay for incognito blocking.
  /// Uses [OverlayService] so quote data is passed through to the
  /// native overlay with proper state tracking.
  Future<void> triggerIncognitoBlock() async {
    if (_isOverlayShown) return;
    try {
      final quote = await QuotesLoader.instance.getQuoteForBlockedApp('chrome');
      _currentQuote = quote;
      _isOverlayShown = true;

      await OverlayService.instance.showQuoteOverlay(
        quote: quote.text,
        author: quote.author,
        category: quote.category,
        source: 'chrome_incognito',
      );

      developer.log('IncognitoController: overlay shown for ${quote.author}');
    } catch (e, st) {
      developer.log('IncognitoController: overlay error: $e', stackTrace: st);
      _isOverlayShown = false;
    }
  }

  /// Hides the incognito quote overlay.
  Future<void> dismissIncognitoBlock() async {
    if (!_isOverlayShown) return;
    try {
      await OverlayService.instance.hideQuoteOverlay();
      _isOverlayShown = false;
      _currentQuote = null;
      developer.log('IncognitoController: overlay dismissed');
    } catch (e, st) {
      developer.log('IncognitoController: dismiss error: $e', stackTrace: st);
    }
  }

  /// Checks the native incognito state and toggles the overlay
  /// based on whether the user is currently in an Chrome incognito tab.
  Future<void> _checkAndToggleOverlay() async {
    try {
      final isIncognito = await _channel.invokeMethod<bool>('isChromeIncognito')
          .timeout(const Duration(seconds: 1), onTimeout: () => false);

      if (isIncognito == true && !_isOverlayShown) {
        await triggerIncognitoBlock();
      } else if ((isIncognito == false || isIncognito == null) && _isOverlayShown) {
        await dismissIncognitoBlock();
      }
    } catch (e) {
      // Native method may not exist yet; ignore on first run.
      developer.log('IncognitoController: poll check skipped: $e');
    }
  }
}