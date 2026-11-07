import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../models/permission_check_result.dart';
import 'package:tigerbay_staff_app/providers/auth_provider.dart';
import '../services/permission_guard_service.dart';
import 'not_permitted_dialog.dart';

/// A button wrapper that enforces **live RPC permission checks** before
/// executing any sensitive action.
///
/// When tapped, [PermissionGuardedButton]:
/// 1. Shows an inline loading spinner (replaces child content).
/// 2. Calls [PermissionGuardService.check] â†’ Supabase `check_staff_permission`.
/// 3. If [PermissionCheckResult.isAllowed]:
///    - Calls [onPressed] to execute the permitted action.
/// 4. If denied or the account is inactive:
///    - Updates [AuthProvider] with the latest tier from the database.
///    - Presents [NotPermittedDialog] with the current tier label.
///    - Does NOT call [onPressed].
///
/// Usage:
/// ```dart
/// PermissionGuardedButton(
///   staffId: staff.id,
///   requiredPermission: AppConstants.permCanOverrideTables,
///   label: 'Override Table',
///   icon: Icons.table_restaurant_rounded,
///   onPressed: () async => tableProvider.updateStatus(...),
/// )
/// ```
class PermissionGuardedButton extends StatefulWidget {
  /// The UUID of the staff member whose permissions are being checked.
  final String staffId;

  /// The permission key to check (e.g. `'can_override_tables'`).
  /// Must match a column name in the Supabase `staff_roles_permissions`
  /// table and the `p_required_permission` RPC parameter.
  final String requiredPermission;

  /// Label displayed on the button.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// The action to execute if the live permission check passes.
  /// This is only called when [PermissionCheckResult.isAllowed] is `true`.
  final Future<void> Function() onPressed;

  /// Optional custom button style. Defaults to the theme's
  /// [ElevatedButton] style when null.
  final ButtonStyle? style;

  /// Whether the button is externally disabled (e.g. while another
  /// operation is in progress). When `true`, the live check is never
  /// executed.
  final bool enabled;

  const PermissionGuardedButton({
    super.key,
    required this.staffId,
    required this.requiredPermission,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style,
    this.enabled = true,
  });

  @override
  State<PermissionGuardedButton> createState() =>
      _PermissionGuardedButtonState();
}

class _PermissionGuardedButtonState
    extends State<PermissionGuardedButton> {
  /// True while the live permission RPC is in-flight.
  bool _isChecking = false;

  final PermissionGuardService _guardService = PermissionGuardService();

  Future<void> _handleTap() async {
    if (_isChecking || !widget.enabled) return;

    setState(() => _isChecking = true);

    final authProvider = context.read<AuthProvider>();

    try {
      final result = await _guardService.check(
        staffId: widget.staffId,
        requiredPermission: widget.requiredPermission,
      );

      if (!mounted) return;

      if (result.isAllowed) {
        // Permission confirmed â€” execute the protected action.
        await widget.onPressed();
      } else {
        // Permission denied or account deactivated:
        // 1. Sync the locally-cached tier level with the DB-returned value.
        authProvider.updateTierLevel(result.currentTier);

        // 2. Mark the account inactive locally if `is_active` changed.
        if (!result.isActive) {
          authProvider.markInactive();
        }

        // 3. Present the spec-mandated "Action Not Permitted" dialog.
        if (mounted) {
          await NotPermittedDialog.show(
            context,
            tierLevel: result.currentTier,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = !widget.enabled || _isChecking;

    return ElevatedButton(
      style: widget.style,
      onPressed: isDisabled ? null : _handleTap,
      child: _isChecking
          ? _LoadingContent(label: widget.label)
          : _ButtonContent(icon: widget.icon, label: widget.label),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal content widgets
// ---------------------------------------------------------------------------

/// Shown while the live permission RPC is in-flight.
class _LoadingContent extends StatelessWidget {
  final String label;

  const _LoadingContent({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Checking...',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Normal button content with optional icon and label.
class _ButtonContent extends StatelessWidget {
  final IconData? icon;
  final String label;

  const _ButtonContent({this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    if (icon == null) return Text(label);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Compact icon-only variant
// ---------------------------------------------------------------------------

/// A compact [IconButton] variant of [PermissionGuardedButton].
///
/// Shows a small spinner overlay on the icon while the live RPC check
/// is in-flight, then either executes [onPressed] or shows
/// [NotPermittedDialog].
///
/// Usage:
/// ```dart
/// PermissionGuardedIconButton(
///   staffId: staff.id,
///   requiredPermission: AppConstants.permCanIssuePoints,
///   icon: Icons.star_rounded,
///   tooltip: 'Issue Points',
///   onPressed: () async => _issuePoints(),
/// )
/// ```
class PermissionGuardedIconButton extends StatefulWidget {
  final String staffId;
  final String requiredPermission;
  final IconData icon;
  final String? tooltip;
  final Future<void> Function() onPressed;
  final Color? iconColor;
  final bool enabled;

  const PermissionGuardedIconButton({
    super.key,
    required this.staffId,
    required this.requiredPermission,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconColor,
    this.enabled = true,
  });

  @override
  State<PermissionGuardedIconButton> createState() =>
      _PermissionGuardedIconButtonState();
}

class _PermissionGuardedIconButtonState
    extends State<PermissionGuardedIconButton> {
  bool _isChecking = false;
  final PermissionGuardService _guardService = PermissionGuardService();

  Future<void> _handleTap() async {
    if (_isChecking || !widget.enabled) return;
    setState(() => _isChecking = true);

    final authProvider = context.read<AuthProvider>();

    try {
      final result = await _guardService.check(
        staffId: widget.staffId,
        requiredPermission: widget.requiredPermission,
      );

      if (!mounted) return;

      if (result.isAllowed) {
        await widget.onPressed();
      } else {
        authProvider.updateTierLevel(result.currentTier);
        if (!result.isActive) authProvider.markInactive();
        if (mounted) {
          await NotPermittedDialog.show(
            context,
            tierLevel: result.currentTier,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? '',
      child: InkWell(
        onTap: (_isChecking || !widget.enabled) ? null : _handleTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _isChecking
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.iconColor ?? AppColors.gold,
                    ),
                  ),
                )
              : Icon(
                  widget.icon,
                  color: widget.iconColor ?? AppColors.gold,
                ),
        ),
      ),
    );
  }
}
