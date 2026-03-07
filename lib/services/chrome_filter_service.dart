import 'package:flutter/services.dart';

/// Service for Chrome incognito keyword filtering status (isolated module).
class ChromeFilterService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Get the current Chrome incognito filter status.
  ///
  /// Returns `{ "isActive": true, "blockedKeywordCount": 18, "totalBlocks": 5 }`
  Future<Map<String, dynamic>> getFilterStatus() async {
    try {
      final result = await _channel.invokeMethod('getChromeFilterStatus');
      if (result == null) {
        return {'isActive': false, 'blockedKeywordCount': 0, 'totalBlocks': 0};
      }
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      print('Error getting Chrome filter status: $e');
      return {
        'isActive': false,
        'blockedKeywordCount': 0,
        'totalBlocks': 0,
      };
    }
  }

  /// List of blocked keywords (read-only, matches native ChromeIncognitoBlocker).
  static const List<String> blockedKeywords = [
    'porn', 'pornhub', 'xxx', 'xvideos', 'xnxx',
    'redtube', 'youporn', 'hentai', 'nsfw', 'onlyfans',
    'fansly', 'sexvideo', 'pornvideo', 'rule34', 'bdsm',
    'escort', 'camgirl', 'chaturbate','banged',
  ];
}
