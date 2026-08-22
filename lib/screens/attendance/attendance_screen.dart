import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/shift_log.dart';
import '../../providers/shift_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/geofence_service.dart';
import '../../widgets/status_chip.dart';
import '../profile/staff_profile_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with WidgetsBindingObserver {
  /// Set when the app goes to the background so we only auto-revalidate on
  /// a genuine return from Settings / quick-settings — not on first resume.
  bool _leftAppForSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user comes back from Location/App settings (e.g. after
    // enabling GPS or granting the permission), re-run validation so the
    // screen recovers without them having to tap anything.
    if (state == AppLifecycleState.paused) {
      _leftAppForSettings = true;
    } else if (state == AppLifecycleState.resumed && _leftAppForSettings) {
      _leftAppForSettings = false;
      _refreshLocation();
    }
  }

  Future<void> _init() async {
    final staffProvider = context.read<StaffProvider>();
    final shiftProvider = context.read<ShiftProvider>();
    final authStaff = context.read<AuthProvider>().staff;

    // Load branch first — guaranteed non-null (falls back internally).
    if (staffProvider.branch == null) {
      await staffProvider.loadBranch();
    }
    final branch = staffProvider.branch;
    final staff = staffProvider.staff ?? authStaff;

    // Run the shift lookup and location validation CONCURRENTLY: the GPS
    // permission dialog + geofence check must never wait on (or be skipped
    // by) a slow/hung shift query.
    await Future.wait([
      if (staff != null) shiftProvider.loadActiveShift(staff.id),
      if (branch != null) shiftProvider.refreshValidation(branch),
      if (staff != null) shiftProvider.loadRecentShifts(staff.id),
    ]);
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
    // Clock In requires the strict branch geofence; Clock Out uses a widened
    // 150 m tolerance so GPS drift never locks a shift open.
    final canAct =
        isClockedIn ? shiftProvider.canClockOut : shiftProvider.canToggleAttendance;

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
            // ── Worked-hours summary ────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _HoursCard(
                    label: 'Today',
                    duration: shiftProvider.todayTotal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HoursCard(
                    label: 'Last 7 days',
                    duration: shiftProvider.weekTotal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Text('Recent Shifts',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            _buildShiftHistory(shiftProvider),
            const SizedBox(height: 28),
            const Text('Location & Network Validation',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
                if (isClockedIn)
                  StatusChip(
                    label: shiftProvider.canClockOut
                        ? 'Clock Out Available'
                        : 'Clock Out: Out of Range',
                    icon: Icons.logout_rounded,
                    background: shiftProvider.canClockOut
                        ? AppColors.successBg
                        : AppColors.dangerBg,
                    foreground: shiftProvider.canClockOut
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
              error: shiftProvider.error,
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
            ..._buildPermissionCta(shiftProvider),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(
                    color: canAct ? AppColors.primaryBlack : AppColors.border,
                  ),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: canAct && !shiftProvider.isSubmitting
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

  Widget _buildShiftHistory(ShiftProvider shiftProvider) {
    if (shiftProvider.isLoadingHistory && shiftProvider.recentShifts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
          ),
        ),
      );
    }

    final shifts = shiftProvider.recentShifts.take(7).toList();
    if (shifts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'No recorded shifts yet. Clock in to start tracking your hours.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < shifts.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _ShiftRow(shift: shifts[i]),
          ],
        ],
      ),
    );
  }

  /// Contextual call-to-action shown whenever location access is not ready:
  /// • GPS toggle OFF   → "Turn On Location" (opens Location settings)
  /// • Permission denied → "Allow Location" (re-triggers the native dialog)
  /// • Blocked ("Don't ask again") → "Open App Settings"
  /// When everything is fine this emits nothing.
  List<Widget> _buildPermissionCta(ShiftProvider shiftProvider) {
    // Fully granted (or still running the initial check that will itself
    // pop the native dialog) — no manual action needed from the user.
    if (shiftProvider.permissionState == GeoPermissionState.granted ||
        shiftProvider.isValidating) {
      return const [];
    }

    final List<Widget> widgets = [];

    switch (shiftProvider.permissionState) {
      case GeoPermissionState.serviceDisabled:
        widgets.add(SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.location_on_outlined),
            label: const Text('Turn On Location'),
            onPressed: shiftProvider.isValidating
                ? null
                : () async {
                    await context.read<ShiftProvider>().openDeviceLocationSettings();
                  },
          ),
        ));
        break;
      case GeoPermissionState.denied:
      case GeoPermissionState.unknown:
        widgets.add(SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('Allow Location Access'),
            onPressed: shiftProvider.isValidating
                ? null
                : () async {
                    final provider = context.read<ShiftProvider>();
                    final branch = context.read<StaffProvider>().branch;
                    final granted = await provider.requestLocationAccess();
                    if (granted && branch != null) {
                      await provider.refreshValidation(branch);
                    }
                  },
          ),
        ));
        break;
      case GeoPermissionState.permanentlyDenied:
        widgets.add(SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Open App Settings'),
            onPressed: shiftProvider.isValidating
                ? null
                : () async {
                    await context.read<ShiftProvider>().openAppSettings();
                  },
          ),
        ));
        break;
      case GeoPermissionState.granted:
        break;
    }

    if (widgets.isNotEmpty) {
      widgets.add(const SizedBox(height: 4));
      widgets.add(const Center(
        child: Text(
          'Attendance requires GPS verification',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ));
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }

  /// Produces the correct guard copy:
  /// • All checks pass → success message for the current action
  /// • Clocked in → widened 150 m clock-out range messaging
  /// • Outside geofence → names the branch and shows the required radius
  /// • Error / null → show error or fallback
  String _resolveGuardMessage(ShiftProvider shiftProvider, branch) {
    if (shiftProvider.error != null) return shiftProvider.error!;
    final v = shiftProvider.validation;
    if (v == null) {
      return shiftProvider.isValidating
          ? 'Verifying location…'
          : 'Could not read GPS. Tap ↻ to retry.';
    }

    if (shiftProvider.isClockedIn) {
      final clockOutRadius = shiftProvider.clockOutRadius;
      if (v.distanceMeters <= clockOutRadius) {
        return v.withinGeofence
            ? 'You are within the branch geofence. You may clock out.'
            : 'Slightly off-site but within the ${clockOutRadius.round()}m '
                'clock-out range. You may still clock out.';
      }
      return 'You must be within ${clockOutRadius.round()}m of '
          '${branch?.name ?? 'the branch'} to clock out.';
    }

    if (v.isEligible) {
      return 'You are within the branch geofence. You may clock in.';
    }
    if (!v.withinGeofence && branch != null) {
      final radius = branch.geofenceRadiusMeters.toInt();
      return 'You must be within ${radius}m of ${branch.name} to clock in.';
    }
    return 'You must be within the branch geofence to clock in.';
  }
}

// ── Live Range Indicator ─────────────────────────────────────────────────────

/// Shows a colour-coded distance pill: 🟢 Inside Range or 🔴 Outside Range
/// with the exact metres reading and the allowed radius from the database.
class _LiveRangeIndicator extends StatelessWidget {
  final dynamic validation; // GeoValidationResult?
  final dynamic branch; // Branch?
  final bool isValidating;
  final String? error;

  const _LiveRangeIndicator({
    required this.validation,
    required this.branch,
    required this.isValidating,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    // Still loading
    if (isValidating) {
      return _buildShell(
        isInside: null,
        distanceText: 'Checking…',
        radiusText: branch != null ? '${branch.geofenceRadiusMeters.toInt()}m' : '—',
      );
    }

    // Error state — GPS failed or permission denied
    if (error != null) {
      return _buildShell(
        isInside: false,
        distanceText: 'Error',
        radiusText: branch != null ? '${branch.geofenceRadiusMeters.toInt()}m' : '—',
        overrideLabel: 'Location Error — Tap ↻',
      );
    }

    // No branch loaded yet
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
    String? overrideLabel,
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
    final String statusLabel = overrideLabel ??
        (isInside == null
            ? 'Checking location'
            : isInside
                ? 'Inside Range'
                : 'Outside Range');

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

// ── Worked-hours summary card ────────────────────────────────────────────────

class _HoursCard extends StatelessWidget {
  final String label;
  final Duration duration;

  const _HoursCard({required this.label, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            Formatters.shortDuration(duration),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
        ],
      ),
    );
  }
}

// ── Recent shift row ─────────────────────────────────────────────────────────

class _ShiftRow extends StatelessWidget {
  final ShiftLog shift;

  const _ShiftRow({required this.shift});

  @override
  Widget build(BuildContext context) {
    final isActive = shift.isActive;
    final duration = shift.currentDuration();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isActive ? AppColors.successBg : AppColors.goldPale,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.login_rounded : Icons.history_rounded,
              size: 18,
              color: isActive ? AppColors.success : AppColors.gold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Formatters.dayLabel(shift.checkInTime),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${Formatters.time(shift.checkInTime)} → '
                  '${shift.checkOutTime != null ? Formatters.time(shift.checkOutTime!) : '—'}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${Formatters.shortDuration(duration)} · live',
                style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 11),
              ),
            )
          else
            Text(
              Formatters.shortDuration(duration),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
        ],
      ),
    );
  }
}
