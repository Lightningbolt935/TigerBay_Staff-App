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
    // Tolerant bool read: DB booleans arrive as bool, some RPC shapes as strings.
    bool asBool(Object? v) => v is bool ? v : v?.toString().toLowerCase() == 'true';

    // Accept BOTH camelCase (app-side JSON) and snake_case (raw
    // staff_roles_permissions rows) — previously a raw table row parsed to
    // ALL-FALSE permissions, causing spurious "Access Denied" for every tier.
    bool readFlag(String camel, String snake) =>
        asBool(json[camel]) || asBool(json[snake]);

    return StaffRolesPermissions(
      id: (json['id'] ?? '').toString(),
      tierName: (json['tierName'] ?? json['tier_name'] ?? 'Tier').toString(),
      canAlterBooking: readFlag('canAlterBooking', 'can_alter_booking'),
      canIssuePoints: readFlag('canIssuePoints', 'can_issue_points'),
      canRedeemVouchers: readFlag('canRedeemVouchers', 'can_redeem_vouchers'),
      canOverrideTables: readFlag('canOverrideTables', 'can_override_tables'),
      canViewAnalytics: readFlag('canViewAnalytics', 'can_view_analytics'),
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
