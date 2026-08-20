import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'secure_storage_service.dart';

/// Handles 4-digit staff PIN setup and verification for loyalty
/// transaction accountability (Module 3). The PIN itself is never
/// persisted — only a salted SHA-256 hash, stored via
/// flutter_secure_storage (platform keychain/keystore).
class PinService {
  final SecureStorageService _secureStorage;

  PinService({SecureStorageService? secureStorage})
      : _secureStorage = secureStorage ?? SecureStorageService();

  /// Per-install salt. In production this should be generated once
  /// and persisted securely rather than derived from the staff id,
  /// but is kept simple here since hashing strategy is backend-agreed.
  String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  Future<void> setPin({required String staffId, required String pin}) async {
    assert(pin.length == 4, 'PIN must be exactly 4 digits');
    final hash = _hash(pin, staffId);
    await _secureStorage.savePinHash(hash);
  }

  Future<bool> hasPinConfigured() async {
    final hash = await _secureStorage.getPinHash();
    return hash != null && hash.isNotEmpty;
  }

  Future<bool> verifyPin({required String staffId, required String pin}) async {
    final storedHash = await _secureStorage.getPinHash();
    if (storedHash == null) return false;
    return storedHash == _hash(pin, staffId);
  }

  Future<void> clearPin() => _secureStorage.clearPinHash();
}
