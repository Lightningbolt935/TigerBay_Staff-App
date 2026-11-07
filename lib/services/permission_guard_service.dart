import 'package:flutter/material.dart';
import '../models/permission_check_result.dart';
import 'supabase_service.dart';

/// Service that performs **live database authorization checks** before
/// executing sensitive code callbacks.
///
/// **Fail-closed architecture**: On any error (network failure, RPC
/// exception, timeout), the service returns a denied [PermissionCheckResult]
/// with `isPermitted: false` and `currentTier: 'Tier C'`. This ensures
/// that a connectivity issue never inadvertently grants access.
///
/// Usage:
/// ```dart
/// final result = await PermissionGuardService().check(
///   staffId: staff.id,
///   requiredPermission: AppConstants.permCanOverrideTables,
/// );
///
/// if (result.isAllowed) {
///   // Execute the protected action
/// } else {
///   // Show NotPermittedDialog with result.currentTier
/// }
/// ```
class PermissionGuardService {
  final SupabaseService _supabaseService;

  /// Accepts an optional [SupabaseService] for dependency injection
  /// and testability. In production the default instance is used.
  PermissionGuardService({SupabaseService? supabaseService})
      : _supabaseService = supabaseService ?? SupabaseService();

  /// Performs a live permission check by calling the Supabase
  /// `check_staff_permission` RPC.
  ///
  /// Parameters:
  /// - [staffId]            — UUID of the staff member to verify.
  /// - [requiredPermission] — Permission key string matching the Supabase
  ///                          column name (e.g. `'can_override_tables'`).
  ///
  /// Returns a [PermissionCheckResult]. Check [PermissionCheckResult.isAllowed]
  /// to determine whether the action should proceed.
  ///
  /// **Fail-closed**: On any exception, returns
  /// `PermissionCheckResult.denied()` — never grants access on error.
  Future<PermissionCheckResult> check({
    required String staffId,
    required String requiredPermission,
  }) async {
    try {
      return await _supabaseService.checkPermission(
        staffId: staffId,
        requiredPermission: requiredPermission,
      );
    } catch (e) {
      // Fail closed: log the error but return a safe denied result.
      // currentTier is 'Tier C' (lowest) so the NotPermittedDialog
      // shows an accurate access level, not 'Unknown'.
      debugPrint('[PermissionGuardService] Live check failed: $e');
      return PermissionCheckResult.denied();
    }
  }

  /// Convenience method that checks permission and, if [isAllowed],
  /// executes the [onPermitted] callback.
  ///
  /// Returns the [PermissionCheckResult] regardless of outcome so the
  /// caller can show the appropriate UI (e.g. [NotPermittedDialog]).
  ///
  /// This method does NOT display any UI — the caller is responsible
  /// for handling the denied state.
  Future<PermissionCheckResult> checkAndExecute({
    required String staffId,
    required String requiredPermission,
    required Future<void> Function() onPermitted,
  }) async {
    final result = await check(
      staffId: staffId,
      requiredPermission: requiredPermission,
    );

    if (result.isAllowed) {
      await onPermitted();
    }

    return result;
  }
}
