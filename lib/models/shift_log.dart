import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

/// Maps directly to the `timesheets` table in Supabase.
class ShiftLog extends Equatable {
  final String id;
  final String staffId;
  final String branchId; // venue_id in timesheets
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final double? totalShiftHours;
  final double checkInLat;
  final double checkInLng;
  final double? distanceFromBranchMeters;
  final bool isWithinGeofence;
  final String? notes;
  final String checkInWifiBssid;
  final String status; // 'ACTIVE' | 'COMPLETED' | 'ABSENT'

  const ShiftLog({
    required this.id,
    required this.staffId,
    required this.branchId,
    required this.checkInTime,
    this.checkOutTime,
    this.totalShiftHours,
    required this.checkInLat,
    required this.checkInLng,
    this.distanceFromBranchMeters,
    this.isWithinGeofence = true,
    this.notes,
    required this.checkInWifiBssid,
    this.status = AppConstants.shiftActive,
  });

  bool get isActive => status == AppConstants.shiftActive;
  bool get isAbsent => notes?.toUpperCase().contains('ABSENT') ?? false;

  /// Live duration of the shift. If still active, computed against "now".
  Duration currentDuration({DateTime? now}) {
    final end = checkOutTime ?? (now ?? DateTime.now());
    return end.difference(checkInTime);
  }

  factory ShiftLog.fromJson(Map<String, dynamic> json) {
    final rawCheckInTime =
        json['clock_in'] ?? json['check_in_time'] ?? json['checkInTime'];
    final rawCheckOutTime =
        json['clock_out'] ?? json['check_out_time'] ?? json['checkOutTime'];
    final rawTotalHours = json['total_shift_hours'] ?? json['totalShiftHours'];

    final rawLat = json['device_latitude'] ??
        json['check_in_lat'] ??
        json['checkInLat'] ??
        0.0;
    final rawLng = json['device_longitude'] ??
        json['check_in_lng'] ??
        json['checkInLng'] ??
        0.0;
    final rawDistance =
        json['distance_from_branch_meters'] ?? json['distanceFromBranchMeters'];
    final rawGeofence =
        json['is_within_geofence'] ?? json['isWithinGeofence'] ?? true;
    final rawWifi =
        json['check_in_wifi_bssid'] ?? json['checkInWifiBssid'] ?? 'N/A';
    final notes = json['notes']?.toString();

    final checkIn = rawCheckInTime != null
        ? DateTime.tryParse(rawCheckInTime.toString())?.toLocal() ??
            DateTime.now()
        : DateTime.now();

    final checkOut = rawCheckOutTime != null
        ? DateTime.tryParse(rawCheckOutTime.toString())?.toLocal()
        : null;

    String resolvedStatus = (json['status'] ?? '').toString();
    if (resolvedStatus.isEmpty) {
      if (notes != null && notes.toUpperCase().contains('ABSENT')) {
        resolvedStatus = 'ABSENT';
      } else if (checkOut == null) {
        resolvedStatus = AppConstants.shiftActive;
      } else {
        resolvedStatus = AppConstants.shiftCompleted;
      }
    }

    return ShiftLog(
      id: (json['id'] ?? '').toString(),
      staffId: (json['staff_id'] ?? json['staffId'] ?? '').toString(),
      branchId:
          (json['venue_id'] ?? json['branch_id'] ?? json['branchId'] ?? '')
              .toString(),
      checkInTime: checkIn,
      checkOutTime: checkOut,
      totalShiftHours: rawTotalHours != null
          ? (rawTotalHours is num
              ? rawTotalHours.toDouble()
              : double.tryParse(rawTotalHours.toString()))
          : null,
      checkInLat: rawLat is num
          ? rawLat.toDouble()
          : (double.tryParse(rawLat.toString()) ?? 0.0),
      checkInLng: rawLng is num
          ? rawLng.toDouble()
          : (double.tryParse(rawLng.toString()) ?? 0.0),
      distanceFromBranchMeters: rawDistance != null
          ? (rawDistance is num
              ? rawDistance.toDouble()
              : double.tryParse(rawDistance.toString()))
          : null,
      isWithinGeofence:
          rawGeofence == true || rawGeofence.toString().toLowerCase() == 'true',
      notes: notes,
      checkInWifiBssid: rawWifi.toString(),
      status: resolvedStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'staff_id': staffId,
      'venue_id': branchId,
      'clock_in': checkInTime.toIso8601String(),
      'clock_out': checkOutTime?.toIso8601String(),
      'device_latitude': checkInLat,
      'device_longitude': checkInLng,
      'distance_from_branch_meters': distanceFromBranchMeters,
      'is_within_geofence': isWithinGeofence,
      'notes': notes,
      'status': status,
    };
  }

  ShiftLog copyWith({
    DateTime? checkOutTime,
    double? totalShiftHours,
    String? status,
    String? notes,
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
      distanceFromBranchMeters: distanceFromBranchMeters,
      isWithinGeofence: isWithinGeofence,
      notes: notes ?? this.notes,
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
        distanceFromBranchMeters,
        isWithinGeofence,
        notes,
        checkInWifiBssid,
        status,
      ];
}
