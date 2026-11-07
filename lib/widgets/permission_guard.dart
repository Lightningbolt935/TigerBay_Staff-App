import 'package:flutter/material.dart';
import 'package:tigerbay_staff_app/providers/auth_provider.dart';
import '../services/permission_guard_service.dart';
import 'access_denied_dialog.dart';
import 'not_permitted_dialog.dart';

/// Wraps any restricted action. Provides two modes of operation:
///
/// 1. **[run]** (static, cached) â€” checks a pre-computed boolean.
///    Used for UI-level gating where a full RPC round-trip is not required
///    (e.g., hiding/disabling buttons based on cached permissions).
///
/// 2. **[runLive]** (static, real-time) â€” performs a live database permission
///    check via [PermissionGuardService] before executing the action.
///    Used for **every sensitive operational action** (overriding tables,
///    altering bookings, issuing manual points, issuing refunds) as mandated
///    by the spec.
///
/// Example (cached):
/// ```dart
/// onPressed: () => PermissionGuard.run(
///   context,
///   allowed: staffProvider.canOverrideTables,
///   action: () => tableProvider.updateStatus(...),
/// ),
/// ```
///
/// Example (live):
/// ```dart
/// onPressed: () => PermissionGuard.runLive(
///   context,
///   staffId: staff.id,
///   requiredPermission: AppConstants.permCanOverrideTables,
///   authProvider: authProvider,
///   action: () async => tableProvider.updateStatus(...),
/// ),
/// ```
class PermissionGuard {
  PermissionGuard._();

  // ---------------------------------------------------------------------------
  // Cached permission check (backward-compatible)
  // ---------------------------------------------------------------------------

  /// Checks a pre-computed [allowed] boolean and either executes [action]
  /// or shows the [AccessDeniedDialog].
  ///
  /// This method does NOT perform a live database query â€” it relies on
  /// the permission booleans cached on the [StaffMember] at login time.
  static void run(
    BuildContext context, {
    required bool allowed,
    required VoidCallback action,
  }) {
    if (allowed) {
      action();
    } else {
      AccessDeniedDialog.show(context);
    }
  }

  // ---------------------------------------------------------------------------
  // Live permission check (real-time database query)
  // ---------------------------------------------------------------------------

  /// Performs a **real-time permission check** against the database before
  /// executing [action].
  ///
  /// This method:
  /// 1. Calls [PermissionGuardService.check] which invokes the Supabase
  ///    `check_staff_permission` RPC.
  /// 2. If `is_permitted == true` AND `is_active == true`:
  ///    - Executes the [action] callback.
  /// 3. If `is_permitted == false` OR `is_active == false`:
  ///    - Aborts the action immediately.
  ///    - Updates the [AuthProvider]'s tier level with the freshly-fetched
  ///      [currentTier].
  ///    - Shows the [NotPermittedDialog] with the current tier label.
  ///
  /// Parameters:
  /// - [context]            â€” BuildContext for showing the dialog.
  /// - [staffId]            â€” UUID of the staff member to check.
  /// - [requiredPermission] â€” Permission string (e.g. 'can_override_tables').
  /// - [authProvider]       â€” The [AuthProvider] instance to update tier state.
  /// - [action]             â€” Async callback to execute if permitted.
  /// - [guardService]       â€” Optional custom service instance for testing.
  static Future<void> runLive(
    BuildContext context, {
    required String staffId,
    required String requiredPermission,
    required AuthProvider authProvider,
    required Future<void> Function() action,
    PermissionGuardService? guardService,
  }) async {
    final service = guardService ?? PermissionGuardService();

    final result = await service.check(
      staffId: staffId,
      requiredPermission: requiredPermission,
    );

    if (result.isAllowed) {
      // Permission granted â€” execute the protected action.
      await action();
    } else {
      // Permission denied or account deactivated.
      // Update local state with the freshly-fetched tier level.
      authProvider.updateTierLevel(result.currentTier);

      // If the account was deactivated, also mark it locally.
      if (!result.isActive) {
        authProvider.markInactive();
      }

      // Show the spec-mandated "Action Not Permitted" dialog.
      if (context.mounted) {
        await NotPermittedDialog.show(
          context,
          tierLevel: result.currentTier,
        );
      }
    }
  }
}
