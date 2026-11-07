/// Immutable result object returned by [SupabaseService.checkPermission]
/// and [PermissionGuardService.check].
///
/// Represents the real-time permission state fetched from the Supabase
/// `check_staff_permission` RPC. This is NOT derived from cached data —
/// it reflects the database's current truth at the moment of the call.
///
/// Fields map directly to the SQL RPC return columns:
///
/// | Dart field      | SQL column        | Type    |
/// |-----------------|-------------------|---------|
/// | [isPermitted]   | `is_permitted`    | bool    |
/// | [isActive]      | `is_active`       | bool    |
/// | [currentTier]   | `current_tier`    | text    |
/// | [branchId]      | `branch_id`       | uuid?   |
class PermissionCheckResult {
  /// Whether the staff member holds the specific requested permission.
  final bool isPermitted;

  /// Whether the staff member's account is still active. A `false` value
  /// means the session should be invalidated regardless of [isPermitted].
  final bool isActive;

  /// The staff member's current tier label (e.g. "Tier A", "Tier B",
  /// "Tier C"). May differ from the value cached at login if a Branch
  /// Manager updated the tier during the session.
  final String currentTier;

  /// The branch UUID associated with this permission check. Used to
  /// validate branch-scoped isolation — the caller can verify that the
  /// staff member is only acting on their assigned branch.
  /// May be null if the RPC does not return it.
  final String? branchId;

  const PermissionCheckResult({
    required this.isPermitted,
    required this.isActive,
    required this.currentTier,
    this.branchId,
  });

  /// Returns `true` only when the staff member is both **active** AND
  /// has the **required permission**. Both conditions must hold.
  bool get isAllowed => isPermitted && isActive;

  /// Constructs a [PermissionCheckResult] from the raw JSON map returned
  /// by the Supabase `check_staff_permission` RPC.
  ///
  /// Expected shape:
  /// ```json
  /// {
  ///   "is_permitted": true,
  ///   "is_active":    true,
  ///   "current_tier": "Tier A",
  ///   "branch_id":    "uuid-string"
  /// }
  /// ```
  factory PermissionCheckResult.fromJson(Map<String, dynamic> json) {
    return PermissionCheckResult(
      isPermitted: json['is_permitted'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? false,
      currentTier: json['current_tier'] as String? ?? 'Unknown',
      branchId: json['branch_id'] as String?,
    );
  }

  /// Returns a fail-closed [PermissionCheckResult] used whenever the
  /// RPC call fails (network error, timeout, unexpected exception).
  ///
  /// Defaults to the lowest possible tier ("Tier C") so the error
  /// message shown to the user is accurate about their access level.
  factory PermissionCheckResult.denied() {
    return const PermissionCheckResult(
      isPermitted: false,
      isActive: false,
      currentTier: 'Tier C',
      branchId: null,
    );
  }

  @override
  String toString() => 'PermissionCheckResult('
      'isPermitted: $isPermitted, '
      'isActive: $isActive, '
      'currentTier: $currentTier, '
      'branchId: $branchId)';
}
