import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores and verifies the user's lock password.
///
/// flutter_secure_storage already performs AES-256-GCM encryption via the
/// Android Keystore on every read/write, so we do NOT need a separate
/// `encrypt`/`pointycastle` layer. Removing that layer eliminates the
/// AOT tree-shaking crash (ArgumentError: No block cipher implementation)
/// that only appears in release builds.
class PasswordManager {
  static const String _passwordKey = 'focus_lock_password';

  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    // Wipe corrupted Keystore on first install instead of crashing.
    resetOnError: true,
  );

  final _storage = const FlutterSecureStorage(aOptions: _androidOptions);

  /// Persist the password. Returns true on success.
  Future<bool> setPassword(String password) async {
    try {
      await _storage.write(key: _passwordKey, value: password);
      return true;
    } catch (e) {
      debugPrint('PasswordManager.setPassword error: $e');
      return false;
    }
  }

  /// Returns true if [inputPassword] matches the stored password.
  Future<bool> verifyPassword(String inputPassword) async {
    try {
      final stored = await _storage.read(key: _passwordKey);
      return stored != null && stored == inputPassword;
    } catch (e) {
      debugPrint('PasswordManager.verifyPassword error: $e');
      return false;
    }
  }

  /// Returns the stored password (used after the emergency challenge).
  Future<String?> getPasswordAfterChallenge() async {
    try {
      return await _storage.read(key: _passwordKey);
    } catch (e) {
      debugPrint('PasswordManager.getPasswordAfterChallenge error: $e');
      return null;
    }
  }

  /// Returns true if a password has previously been saved.
  Future<bool> hasPassword() async {
    try {
      final value = await _storage.read(key: _passwordKey);
      return value != null && value.isNotEmpty;
    } catch (e) {
      debugPrint('PasswordManager.hasPassword error: $e');
      return false;
    }
  }

  /// Wipe the stored password (for reset / testing).
  Future<void> clearPassword() async {
    try {
      await _storage.delete(key: _passwordKey);
    } catch (e) {
      debugPrint('PasswordManager.clearPassword error: $e');
    }
  }
}
