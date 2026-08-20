import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

/// Maps to `shift_logs`. A row is created on check-in and closed out on
/// check-out. `status` starts as ACTIVE and transitions to COMPLETED
/// (normal checkout) or FLAGGED (e.g. backend-side anomaly detection —
/// such as a shift left open past a threshold, or geofence mismatch found
/// on reconciliation).
class ShiftLog extends Equatable {
  final String id;
  final String staffId;
  final String branchId;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final double? totalShiftHours;
  final double checkInLat;
  final double checkInLng;
  final String checkInWifiBssid;
  final String status; // 'ACTIVE' | 'COMPLETED' | 'FLAGGED'

  const ShiftLog({
    required this.id,
    required this.staffId,
    required this.branchId,
    required this.checkInTime,
    this.checkOutTime,
    this.totalShiftHours,
    required this.checkInLat,
    required this.checkInLng,
    required this.checkInWifiBssid,
    this.status = AppConstants.shiftActive,
  });

  bool get isActive => status == AppConstants.shiftActive;

  /// Live duration of the shift. If still active, computed against "now".
  Duration currentDuration({DateTime? now}) {
    final end = checkOutTime ?? (now ?? DateTime.now());
    return end.difference(checkInTime);
  }

  factory ShiftLog.fromJson(Map<String, dynamic> json) {
    final rawCheckInTime = json['check_in_time'] ?? json['checkInTime'];
    final rawCheckOutTime = json['check_out_time'] ?? json['checkOutTime'];
    final rawTotalHours = json['total_shift_hours'] ?? json['totalShiftHours'];
    final rawLat = json['check_in_lat'] ?? json['checkInLat'] ?? 0.0;
    final rawLng = json['check_in_lng'] ?? json['checkInLng'] ?? 0.0;
    final rawWifi = json['check_in_wifi_bssid'] ?? json['checkInWifiBssid'] ?? 'N/A';

    return ShiftLog(
      id: (json['id'] ?? '').toString(),
      staffId: (json['staff_id'] ?? json['staffId'] ?? '').toString(),
      branchId: (json['branch_id'] ?? json['branchId'] ?? '').toString(),
      checkInTime: rawCheckInTime != null
          ? DateTime.tryParse(rawCheckInTime.toString()) ?? DateTime.now()
          : DateTime.now(),
      checkOutTime: rawCheckOutTime != null
          ? DateTime.tryParse(rawCheckOutTime.toString())
          : null,
      totalShiftHours: rawTotalHours != null
          ? (rawTotalHours is num ? rawTotalHours.toDouble() : double.tryParse(rawTotalHours.toString()))
          : null,
      checkInLat: rawLat is num ? rawLat.toDouble() : (double.tryParse(rawLat.toString()) ?? 0.0),
      checkInLng: rawLng is num ? rawLng.toDouble() : (double.tryParse(rawLng.toString()) ?? 0.0),
      checkInWifiBssid: rawWifi.toString(),
      status: (json['status'] ?? AppConstants.shiftActive).toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'staffId': staffId,
      'branchId': branchId,
      'checkInTime': checkInTime.toIso8601String(),
      'checkOutTime': checkOutTime?.toIso8601String(),
      'totalShiftHours': totalShiftHours,
      'checkInLat': checkInLat,
      'checkInLng': checkInLng,
      'checkInWifiBssid': checkInWifiBssid,
      'status': status,
    };
  }

  ShiftLog copyWith({
    DateTime? checkOutTime,
    double? totalShiftHours,
    String? status,
  }) {
    return ShiftLog(
      id: id,
      staffId: staffId,
      branchId: branchId,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      totalShiftHours: totalShiftHours ?? this.totalShiftHours,
      checkInLat: checkInLat,
      checkInLng: checkInLng,
      checkInWifiBssid: checkInWifiBssid,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
        id,
        staffId,
        branchId,
        checkInTime,
        checkOutTime,
        totalShiftHours,
        checkInLat,
        checkInLng,
        checkInWifiBssid,
        status,
      ];
}
