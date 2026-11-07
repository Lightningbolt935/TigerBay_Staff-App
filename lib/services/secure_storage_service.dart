import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/app_constants.dart';

/// Thin wrapper around flutter_secure_storage. The staff PIN is never
/// stored or transmitted in plaintext — only its hash (see PinService).
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> savePinHash(String hash) =>
      _storage.write(key: AppConstants.secureKeyPinHash, value: hash);

  Future<String?> getPinHash() =>
      _storage.read(key: AppConstants.secureKeyPinHash);

  Future<void> clearPinHash() =>
      _storage.delete(key: AppConstants.secureKeyPinHash);

  Future<void> saveAuthToken(String token) =>
      _storage.write(key: AppConstants.secureKeyAuthToken, value: token);

  Future<String?> getAuthToken() =>
      _storage.read(key: AppConstants.secureKeyAuthToken);

  Future<void> clearAuthToken() =>
      _storage.delete(key: AppConstants.secureKeyAuthToken);

  // ---------------------------------------------------------------------------
  // Staff member JSON persistence — allows session restore without OTP re-login
  // ---------------------------------------------------------------------------

  /// Persists the full [StaffMember] JSON so subsequent app opens can restore
  /// the session without requiring OTP re-authentication.
  Future<void> saveStaffJson(String json) =>
      _storage.write(key: AppConstants.secureKeyStaffJson, value: json);

  /// Returns the persisted [StaffMember] JSON, or null if none exists.
  Future<String?> getStaffJson() =>
      _storage.read(key: AppConstants.secureKeyStaffJson);

  /// Clears the persisted staff JSON (called on sign-out).
  Future<void> clearStaffJson() =>
      _storage.delete(key: AppConstants.secureKeyStaffJson);

  Future<void> clearAll() => _storage.deleteAll();
}

