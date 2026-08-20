import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles the full OTP lifecycle for staff authentication against
/// the `public.staff_auth_otps` Supabase table.
///
/// The flow is:
///   1. [requestStaffOtp] →
///      a. Validates the email against `public.staff_members` (must exist + active).
///      b. Generates a secure 6-digit OTP.
///      c. Inserts a row into `staff_auth_otps` with `staff_id`, `email`, `otp`,
///         and `expires_at` (which triggers the `send-otp-email` Edge Function
///         via the Database Webhook to dispatch the code by email).
///   2. [verifyStaffOtp] → queries the latest non-expired row for the given
///      email and validates the entered code.
class StaffAuthService {
  final SupabaseClient _client;

  StaffAuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Generates a cryptographically random 6-digit OTP (range: 100000–999999).
  /// Using an offset of 100000 guarantees the result is always exactly 6 digits
  /// without requiring zero-padding.
  String _generateOtp() {
    return (Random.secure().nextInt(900000) + 100000).toString();
  }

  // ---------------------------------------------------------------------------
  // Request OTP
  // ---------------------------------------------------------------------------

  /// Validates [email] against `public.staff_members`, generates a secure
  /// 6-digit OTP, and inserts it into `public.staff_auth_otps`.
  ///
  /// Steps:
  ///   1. Queries `staff_members` for an active record with the given email.
  ///      Throws if no match is found or the account is inactive.
  ///   2. Generates a `Random.secure()` 6-digit OTP (zero-padded).
  ///   3. Inserts `{ staff_id, email, otp, expires_at }` into `staff_auth_otps`.
  ///      The Database Webhook fires automatically and calls `send-otp-email`.
  ///
  /// Throws a descriptive [Exception] or [PostgrestException] on failure.
  Future<void> requestStaffOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    if (kDebugMode) {
      debugPrint('🔎 [StaffAuthService] Validating email against staff_members: $cleanEmail');
    }

    try {
      // ── Step 1: Validate against staff_members ──────────────────────────────
      final staffRow = await _client
          .from('staff_members')
          .select('staff_id, is_active')
          .eq('email', cleanEmail)
          .maybeSingle();

      if (staffRow == null) {
        throw Exception(
          'Staff member not registered or inactive. '
          'Please contact your Branch Manager.',
        );
      }

      final isActive = staffRow['is_active'] as bool? ?? false;
      if (!isActive) {
        throw Exception(
          'This account has been deactivated. '
          'Please contact your Branch Manager.',
        );
      }

      final staffId = staffRow['staff_id'] as String? ?? '';

      if (kDebugMode) {
        debugPrint('✅ [StaffAuthService] staff_members record found — staff_id: $staffId');
      }

      // ── Step 2: Generate OTP ────────────────────────────────────────────────
      final otp = _generateOtp();
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10));

      if (kDebugMode) {
        debugPrint('🔑 [StaffAuthService] Inserting OTP row for: $cleanEmail');
      }

      // ── Step 3: Insert into staff_auth_otps ─────────────────────────────────
      await _client.from('staff_auth_otps').insert({
        'staff_id': staffId,
        'email': cleanEmail,
        'otp': otp,
        'expires_at': expiresAt.toIso8601String(),
      });

      if (kDebugMode) {
        debugPrint(
          '✅ [StaffAuthService] OTP inserted for $cleanEmail (staff_id: $staffId). '
          'Webhook will dispatch email.',
        );
      }
    } on PostgrestException catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ [StaffAuthService] POSTGREST ERROR in requestStaffOtp:');
        debugPrint('   Message: ${e.message}');
        debugPrint('   Code:    ${e.code}');
        debugPrint('   Details: ${e.details}');
        debugPrint('   Hint:    ${e.hint}');
        debugPrint(stack.toString());
      }
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ [StaffAuthService] UNEXPECTED ERROR in requestStaffOtp: $e');
        debugPrint(stack.toString());
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Verify OTP
  // ---------------------------------------------------------------------------

  /// Queries the latest non-expired OTP row for [email] and validates
  /// [enteredOtp] against the stored value.
  ///
  /// Returns `true` if the code is correct and the row is not expired.
  ///
  /// Throws an [Exception] with a descriptive message if:
  ///   - No valid (non-expired) OTP row exists for this email.
  ///   - The entered code does not match the stored OTP.
  Future<bool> verifyStaffOtp(String email, String enteredOtp) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanOtp = enteredOtp.trim();

    if (kDebugMode) {
      debugPrint('🔍 [StaffAuthService] Verifying OTP for: $cleanEmail');
    }

    try {
      // Fetch the most recent non-expired OTP row for this email.
      final List<Map<String, dynamic>> rows = await _client
          .from('staff_auth_otps')
          .select('otp, expires_at')
          .eq('email', cleanEmail)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('expires_at', ascending: false)
          .limit(1);

      if (rows.isEmpty) {
        throw Exception(
          'No valid OTP found for $cleanEmail. '
          'The code may have expired — please request a new one.',
        );
      }

      final storedOtp = rows.first['otp'] as String?;

      if (storedOtp == null || storedOtp.isEmpty) {
        throw Exception('Stored OTP is invalid. Please request a new code.');
      }

      if (storedOtp != cleanOtp) {
        if (kDebugMode) {
          debugPrint(
            '❌ [StaffAuthService] OTP mismatch for $cleanEmail '
            '(entered: $cleanOtp)',
          );
        }
        throw Exception(
          'The verification code you entered is incorrect. Please try again.',
        );
      }

      if (kDebugMode) {
        debugPrint('✅ [StaffAuthService] OTP verified successfully for $cleanEmail');
      }
      return true;
    } on PostgrestException catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ [StaffAuthService] POSTGREST ERROR in verifyStaffOtp:');
        debugPrint('   Message: ${e.message}');
        debugPrint('   Code:    ${e.code}');
        debugPrint(stack.toString());
      }
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ [StaffAuthService] ERROR in verifyStaffOtp: $e');
        debugPrint(stack.toString());
      }
      rethrow;
    }
  }
}
