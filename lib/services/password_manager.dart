import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class PasswordManager {
  static const String _passwordKey = 'focus_lock_password';
  static const String _encryptionKeyKey = 'encryption_key_part';

  // Explicitly use EncryptedSharedPreferences on Android to avoid
  // BadPaddingException / keystore errors on first install.
  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true, // wipe corrupted keystore instead of crashing
  );

  final _secureStorage = const FlutterSecureStorage(
    aOptions: _androidOptions,
  );

  /// Encrypt and store password securely
  Future<bool> setPassword(String password) async {
    try {
      // Generate encryption key
      final key = encrypt.Key.fromSecureRandom(32);
      final keyString = key.base64;

      // Store key part 1 (locally)
      await _secureStorage.write(
        key: _encryptionKeyKey,
        value: keyString,
      );

      // Encrypt password
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encrypt(password, iv: iv);

      // Store encrypted password with IV
      String encryptedData = '${iv.base64}:${encrypted.base64}';
      await _secureStorage.write(
        key: _passwordKey,
        value: encryptedData,
      );

      return true;
    } catch (e) {
      print('Error setting password: $e');
      return false;
    }
  }

  /// Verify password during unlock attempt
  Future<bool> verifyPassword(String inputPassword) async {
    try {
      final encryptedData = await _secureStorage.read(key: _passwordKey);
      final keyString = await _secureStorage.read(key: _encryptionKeyKey);

      if (encryptedData == null || keyString == null) {
        return false;
      }

      // Parse encrypted data
      final parts = encryptedData.split(':');
      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypted = encrypt.Encrypted.fromBase64(parts[1]);

      // Decrypt
      final key = encrypt.Key.fromBase64(keyString);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final decrypted = encrypter.decrypt(encrypted, iv: iv);

      return decrypted == inputPassword;
    } catch (e) {
      print('Error verifying password: $e');
      return false;
    }
  }

  /// Retrieve password after challenge completion (for emergency unlock)
  Future<String?> getPasswordAfterChallenge() async {
    try {
      final encryptedData = await _secureStorage.read(key: _passwordKey);
      final keyString = await _secureStorage.read(key: _encryptionKeyKey);

      if (encryptedData == null || keyString == null) {
        return null;
      }

      final parts = encryptedData.split(':');
      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypted = encrypt.Encrypted.fromBase64(parts[1]);

      final key = encrypt.Key.fromBase64(keyString);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final decrypted = encrypter.decrypt(encrypted, iv: iv);

      return decrypted;
    } catch (e) {
      print('Error retrieving password: $e');
      return null;
    }
  }

  /// Check if a password has already been saved
  Future<bool> hasPassword() async {
    try {
      final value = await _secureStorage.read(key: _passwordKey);
      return value != null && value.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking password existence: $e');
      return false;
    }
  }

  /// Clear password (for reset)
  Future<void> clearPassword() async {
    try {
      await _secureStorage.delete(key: _passwordKey);
      await _secureStorage.delete(key: _encryptionKeyKey);
    } catch (e) {
      debugPrint('Error clearing password: $e');
    }
  }
}
