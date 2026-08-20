import 'package:equatable/equatable.dart';
import 'staff_roles_permissions.dart';

/// Maps to the `staff_members` table in Supabase/PostgreSQL.
///
/// Schema fields covered:
/// - [id]        — UUID primary key.
/// - [staffId]   — Human-readable staff identifier (e.g. "TB-0042").
/// - [name]      — Short display name.
/// - [fullName]  — Full legal name (maps to `full_name`).
/// - [email]     — Work email address (unique).
/// - [role]      — Role label (e.g. "Manager", "Waiter").
/// - [branchId]  — UUID of the branch this staff member belongs to.
///                 ALL data queries MUST be scoped to this branch.
/// - [venueId]   — UUID of the venue (maps to `venue_id`). Nullable.
/// - [tierLevel] — Current permission tier label (e.g. "Tier A", "Tier B").
///                 Duplicated from [permissions] for quick access in UI.
/// - [isActive]  — If false, the staff member's session should be terminated
///                 and all actions blocked.
/// - [pinHash]   — Nullable. Null means PIN setup is not yet complete.
class StaffMember extends Equatable {
  final String id;
  final String staffId;
  final String name;
  final String? fullName;   // full_name column
  final String email;
  final String? role;       // role column
  final String? pinHash;
  final String? branchId;   // nullable — not all rows guarantee this
  final String? venueId;    // venue_id column
  final String tierLevel;
  final StaffRolesPermissions permissions;
  final bool isActive;
  final DateTime? createdAt; // created_at column

  const StaffMember({
    required this.id,
    required this.staffId,
    required this.name,
    this.fullName,
    required this.email,
    this.role,
    this.pinHash,
    this.branchId,
    this.venueId,
    required this.tierLevel,
    required this.permissions,
    required this.isActive,
    this.createdAt,
  });

  /// Whether the staff member has completed PIN configuration.
  bool get hasPinConfigured => pinHash != null && pinHash!.isNotEmpty;

  /// Deserializes from a Supabase/PostgreSQL row (snake_case keys).
  ///
  /// Expected JSON shape:
  /// ```json
  /// {
  ///   "id": "uuid",
  ///   "staff_id": "TB-0042",
  ///   "name": "Jane Doe",
  ///   "email": "jane@tigerbay.com",
  ///   "pin_hash": "sha256...",
  ///   "branch_id": "uuid",
  ///   "tier_level": "Tier A",
  ///   "is_active": true,
  ///   "permissions": { ... }
  /// }
  /// ```
  /// Gracefully parses both snake_case Supabase column names AND camelCase
  /// legacy keys. This ensures compatibility across different RPC response
  /// shapes without requiring changes at every call site.
  ///
  /// Key resolution order:
  /// - `staff_id`  → `staffId`  (fallback: `staffId` camelCase)
  /// - `branch_id` → `branchId` (fallback: `branchId` camelCase)
  /// - `is_active` → `isActive` (fallback: `isActive` camelCase)
  /// - `pin_hash`  → `pinHash`  (fallback: `pinHash`  camelCase)
  /// - `tier_level`→ `tierLevel`(fallback: `tierLevel` camelCase)
  factory StaffMember.fromJson(Map<String, dynamic> json) {
    // Resolve each field using safe toString conversions to prevent int/String type cast errors.
    final rawId = (json['id'] ?? '').toString();
    final rawStaffId = (json['staff_id'] ?? json['staffId'] ?? '').toString();
    final rawBranchId = (json['branch_id'] ?? json['branchId'])?.toString();
    final rawIsActive = json['is_active'] is bool
        ? json['is_active'] as bool
        : (json['isActive'] is bool ? json['isActive'] as bool : true);
    final rawPinHash = (json['pin_hash'] ?? json['pinHash'])?.toString();
    final rawTierLevel = (json['tier_level'] ?? json['tierLevel'] ?? 'Tier A').toString();
    final rawFullName = (json['full_name'] ?? json['fullName'])?.toString();
    final rawVenueId = (json['venue_id'] ?? json['venueId'])?.toString();
    final rawRole = json['role']?.toString();
    final rawName = (json['name'] ?? json['full_name'] ?? 'Staff').toString();
    final rawEmail = (json['email'] ?? '').toString();
    final rawCreatedAt = json['created_at'] != null
        ? DateTime.tryParse(json['created_at'].toString())
        : null;

    // Permissions may be absent from slim responses — use defaults.
    final permsJson = json['permissions'] as Map<String, dynamic>?;
    final permissions = permsJson != null
        ? StaffRolesPermissions.fromJson(permsJson)
        : StaffRolesPermissions(
            id: '',
            tierName: rawTierLevel,
          );

    return StaffMember(
      id: rawId,
      staffId: rawStaffId,
      name: rawName,
      fullName: rawFullName,
      email: rawEmail,
      role: rawRole,
      pinHash: rawPinHash,
      branchId: rawBranchId,
      venueId: rawVenueId,
      tierLevel: rawTierLevel,
      permissions: permissions,
      isActive: rawIsActive,
      createdAt: rawCreatedAt,
    );
  }

  /// Serializes to snake_case keys for Supabase compatibility.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'staff_id': staffId,
      'name': name,
      'full_name': fullName,
      'email': email,
      'role': role,
      'pin_hash': pinHash,
      'branch_id': branchId,
      'venue_id': venueId,
      'tier_level': tierLevel,
      'permissions': permissions.toJson(),
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// Creates a copy of this [StaffMember] with the given fields replaced.
  /// Particularly useful when [PermissionGuardService] detects a tier change
  /// and needs to update [tierLevel] without refetching the full profile.
  StaffMember copyWith({
    String? id,
    String? staffId,
    String? name,
    String? fullName,
    String? email,
    String? role,
    String? pinHash,
    String? branchId,
    String? venueId,
    String? tierLevel,
    StaffRolesPermissions? permissions,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return StaffMember(
      id: id ?? this.id,
      staffId: staffId ?? this.staffId,
      name: name ?? this.name,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      pinHash: pinHash ?? this.pinHash,
      branchId: branchId ?? this.branchId,
      venueId: venueId ?? this.venueId,
      tierLevel: tierLevel ?? this.tierLevel,
      permissions: permissions ?? this.permissions,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        staffId,
        name,
        fullName,
        email,
        role,
        pinHash,
        branchId,
        venueId,
        tierLevel,
        permissions,
        isActive,
        createdAt,
      ];
}
