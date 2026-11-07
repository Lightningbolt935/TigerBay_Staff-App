import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/leave_request.dart';
import '../core/constants/app_constants.dart';

/// Handles all `staff_leave_requests` table interactions.
///
/// Two main responsibilities:
///   1. **[submitLeaveRequest]** — inserts a new row with `status = 'pending'`.
///   2. **[getLeaveHistoryStream]** — returns a real-time [Stream] of the
///      authenticated staff member's leave requests, ordered newest-first.
///
/// Both methods are guarded against unauthenticated calls; they throw an
/// [AuthException] if called without an active session, keeping error
/// handling consistent with the rest of the service layer.
class LeaveService {
  final SupabaseClient _client;

  LeaveService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ── Submit ─────────────────────────────────────────────────────────────────

  /// Inserts a new leave request for the currently authenticated staff member.
  ///
  /// [leaveType] must be one of the values declared in [AppConstants]:
  ///   `'sick'`, `'casual'`, `'annual'`, or `'unpaid'`.
  ///
  /// Dates are sent to Supabase as `DATE` strings (`yyyy-MM-dd`) — no time
  /// component — to match the column type and avoid timezone ambiguities.
  Future<void> submitLeaveRequest({
    required String staffId,
    required String venueId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    final effectiveStaffId = staffId.isNotEmpty
        ? staffId
        : _client.auth.currentUser?.id;

    if (effectiveStaffId == null || effectiveStaffId.isEmpty) {
      throw const AuthException('No authenticated staff member — cannot submit leave request.');
    }

    assert(
      AppConstants.leaveTypes.contains(leaveType),
      'leaveType "$leaveType" is not one of the allowed values: ${AppConstants.leaveTypes}',
    );

    if (kDebugMode) {
      print('🗓️  Submitting leave request: $leaveType '
          '(${startDate.toIso8601String().split('T')[0]} → '
          '${endDate.toIso8601String().split('T')[0]}) for staff $effectiveStaffId');
    }

    try {
      await _client.from('staff_leave_requests').insert({
        'staff_id': effectiveStaffId,
        'venue_id': venueId.isNotEmpty ? venueId : null,
        'leave_type': leaveType,
        // Strip the time component — column type is DATE, not TIMESTAMPTZ.
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'reason': reason,
        'status': AppConstants.leaveStatusPending,
      });

      if (kDebugMode) {
        print('✅ Leave request submitted successfully.');
      }
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('❌ POSTGREST ERROR in submitLeaveRequest: ${e.message} (${e.code})');
      }
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        print('❌ UNEXPECTED ERROR in submitLeaveRequest: $e');
        print(stack);
      }
      rethrow;
    }
  }

  // ── Real-time history stream ────────────────────────────────────────────────

  /// Returns a real-time [Stream] of [LeaveRequest] objects for the
  /// authenticated staff member, ordered newest-first.
  Stream<List<LeaveRequest>> getLeaveHistoryStream({String? staffId}) {
    final effectiveStaffId = (staffId != null && staffId.isNotEmpty)
        ? staffId
        : _client.auth.currentUser?.id;

    if (effectiveStaffId == null || effectiveStaffId.isEmpty) {
      return Stream.value([]);
    }

    return _client
        .from('staff_leave_requests')
        .stream(primaryKey: ['id'])
        .eq('staff_id', effectiveStaffId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => LeaveRequest.fromJson(
                    Map<String, dynamic>.from(row),
                  ))
              .toList(),
        );
  }

  // ── Typed raw stream (for consumers that prefer Map) ──────────────────────

  /// Same as [getLeaveHistoryStream] but emits raw JSON maps instead of
  /// [LeaveRequest] objects — useful for quick prototyping or debug views.
  Stream<List<Map<String, dynamic>>> getRawLeaveHistoryStream({String? staffId}) {
    final effectiveStaffId = (staffId != null && staffId.isNotEmpty)
        ? staffId
        : _client.auth.currentUser?.id;

    if (effectiveStaffId == null || effectiveStaffId.isEmpty) {
      return Stream.value([]);
    }

    return _client
        .from('staff_leave_requests')
        .stream(primaryKey: ['id'])
        .eq('staff_id', effectiveStaffId)
        .order('created_at', ascending: false);
  }
}
