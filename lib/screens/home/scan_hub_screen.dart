import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import 'package:tigerbay_staff_app/providers/auth_provider.dart';
import '../../providers/staff_provider.dart';
import '../../widgets/permission_guard.dart';

/// Sample operational screen demonstrating a **live permission check**
/// before executing a sensitive transaction.
///
/// This screen shows a "Quick Issue Points" action that:
/// 1. Calls [PermissionGuard.runLive] with `'can_issue_points'`.
/// 2. If the live check passes â†’ executes a mock loyalty transaction
///    and shows a success snackbar.
/// 3. If the live check fails â†’ aborts and shows [NotPermittedDialog]
///    with the staff member's current tier.
///
/// This demonstrates the full live permission flow as specified:
/// - Real-time RPC call to `check_staff_permission`.
/// - Tier update on mismatch.
/// - Account deactivation detection.
/// - "Action Not Permitted" dialog with tier label.
class ScanHubDemoScreen extends StatefulWidget {
  const ScanHubDemoScreen({super.key});

  @override
  State<ScanHubDemoScreen> createState() => _ScanHubDemoScreenState();
}

class _ScanHubDemoScreenState extends State<ScanHubDemoScreen> {
  bool _isProcessing = false;

  /// Executes a mock "Issue Points" transaction, gated by a live
  /// permission check.
  Future<void> _issuePoints() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    final authProvider = context.read<AuthProvider>();
    final staffProvider = context.read<StaffProvider>();
    final staff = staffProvider.staff;

    if (staff == null) {
      setState(() => _isProcessing = false);
      return;
    }

    // ---- LIVE PERMISSION CHECK ----
    // This is the core demonstration: every sensitive action must go
    // through PermissionGuard.runLive() which queries the database
    // in real-time, NOT the cached permission booleans.
    await PermissionGuard.runLive(
      context,
      staffId: staff.id,
      requiredPermission: AppConstants.permCanIssuePoints,
      authProvider: authProvider,
      action: () async {
        // Simulated transaction â€” in production this would call
        // ApiService.submitLoyaltyTransaction with branch-scoped params.
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Points issued successfully!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      },
    );

    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  /// Executes a mock "Override Table" action, gated by a live
  /// permission check.
  Future<void> _overrideTable() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    final authProvider = context.read<AuthProvider>();
    final staffProvider = context.read<StaffProvider>();
    final staff = staffProvider.staff;

    if (staff == null) {
      setState(() => _isProcessing = false);
      return;
    }

    await PermissionGuard.runLive(
      context,
      staffId: staff.id,
      requiredPermission: AppConstants.permCanOverrideTables,
      authProvider: authProvider,
      action: () async {
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Table assignment overridden.'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      },
    );

    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffProvider = context.watch<StaffProvider>();
    final staff = staffProvider.staff;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Hub'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Staff info card ----
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff?.name ?? 'Staff Member',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Staff ID: ${staff?.staffId ?? 'â€”'}  â€¢  Tier: ${staff?.tierLevel ?? 'â€”'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Branch: ${staff?.branchId ?? 'â€”'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ---- Section title ----
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Each action performs a live database permission check '
                'before executing.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),

              // ---- Issue Points action ----
              _ActionCard(
                icon: Icons.star_rounded,
                iconColor: AppColors.gold,
                iconBgColor: AppColors.goldPale,
                title: 'Issue Loyalty Points',
                subtitle: 'Requires: can_issue_points',
                isProcessing: _isProcessing,
                onTap: _issuePoints,
              ),
              const SizedBox(height: 12),

              // ---- Override Table action ----
              _ActionCard(
                icon: Icons.table_restaurant_rounded,
                iconColor: AppColors.warning,
                iconBgColor: AppColors.tableReserved,
                title: 'Override Table Assignment',
                subtitle: 'Requires: can_override_tables',
                isProcessing: _isProcessing,
                onTap: _overrideTable,
              ),
              const SizedBox(height: 12),

              // ---- Info card ----
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.goldPale,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.gold, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'All operations are scoped to your assigned branch. '
                        'Permissions are verified in real-time.',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Internal action card widget used by [ScanHubDemoScreen].
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final bool isProcessing;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.isProcessing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: isProcessing ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isProcessing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
