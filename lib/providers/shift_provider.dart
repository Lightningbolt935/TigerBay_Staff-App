import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/shift_log.dart';
import '../models/branch.dart';
import '../services/api_service.dart';
import '../services/geofence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Drives the Attendance screen: geofence/Wi-Fi validation, check-in,
/// check-out, and the live shift-duration ticker.
class ShiftProvider extends ChangeNotifier {
  final ApiService _api;
  final GeofenceService _geofence;

  ShiftProvider({ApiService? api, GeofenceService? geofence})
      : _api = api ?? ApiService(),
        _geofence = geofence ?? GeofenceService();

  ShiftLog? _activeShift;
  GeoValidationResult? _validation;
  bool _isValidating = false;
  bool _isSubmitting = false;
  String? _error;
  GeoPermissionState _permissionState = GeoPermissionState.unknown;
  Timer? _ticker;
  Duration _liveDuration = Duration.zero;

  List<ShiftLog> _recentShifts = [];
  bool _isLoadingHistory = false;
  Duration _todayTotal = Duration.zero;
  Duration _weekTotal = Duration.zero;

  ShiftLog? get activeShift => _activeShift;
  GeoValidationResult? get validation => _validation;
  bool get isValidating => _isValidating;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;

  /// Latest known OS-level location access state for the Attendance UI.
  GeoPermissionState get permissionState => _permissionState;
  Duration get liveDuration => _liveDuration;
  bool get isClockedIn => _activeShift != null && _activeShift!.isActive;

  /// Most recent shifts (newest first), including the active one.
  List<ShiftLog> get recentShifts => _recentShifts;
  bool get isLoadingHistory => _isLoadingHistory;

  /// Total time worked today (clamped to midnight → now).
  Duration get todayTotal => _todayTotal;

  /// Total time worked over the trailing 7 days.
  Duration get weekTotal => _weekTotal;

  /// Enables the Clock In button only when GPS geofence passes (strict
  /// branch radius from the `branches` table).
  bool get canToggleAttendance => _validation?.isEligible ?? false;

  /// Widened GPS tolerance used ONLY when clocking out.
  ///
  /// Indoor GPS drift regularly exceeds the strict branch radius, which used
  /// to lock staff out of ending their shift. Fraud is still prevented: the
  /// device must remain within this tolerance of the venue, so staff cannot
  /// clock out once they have actually left site — keeping worked-hours
  /// accurate.
  static const double clockOutToleranceMeters = 150.0;

  /// Effective clock-out radius = branch geofence radius widened to at least
  /// [clockOutToleranceMeters]. Set during [refreshValidation]; null until
  /// the first validation succeeds.
  double? _clockOutRadius;

  double get clockOutRadius => _clockOutRadius ?? clockOutToleranceMeters;

  /// Enables the Clock Out button when the device is within the widened
  /// clock-out radius (branch radius, but never stricter than
  /// [clockOutToleranceMeters]).
  bool get canClockOut {
    final v = _validation;
    final radius = _clockOutRadius;
    if (v == null || radius == null) return false;
    return v.distanceMeters <= radius;
  }

  Future<void> loadActiveShift(String staffId) async {
    debugPrint('🔎 [ShiftProvider] Loading active shift for staff: $staffId');
    try {
      // 1. Try querying Supabase staff_shift_logs
      final client = Supabase.instance.client;
      final rows = await client
          .from('staff_shift_logs')
          .select()
          .eq('staff_id', staffId)
          .eq('status', 'ACTIVE')
          .order('check_in_time', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        _activeShift = ShiftLog.fromJson(Map<String, dynamic>.from(rows.first));
        debugPrint('✅ [ShiftProvider] Found active shift from DB: ${_activeShift?.id} clocked in at ${_activeShift?.checkInTime}');
        _restartTickerIfNeeded();
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('⚠️ [ShiftProvider] loadActiveShift Supabase query: $e');
    }

    // 2. Fallback to API Service — must never throw, otherwise the
    // attendance screen's validation pipeline is skipped entirely.
    try {
      _activeShift = await _api.getActiveShift(staffId);
    } catch (e) {
      debugPrint('⚠️ [ShiftProvider] getActiveShift fallback failed (ignoring): $e');
    }
    _restartTickerIfNeeded();
    notifyListeners();
  }

  /// Loads the most recent shift logs for [staffId] and recomputes the
  /// today/week worked-hours totals shown on the Attendance screen.
  Future<void> loadRecentShifts(String staffId) async {
    _isLoadingHistory = true;
    notifyListeners();
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('staff_shift_logs')
          .select()
          .eq('staff_id', staffId)
          .order('check_in_time', ascending: false)
          .limit(14);
      _recentShifts = rows
          .map((r) => ShiftLog.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [ShiftProvider] loadRecentShifts: $e');
    } finally {
      _isLoadingHistory = false;
      _computeTotals();
      notifyListeners();
    }
  }

  /// Sums overlapping durations of all known shifts against a window.
  void _computeTotals() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final weekStart = startOfToday.subtract(const Duration(days: 6));

    // Merge active + history, de-duplicating by id.
    final byId = <String, ShiftLog>{};
    if (_activeShift != null) byId[_activeShift!.id] = _activeShift!;
    for (final s in _recentShifts) {
      byId.putIfAbsent(s.id, () => s);
    }

    Duration overlap(Map<String, ShiftLog> shifts, DateTime windowStart) {
      var total = Duration.zero;
      for (final s in shifts.values) {
        final end = s.checkOutTime ?? now;
        final from = s.checkInTime.isAfter(windowStart) ? s.checkInTime : windowStart;
        final to = end.isBefore(now) ? end : now;
        if (to.isAfter(from)) total += to.difference(from);
      }
      return total;
    }

    _todayTotal = overlap(byId, startOfToday);
    _weekTotal = overlap(byId, weekStart);
  }

  Future<void> refreshValidation(Branch branch) async {
    _isValidating = true;
    _error = null;
    notifyListeners();
    try {
      debugPrint('📍 [ShiftProvider] Refreshing location validation for branch: ${branch.name} (lat: ${branch.latitude}, lng: ${branch.longitude}, radius: ${branch.geofenceRadiusMeters}m)');

      // Ask the OS for location access (native dialog pops when needed).
      _permissionState = await _geofence.ensurePermissions();

      switch (_permissionState) {
        case GeoPermissionState.serviceDisabled:
          _error = 'GPS is turned off. Turn on Location, then tap ↻ to retry.';
          debugPrint('❌ [ShiftProvider] Device location services are OFF.');
          return;
        case GeoPermissionState.denied:
          _error = 'Location permission is required for attendance.';
          debugPrint('❌ [ShiftProvider] Location permission denied by user.');
          return;
        case GeoPermissionState.permanentlyDenied:
          _error = 'Location permission is blocked. Enable it in App Settings.';
          debugPrint('❌ [ShiftProvider] Location permission permanently denied.');
          return;
        case GeoPermissionState.unknown:
        case GeoPermissionState.granted:
          break;
      }

      _validation = await _geofence.validate(branch);
      _clockOutRadius = math.max(
        branch.geofenceRadiusMeters,
        clockOutToleranceMeters,
      );
      _error = null;
      debugPrint('✅ [ShiftProvider] Validation result: inside=${_validation?.withinGeofence}, distance=${_validation?.distanceMeters.toStringAsFixed(1)}m, clockOutRadius=$_clockOutRadius');
    } catch (e) {
      _error = 'Unable to verify location ($e). Try again.';
      debugPrint('❌ [ShiftProvider] refreshValidation error: $e');
    } finally {
      _isValidating = false;
      notifyListeners();
    }
  }

  /// Re-asks the OS for location access from an explicit user gesture
  /// (e.g. the "Allow Location" button). Returns true when granted.
  Future<bool> requestLocationAccess() async {
    _permissionState = await _geofence.ensurePermissions();
    notifyListeners();
    return _permissionState == GeoPermissionState.granted;
  }

  /// Opens the system Location settings (to flip the GPS toggle ON).
  Future<void> openDeviceLocationSettings() =>
      _geofence.openDeviceLocationSettings();

  /// Opens this app's system Settings page (to grant a blocked permission).
  Future<void> openAppSettings() => _geofence.openAppSettings();

  Future<void> clockIn({
    required String staffId,
    required Branch branch,
  }) async {
    if (!canToggleAttendance) {
      debugPrint('⚠️ [ShiftProvider] Cannot clock in: not within geofence range.');
      return;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('🚀 [ShiftProvider] Clocking in staff: $staffId at ${branch.name}');
      final position = await _geofence.getCurrentPosition();
      final now = DateTime.now();

      try {
        final client = Supabase.instance.client;
        final res = await client.from('staff_shift_logs').insert({
          'staff_id': staffId,
          'branch_id': branch.id,
          'check_in_time': now.toIso8601String(),
          'check_in_lat': position.latitude,
          'check_in_lng': position.longitude,
          'check_in_wifi_bssid': 'N/A',
          'status': 'ACTIVE',
        }).select().single();

        _activeShift = ShiftLog.fromJson(Map<String, dynamic>.from(res));
        debugPrint('✅ [ShiftProvider] Clock-in recorded in Supabase: ${_activeShift?.id}');
      } catch (dbErr) {
        debugPrint('⚠️ [ShiftProvider] DB insert notice ($dbErr), creating local active shift session.');
        _activeShift = ShiftLog(
          id: 'shift-${DateTime.now().millisecondsSinceEpoch}',
          staffId: staffId,
          branchId: branch.id,
          checkInTime: now,
          checkInLat: position.latitude,
          checkInLng: position.longitude,
          checkInWifiBssid: 'N/A',
          status: AppConstants.shiftActive,
        );
      }

      _restartTickerIfNeeded();
      _error = null;
      unawaited(loadRecentShifts(staffId));
    } catch (e) {
      debugPrint('❌ [ShiftProvider] Clock-in failed: $e');
      _error = 'Check-in failed: $e';
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> clockOut() async {
    if (_activeShift == null) return;
    if (!canClockOut) {
      final radius = clockOutRadius.toStringAsFixed(0);
      debugPrint('⚠️ [ShiftProvider] Cannot clock out: not within ${radius}m range.');
      _error = 'You must be within ${radius}m of the branch to clock out.';
      notifyListeners();
      return;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('🚀 [ShiftProvider] Clocking out shift: ${_activeShift?.id}');
      final now = DateTime.now();
      final durationHours = now.difference(_activeShift!.checkInTime).inSeconds / 3600.0;

      try {
        final client = Supabase.instance.client;
        await client.from('staff_shift_logs').update({
          'check_out_time': now.toIso8601String(),
          'total_shift_hours': durationHours,
          'status': 'COMPLETED',
        }).eq('id', _activeShift!.id);
        debugPrint('✅ [ShiftProvider] Clock-out updated in Supabase.');
      } catch (dbErr) {
        debugPrint('⚠️ [ShiftProvider] DB update notice: $dbErr');
      }

      _activeShift = _activeShift!.copyWith(
        checkOutTime: now,
        totalShiftHours: durationHours,
        status: AppConstants.shiftCompleted,
      );
      _ticker?.cancel();
      _error = null;
      unawaited(loadRecentShifts(_activeShift!.staffId));
    } catch (e) {
      debugPrint('❌ [ShiftProvider] Clock-out failed: $e');
      _error = 'Check-out failed: $e';
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void _restartTickerIfNeeded() {
    _ticker?.cancel();
    if (_activeShift == null || !_activeShift!.isActive) return;
    _liveDuration = _activeShift!.currentDuration();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _liveDuration = _activeShift!.currentDuration();
      _computeTotals();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
