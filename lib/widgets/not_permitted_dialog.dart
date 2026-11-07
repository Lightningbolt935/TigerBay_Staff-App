import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Standard reusable modal dialog shown whenever a **live permission check**
/// fails (i.e., the `check_staff_permission` RPC returns `is_permitted: false`
/// or `is_active: false`).
///
/// This dialog is distinct from [AccessDeniedDialog] (which is used for
/// cached/static permission checks). [NotPermittedDialog] is specifically
/// designed for the live permission checking flow and displays the staff
/// member's **current tier level** so they know which access level they hold.
///
/// Spec-mandated content:
/// - **Title**: "Action Not Permitted"
/// - **Body**: "You do not have the required permissions for this action.
///   Contact your Branch Manager to upgrade your access level
///   (Current Tier: [Tier Level])."
/// - **Button**: "Dismiss"
///
/// Usage:
/// ```dart
/// NotPermittedDialog.show(context, tierLevel: 'Tier B');
/// ```
class NotPermittedDialog extends StatelessWidget {
  /// The staff member's current tier level, displayed in the dialog body.
  final String tierLevel;

  const NotPermittedDialog({super.key, required this.tierLevel});

  /// Shows the [NotPermittedDialog] as a centered modal dialog.
  ///
  /// Parameters:
  /// - [context]   — the [BuildContext] from the calling widget.
  /// - [tierLevel] — the current tier label to display (e.g. "Tier A").
  static Future<void> show(
    BuildContext context, {
    required String tierLevel,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NotPermittedDialog(tierLevel: tierLevel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- Warning icon ----
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.dangerBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.block_rounded,
                color: AppColors.danger,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),

            // ---- Title ----
            const Text(
              'Action Not Permitted',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            // ---- Body ----
            Text(
              'You do not have the required permissions for this action. '
              'Contact your Branch Manager to upgrade your access level '
              '(Current Tier: $tierLevel).',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // ---- Dismiss button ----
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
