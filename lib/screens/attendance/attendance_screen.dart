import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../providers/shift_provider.dart';
import '../../providers/staff_provider.dart';
import '../../widgets/status_chip.dart';
import '../profile/staff_profile_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final staffProvider = context.read<StaffProvider>();
    final shiftProvider = context.read<ShiftProvider>();
    if (staffProvider.branch == null) {
      await staffProvider.loadBranch();
    }
    final staff = staffProvider.staff;
    final branch = staffProvider.branch;
    if (staff == null || branch == null) return;
    await shiftProvider.loadActiveShift(staff.id);
    await shiftProvider.refreshValidation(branch);
  }

  Future<void> _refreshLocation() async {
    final staffProvider = context.read<StaffProvider>();
    final shiftProvider = context.read<ShiftProvider>();
    if (staffProvider.branch == null) {
      await staffProvider.loadBranch();
    }
    final branch = staffProvider.branch;
    if (branch != null) {
      await shiftProvider.refreshValidation(branch);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffProvider = context.watch<StaffProvider>();
    final shiftProvider = context.watch<ShiftProvider>();
    final branch = staffProvider.branch;
    final isClockedIn = shiftProvider.isClockedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        leading: const BackButton(),
        actions: [
          IconButton(
            tooltip: 'Refresh Location',
            icon: shiftProvider.isValidating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: shiftProvider.isValidating ? null : _refreshLocation,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StaffProfileScreen()),
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.goldPale,
                child: Text(
                  Formatters.initials(staffProvider.staff?.name),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: isClockedIn ? AppColors.successBg : AppColors.surfaceMuted,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isClockedIn ? Icons.check_circle : Icons.schedule,
                        color: isClockedIn ? AppColors.success : AppColors.textSecondary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isClockedIn
                          ? 'Clocked in at ${Formatters.time(shiftProvider.activeShift!.checkInTime)}'
                          : 'Not clocked in',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isClockedIn
                          ? '${Formatters.shortDuration(shiftProvider.liveDuration)} on shift'
                          : 'Clock in when you arrive on-site',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const Divider(height: 36),
                    Row(
                      children: [
                        Expanded(
                          child: _labelValue('Date', Formatters.date(DateTime.now())),
                        ),
                        Expanded(
                          child: _labelValue('Branch', branch?.name ?? '—'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Location & Network Validation',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Row(
              children: [
                StatusChip(
                  label: 'GPS Verified',
                  icon: Icons.location_on_outlined,
                  background: (shiftProvider.validation?.withinGeofence ?? false)
                      ? AppColors.successBg
                      : AppColors.dangerBg,
                  foreground: (shiftProvider.validation?.withinGeofence ?? false)
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LiveRangeIndicator(
              validation: shiftProvider.validation,
              branch: branch,
              isValidating: shiftProvider.isValidating,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _resolveGuardMessage(
                        shiftProvider,
                        branch,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(
                    color: shiftProvider.canToggleAttendance
                        ? AppColors.primaryBlack
                        : AppColors.border,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: shiftProvider.canToggleAttendance && !shiftProvider.isSubmitting
                    ? () async {
                        final staff = staffProvider.staff!;
                        final branch = staffProvider.branch!;
                        if (isClockedIn) {
                          await shiftProvider.clockOut();
                        } else {
                          await shiftProvider.clockIn(staffId: staff.id, branch: branch);
                        }
                      }
                    : null,
                child: shiftProvider.isSubmitting
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isClockedIn ? 'Clock Out' : 'Clock In'),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Text('Staff ID: ${staffProvider.staff?.staffId ?? '—'}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('Biometric & GPS encryption active',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }

  /// Produces the correct guard copy:
  /// • All checks pass → success message
  /// • Outside geofence → names the branch and shows the required radius
  /// • API error / null → fallback from provider
  String _resolveGuardMessage(ShiftProvider shiftProvider, branch) {
    if (shiftProvider.error != null) return shiftProvider.error!;
    final v = shiftProvider.validation;
    if (v == null) return 'Verifying location…';
    if (v.isEligible) {
      return 'You are within the branch geofence. You may clock in.';
    }
    if (!v.withinGeofence && branch != null) {
      final radius = branch.geofenceRadiusMeters.toInt();
      return 'You must be within ${radius}m of ${branch.name} to clock in.';
    }
    return 'You must be within the branch geofence to clock in or out.';
  }
}

// ── Live Range Indicator ─────────────────────────────────────────────────────

/// Shows a colour-coded distance pill: 🟢 Inside Range or 🔴 Outside Range
/// with the exact metres reading and the allowed radius from the database.
class _LiveRangeIndicator extends StatelessWidget {
  final dynamic validation; // GeoValidationResult?
  final dynamic branch; // Branch?
  final bool isValidating;

  const _LiveRangeIndicator({
    required this.validation,
    required this.branch,
    required this.isValidating,
  });

  @override
  Widget build(BuildContext context) {
    if (isValidating || (validation == null && branch != null)) {
      return _buildShell(
        isInside: null,
        distanceText: 'Checking…',
        radiusText: branch != null ? '${branch.geofenceRadiusMeters.toInt()}m' : '—',
      );
    }

    if (validation == null || branch == null) {
      return const SizedBox.shrink();
    }

    final isInside = validation.withinGeofence as bool;
    final distanceM = (validation.distanceMeters as double).round();
    final radiusM = (branch.geofenceRadiusMeters as double).toInt();

    return _buildShell(
      isInside: isInside,
      distanceText: '${distanceM}m',
      radiusText: '${radiusM}m',
    );
  }

  Widget _buildShell({
    required bool? isInside,
    required String distanceText,
    required String radiusText,
  }) {
    final Color dotColor = isInside == null
        ? AppColors.textSecondary
        : isInside
            ? AppColors.success
            : AppColors.danger;
    final Color bgColor = isInside == null
        ? AppColors.surfaceMuted
        : isInside
            ? AppColors.successBg
            : AppColors.dangerBg;
    final String statusLabel = isInside == null
        ? 'Checking location'
        : isInside
            ? 'Inside Range'
            : 'Outside Range';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dotColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Colour dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Status label
          Expanded(
            child: Text(
              statusLabel,
              style: TextStyle(
                color: dotColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          // Distance / radius pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Distance: $distanceText / $radiusText',
              style: TextStyle(
                color: dotColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
