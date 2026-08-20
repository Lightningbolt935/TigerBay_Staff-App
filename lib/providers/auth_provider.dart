import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/staff_member.dart';
import '../services/supabase_service.dart';
import '../services/secure_storage_service.dart';

/// Manages the complete authentication lifecycle for the TigerBay Staff App:
///
/// 1. **Dual-identifier login** � accepts either a Staff ID ("TB-0042")
///    or a work email ("jane@tigerbay.com").
/// 2. **OTP request** � calls [SupabaseService.requestOtp] and starts a
///    60-second countdown timer.
/// 3. **OTP verification** � calls [SupabaseService.verifyOtp] and stores
///    the authenticated [StaffMember].
/// 4. **Session persistence** � after OTP verification, the [StaffMember]
///    JSON is persisted to flutter_secure_storage so subsequent app opens
///    restore the session without re-OTP.
/// 5. **PIN lock** � on every warm start (session restored) the app shows
///    a PIN lock screen. [isSessionLocked] drives this. [unlockSession]
///    clears the lock after PIN verification.
/// 6. **Live tier updates** � exposes [updateTierLevel].
/// 7. **Session termination** � [signOut] clears the Supabase session and
///    all local state including the persisted JSON.
class AuthProvider extends ChangeNotifier {
  final SupabaseService _supabaseService;
  final SecureStorageService _secureStorage;

  AuthProvider({
    SupabaseService? supabaseService,
    SecureStorageService? secureStorage,
  })  : _supabaseService = supabaseService ?? SupabaseService(),
        _secureStorage = secureStorage ?? SecureStorageService();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  StaffMember? _staff;
  bool _isLoading = false;
  String? _error;
  bool _otpRequested = false;
  String? _currentIdentifier;
  int _countdown = 0;
  Timer? _countdownTimer;
  bool _isSessionLocked = false;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  StaffMember? get staff => _staff;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _staff != null;
  bool get otpRequested => _otpRequested;
  String? get currentIdentifier => _currentIdentifier;
  int get countdown => _countdown;
  bool get canResendOtp => _countdown <= 0 && _otpRequested;
  bool get isSessionLocked => _isSessionLocked;

  // ---------------------------------------------------------------------------
  // Session Restore (warm start)
  // ---------------------------------------------------------------------------

  /// Attempts to restore a previously authenticated session from secure storage.
  /// If successful, sets [isSessionLocked] = true so PIN screen is shown.
  Future<bool> restoreSession() async {
    try {
      final json = await _secureStorage.getStaffJson();
      if (json == null || json.isEmpty) return false;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      _staff = StaffMember.fromJson(decoded);
      _isSessionLocked = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AuthProvider] Session restore failed: $e');
      await _secureStorage.clearStaffJson();
      return false;
    }
  }

  /// Persists the current [StaffMember] to secure storage after OTP login.
  Future<void> persistSession() async {
    if (_staff == null) return;
    try {
      final json = jsonEncode(_staff!.toJson());
      await _secureStorage.saveStaffJson(json);
    } catch (e) {
      debugPrint('[AuthProvider] Session persist failed (non-fatal): $e');
    }
  }

  Future<void> clearPersistedSession() async {
    await _secureStorage.clearStaffJson();
  }

  // ---------------------------------------------------------------------------
  // PIN Lock / Unlock
  // ---------------------------------------------------------------------------

  void lockSession() {
    _isSessionLocked = true;
    notifyListeners();
  }

  void unlockSession() {
    _isSessionLocked = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // OTP Request
  // ---------------------------------------------------------------------------

  Future<void> requestOtp(String identifier) async {
    _setLoading(true);
    _error = null;
    try {
      await _supabaseService.requestOtp(identifier.trim());
      _currentIdentifier = identifier.trim();
      _otpRequested = true;
      _startCountdown();
    } catch (e) {
      _error = _parseError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> resendOtp() async {
    if (_currentIdentifier == null) return;
    if (!canResendOtp) return;
    _setLoading(true);
    _error = null;
    try {
      await _supabaseService.requestOtp(_currentIdentifier!);
      _startCountdown();
    } catch (e) {
      _error = _parseError(e);
    } finally {
      _setLoading(false);
    }
  }

  // ---------------------------------------------------------------------------
  // OTP Verification
  // ---------------------------------------------------------------------------

  Future<bool> verifyOtp(String code) async {
    if (_currentIdentifier == null) {
      _error = 'No OTP was requested. Please go back and try again.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    _error = null;
    try {
      final staffMember = await _supabaseService.verifyOtp(
        _currentIdentifier!,
        code.trim(),
      );
      if (!staffMember.isActive) {
        _error = 'Your account has been deactivated. Contact your Branch Manager.';
        _setLoading(false);
        return false;
      }
      _staff = staffMember;
      _cancelCountdown();
      _error = null;
      _setLoading(false);
      await persistSession();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _setLoading(false);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Live Tier Updates
  // ---------------------------------------------------------------------------

  void updateTierLevel(String newTier) {
    if (_staff == null) return;
    _staff = _staff!.copyWith(tierLevel: newTier);
    notifyListeners();
  }

  void markInactive() {
    if (_staff == null) return;
    _staff = _staff!.copyWith(isActive: false);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Session Termination
  // ---------------------------------------------------------------------------

  Future<void> signOut() async {
    try {
      await _supabaseService.signOut();
    } catch (e) {
      debugPrint('[AuthProvider] Sign-out error (non-fatal): $e');
    }
    await clearPersistedSession();
    _staff = null;
    _otpRequested = false;
    _currentIdentifier = null;
    _error = null;
    _isSessionLocked = false;
    _cancelCountdown();
    notifyListeners();
  }

  void resetOtpFlow() {
    _otpRequested = false;
    _currentIdentifier = null;
    _error = null;
    _cancelCountdown();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // PIN Setup Helper
  // ---------------------------------------------------------------------------

  bool get needsPinSetup => _staff != null && !_staff!.hasPinConfigured;

  // ---------------------------------------------------------------------------
  // Countdown Timer
  // ---------------------------------------------------------------------------

  void _startCountdown() {
    _cancelCountdown();
    _countdown = AppConstants.otpCountdownSeconds;
    notifyListeners();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (_countdown > 0) {
          _countdown--;
          notifyListeners();
        } else {
          _cancelCountdown();
        }
      },
    );
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  String _parseError(dynamic error) {
    final message = error.toString().toLowerCase();
    if (message.contains('inactive') || message.contains('deactivated')) {
      return 'This account has been deactivated. Contact your Branch Manager.';
    }
    if (message.contains('not found') || message.contains('no staff')) {
      return 'No staff account found for this identifier. Check and try again.';
    }
    if (message.contains('invalid') || message.contains('expired')) {
      return 'Invalid or expired OTP. Please request a new code.';
    }
    if (message.contains('network') || message.contains('socket')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  void dispose() {
    _cancelCountdown();
    super.dispose();
  }
}
