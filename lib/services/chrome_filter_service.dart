import 'package:flutter/services.dart';

/// Service for Chrome keyword filtering status and configuration.
class ChromeFilterService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Get the current Chrome filter status.
  ///
  /// Returns `{ "isActive": true, "blockedKeywordCount": 9 }`
  Future<Map<String, dynamic>> getFilterStatus() async {
    try {
      final result = await _channel.invokeMethod('getChromeFilterStatus');
      if (result == null) {
        return {'isActive': false, 'blockedKeywordCount': 0};
      }
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      print('Error getting Chrome filter status: $e');
      return {
        'isActive': false,
        'blockedKeywordCount': 0,
      };
    }
  }

  /// List of blocked keywords (read-only, matches native side).
  static const List<String> blockedKeywords = [
    'porn', 'fucked', 'bang', 'onlyfans', 'fansly',
    'sex', 'nsfw', 'xxx', 'hentai',
  ];
}
