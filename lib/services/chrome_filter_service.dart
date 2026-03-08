import 'package:flutter/services.dart';

/// Service for Chrome incognito mode blocking status (isolated module).
class ChromeFilterService {
  static const _channel = MethodChannel('com.example.focus_lock/app_block');

  /// Get the current Chrome incognito blocker status.
  ///
  /// Returns `{ "isActive": true, "totalBlocks": 5 }`
  Future<Map<String, dynamic>> getFilterStatus() async {
    try {
      final result = await _channel.invokeMethod('getChromeFilterStatus');
      if (result == null) {
        return {'isActive': false, 'totalBlocks': 0};
      }
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      print('Error getting Chrome filter status: $e');
      return {
        'isActive': false,
        'totalBlocks': 0,
      };
    }
  }
}
