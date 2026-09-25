import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/shift_log.dart';
import '../models/branch.dart';
import '../services/api_service.dart';
import '../services/geofence_service.dart';

/// Drives the Attendance screen: geofence validation, check-in,
/// check-out, and shift duration using the `timesheets` table.
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

  GeoPermissionState get permissionState => _permissionState;
  Duration get liveDuration => _liveDuration;
  bool get isClockedIn => _activeShift != null && _activeShift!.isActive;

  List<ShiftLog> get recentShifts => _recentShifts;
  bool get isLoadingHistory => _isLoadingHistory;

  Duration get todayTotal => _todayTotal;
  Duration get weekTotal => _weekTotal;

  bool get canToggleAttendance => _validation?.isEligible ?? false;

  static const double clockOutToleranceMeters = 150.0;
  double? _clockOutRadius;
  double get clockOutRadius => _clockOutRadius ?? clockOutToleranceMeters;

  bool get canClockOut {
    final v = _validation;
    final radius = _clockOutRadius;
    if (v == null || radius == null) return false;
    return v.distanceMeters <= radius;
  }

  /// Converts a row from the `timesheets` table into a [ShiftLog] instance.
  ShiftLog _shiftLogFromTimesheet(Map<String, dynamic> row) {
    final clockInStr = row['clock_in']?.toString();
    final clockOutStr = row['clock_out']?.toString();
    final clockIn = clockInStr != null
        ? DateTime.tryParse(clockInStr)?.toLocal() ?? DateTime.now()
        : DateTime.now();
    final clockOut =
        clockOutStr != null ? DateTime.tryParse(clockOutStr)?.toLocal() : null;

    final normalized = {
      'id': row['id']?.toString() ?? '',
      'staff_id': row['staff_id']?.toString() ?? '',
      'branch_id': row['venue_id']?.toString() ?? '',
      'check_in_time': clockIn.toIso8601String(),
      if (clockOut != null) 'check_out_time': clockOut.toIso8601String(),
      'check_in_lat': (row['device_latitude'] as num?)?.toDouble() ?? 0.0,
      'check_in_lng': (row['device_longitude'] as num?)?.toDouble() ?? 0.0,
      'check_in_wifi_bssid': 'N/A',
      'status': clockOut == null
          ? AppConstants.shiftActive
          : AppConstants.shiftCompleted,
      ...row,
    };

    try {
      return ShiftLog.fromJson(normalized);
    } catch (_) {
      return ShiftLog(
        id: row['id']?.toString() ?? '',
        staffId: row['staff_id']?.toString() ?? '',
        branchId: row['venue_id']?.toString() ?? '',
        checkInTime: clockIn,
        checkOutTime: clockOut,
        checkInLat: (row['device_latitude'] as num?)?.toDouble() ?? 0.0,
        checkInLng: (row['device_longitude'] as num?)?.toDouble() ?? 0.0,
        checkInWifiBssid: 'N/A',
        status: clockOut == null
            ? AppConstants.shiftActive
            : AppConstants.shiftCompleted,
      );
    }
  }

  /// Loads the current active shift (where clock_out IS NULL) from `timesheets`.
  Future<void> loadActiveShift(String staffId) async {
    debugPrint('🔎 [ShiftProvider] Loading active shift for staff: $staffId');
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('timesheets')
          .select()
          .eq('staff_id', staffId)
          .order('clock_in', ascending: false)
          .limit(1);

      if (rows.isNotEmpty && rows.first['clock_out'] == null) {
        _activeShift =
            _shiftLogFromTimesheet(Map<String, dynamic>.from(rows.first));
        debugPrint(
            '✅ [ShiftProvider] Found active timesheet: ${_activeShift?.id} clocked in at${_activeShift?.checkInTime}');
        _restartTickerIfNeeded();
        notifyListeners();
        return;
      } else {
        _activeShift = null;
      }
    } catch (e) {
      debugPrint('⚠️ [ShiftProvider] loadActiveShift error: $e');
    }

    _restartTickerIfNeeded();
    notifyListeners();
  }

  /// Loads recent attendance records from `timesheets`.
  Future<void> loadRecentShifts(String staffId) async {
    _isLoadingHistory = true;
    notifyListeners();
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('timesheets')
          .select()
          .eq('staff_id', staffId)
          .order('clock_in', ascending: false)
          .limit(14);

      _recentShifts = rows
          .map((r) => _shiftLogFromTimesheet(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [ShiftProvider] loadRecentShifts error: $e');
    } finally {
      _isLoadingHistory = false;
      _computeTotals();
      notifyListeners();
    }
  }

  void _computeTotals() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final weekStart = startOfToday.subtract(const Duration(days: 6));

    final byId = <String, ShiftLog>{};
    if (_activeShift != null) byId[_activeShift!.id] = _activeShift!;
    for (final s in _recentShifts) {
      byId.putIfAbsent(s.id, () => s);
    }

    Duration overlap(Map<String, ShiftLog> shifts, DateTime windowStart) {
      var total = Duration.zero;
      for (final s in shifts.values) {
        final end = s.checkOutTime ?? now;
        final from =
            s.checkInTime.isAfter(windowStart) ? s.checkInTime : windowStart;
        final to = end.isBefore(now) ? end : now;
        if (to.isAfter(from)) total += to.difference(from);
      }
      return total;
    }

    _todayTotal = overlap(byId, startOfToday);
    _weekTotal = overlap(byId, weekStart);
  }

  /// Compares the live device position with the database branch coordinates.
  Future<void> refreshValidation(Branch branch) async {
    _isValidating = true;
    _error = null;
    notifyListeners();
    try {
      debugPrint(
          '📍 [ShiftProvider] Refreshing location validation for branch: ${branch.name} (lat:${branch.latitude}, lng: ${branch.longitude}, radius:${branch.geofenceRadiusMeters}m)');

      _permissionState = await _geofence.ensurePermissions();

      switch (_permissionState) {
        case GeoPermissionState.serviceDisabled:
          _error = 'GPS is turned off. Turn on Location, then tap ↻ to retry.';
          return;
        case GeoPermissionState.denied:
          _error = 'Location permission is required for attendance.';
          return;
        case GeoPermissionState.permanentlyDenied:
          _error = 'Location permission is blocked. Enable it in App Settings.';
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
      debugPrint(
          '✅ [ShiftProvider] Validation result: inside=${_validation?.withinGeofence}, distance=${_validation?.distanceMeters.toStringAsFixed(1)}m, allowed=${branch.geofenceRadiusMeters}m');
    } catch (e) {
      _error = 'Unable to verify location ($e). Try again.';
      debugPrint('❌ [ShiftProvider] refreshValidation error: $e');
    } finally {
      _isValidating = false;
      notifyListeners();
    }
  }

  Future<bool> requestLocationAccess() async {
    _permissionState = await _geofence.ensurePermissions();
    notifyListeners();
    return _permissionState == GeoPermissionState.granted;
  }

  Future<void> openDeviceLocationSettings() =>
      _geofence.openDeviceLocationSettings();

  Future<void> openAppSettings() => _geofence.openAppSettings();

  /// Inserts a new record into `timesheets`.
  Future<void> clockIn({
    required String staffId,
    required Branch branch,
  }) async {
    if (!canToggleAttendance) {
      debugPrint(
          '⚠️ [ShiftProvider] Cannot clock in: not within geofence range.');
      return;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint(
          '🚀 [ShiftProvider] Clocking in staff: $staffId at${branch.name}');
      final position = await _geofence.getCurrentPosition();
      final now = DateTime.now();

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        branch.latitude,
        branch.longitude,
      );

      final venueId = branch.nightCollinsBranchId.isNotEmpty
          ? branch.nightCollinsBranchId
          : branch.id;

      final client = Supabase.instance.client;
      final payload = {
        'staff_id': staffId,
        'venue_id': venueId,
        'clock_in': now.toIso8601String(),
        'device_latitude': position.latitude,
        'device_longitude': position.longitude,
        'distance_from_branch_meters':
            double.parse(distance.toStringAsFixed(2)),
        'is_within_geofence': distance <= branch.geofenceRadiusMeters,
      };

      final res =
          await client.from('timesheets').insert(payload).select().single();

      _activeShift = _shiftLogFromTimesheet(Map<String, dynamic>.from(res));
      debugPrint(
          '✅ [ShiftProvider] Clock-in recorded in timesheets table: ${_activeShift?.id}');

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

  /// Updates the active row in `timesheets` with clock_out timestamp.
  Future<void> clockOut() async {
    if (_activeShift == null) return;
    if (!canClockOut) {
      final radius = clockOutRadius.toStringAsFixed(0);
      debugPrint(
          '⚠️ [ShiftProvider] Cannot clock out: not within ${radius}m range.');
      _error = 'You must be within ${radius}m of the branch to clock out.';
      notifyListeners();
      return;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint(
          '🚀 [ShiftProvider] Clocking out timesheet: ${_activeShift?.id}');
      final now = DateTime.now();

      final client = Supabase.instance.client;
      await client.from('timesheets').update({
        'clock_out': now.toIso8601String(),
      }).eq('id', _activeShift!.id);

      debugPrint('✅ [ShiftProvider] Clock-out updated in timesheets.');

      _activeShift = _activeShift!.copyWith(
        checkOutTime: now,
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
