import 'package:equatable/equatable.dart';

/// Maps to `staff_roles_permissions`. Drives every permission guard in
/// the app (see widgets/permission_guard.dart). All flags default to
/// false — a tier must be explicitly granted access.
class StaffRolesPermissions extends Equatable {
  final String id;
  final String tierName; // 'Tier A', 'Tier B', 'Tier C'
  final bool canAlterBooking;
  final bool canIssuePoints;
  final bool canRedeemVouchers;
  final bool canOverrideTables;
  final bool canViewAnalytics;

  const StaffRolesPermissions({
    required this.id,
    required this.tierName,
    this.canAlterBooking = false,
    this.canIssuePoints = false,
    this.canRedeemVouchers = false,
    this.canOverrideTables = false,
    this.canViewAnalytics = false,
  });

  factory StaffRolesPermissions.fromJson(Map<String, dynamic> json) {
    return StaffRolesPermissions(
      id: json['id'] as String,
      tierName: json['tierName'] as String,
      canAlterBooking: json['canAlterBooking'] as bool? ?? false,
      canIssuePoints: json['canIssuePoints'] as bool? ?? false,
      canRedeemVouchers: json['canRedeemVouchers'] as bool? ?? false,
      canOverrideTables: json['canOverrideTables'] as bool? ?? false,
      canViewAnalytics: json['canViewAnalytics'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tierName': tierName,
      'canAlterBooking': canAlterBooking,
      'canIssuePoints': canIssuePoints,
      'canRedeemVouchers': canRedeemVouchers,
      'canOverrideTables': canOverrideTables,
      'canViewAnalytics': canViewAnalytics,
    };
  }

  @override
  List<Object?> get props => [
        id,
        tierName,
        canAlterBooking,
        canIssuePoints,
        canRedeemVouchers,
        canOverrideTables,
        canViewAnalytics,
      ];
}
