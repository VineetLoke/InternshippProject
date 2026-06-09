import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/quote_model.dart';

/// Loads and serves quotes from the local JSON asset.
///
/// Tracks the last shown quote index in SharedPreferences to prevent
/// showing the same quote twice in a row.
class QuotesLoader {
  QuotesLoader._();

  static final QuotesLoader _instance = QuotesLoader._();
  static QuotesLoader get instance => _instance;

  static const String _assetPath = 'assets/quotes.json';
  static const String _lastIndexKey = 'last_quote_index';

  List<QuoteModel>? _cache;

  /// Pre-load quotes from the asset bundle.
  /// Call once during app startup for best UX.
  Future<void> load() async {
    if (_cache != null) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final jsonList = jsonDecode(raw) as List<dynamic>;
      _cache = jsonList
          .map((item) => QuoteModel.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      developer.log('QuotesLoader: loaded ${_cache!.length} quotes');
    } catch (e, st) {
      developer.log('QuotesLoader: failed to load quotes: $e', stackTrace: st);
      _cache = [];
    }
  }

  /// Returns a random quote, guaranteed to be different from the
  /// previously shown quote.
  Future<QuoteModel> getRandomQuote() async {
    if (_cache == null || _cache!.isEmpty) {
      await load();
    }
    if (_cache == null || _cache!.isEmpty) {
      // Fallback in case the asset failed to load.
      return const QuoteModel(
        text: 'Focus on being productive instead of busy.',
        author: 'Tim Ferriss',
        category: 'productivity',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final lastIndex = prefs.getInt(_lastIndexKey) ?? -1;

    final random = Random();
    int newIndex;
    if (_cache!.length > 1) {
      do {
        newIndex = random.nextInt(_cache!.length);
      } while (newIndex == lastIndex);
    } else {
      newIndex = 0;
    }

    await prefs.setInt(_lastIndexKey, newIndex);

    // Store the selected quote in SharedPreferences so the native
    // overlay service can read it as a fallback when Flutter is not
    // explicitly controlling the overlay.
    try {
      await prefs.setString('overlay_quote_text', _cache![newIndex].text);
      await prefs.setString('overlay_quote_author', _cache![newIndex].author);
      await prefs.setString('overlay_quote_category', _cache![newIndex].category);
    } catch (e) {
      // Best-effort: native side still falls back to hardcoded quote.
    }

    return _cache![newIndex];
  }

  /// Returns a quote from a specific category.
  /// Falls back to any random quote if the category is empty.
  Future<QuoteModel> getQuoteByCategory(String category) async {
    if (_cache == null || _cache!.isEmpty) {
      await load();
    }
    final filtered = _cache!
        .where((q) => q.category.toLowerCase() == category.toLowerCase())
        .toList();
    if (filtered.isEmpty) return getRandomQuote();
    return filtered[Random().nextInt(filtered.length)];
  }

  /// Gets a quote suitable for blocking a specific app.
  /// Currently maps app names to categories for thematic matching.
  Future<QuoteModel> getQuoteForBlockedApp(String appName) async {
    final lower = appName.toLowerCase();
    if (lower.contains('chrome') || lower.contains('incognito')) {
      return getQuoteByCategory('focus');
    }
    return getRandomQuote();
  }

  /// Total number of loaded quotes.
  int get quoteCount => _cache?.length ?? 0;

  /// Is the cache warm?
  bool get isLoaded => _cache != null;
}
