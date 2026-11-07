import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

/// Represents a row in the `staff_leave_requests` table.
///
/// Status lifecycle:
///   pending → approved | rejected
///
/// [leaveType] is one of the four values defined in [AppConstants]:
///   'sick' | 'casual' | 'annual' | 'unpaid'
class LeaveRequest extends Equatable {
  final String id;
  final String staffId;
  final String venueId;
  final String leaveType; // AppConstants.leaveType*
  final DateTime startDate;
  final DateTime endDate;
  final String reason;

  /// One of [AppConstants.leaveStatusPending], [AppConstants.leaveStatusApproved],
  /// or [AppConstants.leaveStatusRejected].
  final String status;

  /// Optional note added by the manager when approving or rejecting.
  final String? managerNote;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LeaveRequest({
    required this.id,
    required this.staffId,
    required this.venueId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.status = AppConstants.leaveStatusPending,
    this.managerNote,
    this.createdAt,
    this.updatedAt,
  });

  // ── Convenience getters ────────────────────────────────────────────────────

  bool get isPending => status == AppConstants.leaveStatusPending;
  bool get isApproved => status == AppConstants.leaveStatusApproved;
  bool get isRejected => status == AppConstants.leaveStatusRejected;

  /// Inclusive number of calendar days covered by this leave request.
  int get durationDays => endDate.difference(startDate).inDays + 1;

  // ── Serialisation ──────────────────────────────────────────────────────────

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id'] as String,
      staffId: json['staff_id'] as String,
      venueId: json['venue_id'] as String,
      leaveType: json['leave_type'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      reason: json['reason'] as String? ?? '',
      status: json['status'] as String? ?? AppConstants.leaveStatusPending,
      managerNote: json['manager_note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'staff_id': staffId,
      'venue_id': venueId,
      'leave_type': leaveType,
      // Database stores dates as DATE (no time component).
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'reason': reason,
      'status': status,
      if (managerNote != null) 'manager_note': managerNote,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  LeaveRequest copyWith({
    String? status,
    String? managerNote,
    DateTime? updatedAt,
  }) {
    return LeaveRequest(
      id: id,
      staffId: staffId,
      venueId: venueId,
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      status: status ?? this.status,
      managerNote: managerNote ?? this.managerNote,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        staffId,
        venueId,
        leaveType,
        startDate,
        endDate,
        reason,
        status,
        managerNote,
        createdAt,
        updatedAt,
      ];
}
