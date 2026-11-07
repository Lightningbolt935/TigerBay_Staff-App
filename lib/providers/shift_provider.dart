import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/shift_log.dart';
import '../models/branch.dart';
import '../services/geofence_service.dart';

class ShiftProvider extends ChangeNotifier {
  final GeofenceService _geofence;

  ShiftProvider({GeofenceService? geofence})
      : _geofence = geofence ?? GeofenceService();

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

  /// Queries the live `branches` row to guarantee exact coordinates and radius.
  Future<Branch> _fetchLiveBranch(Branch fallback) async {
    try {
      final client = Supabase.instance.client;
      final parsedId = int.tryParse(fallback.id);

      dynamic res;
      if (parsedId != null) {
        res = await client
            .from('branches')
            .select()
            .eq('id', parsedId)
            .maybeSingle();
      } else if (fallback.nightCollinsBranchId.isNotEmpty) {
        res = await client
            .from('branches')
            .select()
            .eq('collins_venue_id', fallback.nightCollinsBranchId)
            .maybeSingle();
      }

      if (res != null) {
        return Branch.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint(
          '⚠️ [ShiftProvider] Could not load live branch coordinates: $e');
    }
    return fallback;
  }

  /// Loads the active shift from `timesheets`.
  Future<void> loadActiveShift(String staffId) async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('timesheets')
          .select()
          .eq('staff_id', staffId)
          .order('clock_in', ascending: false)
          .limit(1);

      if (rows.isNotEmpty && rows.first['clock_out'] == null) {
        final row = Map<String, dynamic>.from(rows.first);
        _activeShift = ShiftLog.fromJson(row);
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
          .map((r) => ShiftLog.fromJson(Map<String, dynamic>.from(r)))
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
        if (s.isAbsent) continue;
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

  /// Validates the device position against live branch coordinates.
  Future<void> refreshValidation(Branch branch) async {
    _isValidating = true;
    _error = null;
    notifyListeners();
    try {
      final liveBranch = await _fetchLiveBranch(branch);

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

      _validation = await _geofence.validate(liveBranch);
      _clockOutRadius = math.max(
        liveBranch.geofenceRadiusMeters,
        clockOutToleranceMeters,
      );
      _error = null;
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

  /// Logs a new check-in to `timesheets`.
  Future<void> clockIn({
    required String staffId,
    required Branch branch,
    String? staffName,
    String? staffCode,
  }) async {
    if (!canToggleAttendance) {
      _error = 'Cannot clock in: outside branch geofence boundary.';
      notifyListeners();
      return;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final liveBranch = await _fetchLiveBranch(branch);
      final position = await _geofence.getCurrentPosition();
      final now = DateTime.now();

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        liveBranch.latitude,
        liveBranch.longitude,
      );

      final isWithin = distance <= liveBranch.geofenceRadiusMeters;
      if (!isWithin) {
        throw Exception(
            'Out of range: ${distance.round()}m from branch (allowed: ${liveBranch.geofenceRadiusMeters.round()}m)');
      }

      final venueId = liveBranch.nightCollinsBranchId.isNotEmpty
          ? liveBranch.nightCollinsBranchId
          : liveBranch.id;

      final metadata = [
        if (staffName != null && staffName.isNotEmpty) 'Name: $staffName',
        if (staffCode != null && staffCode.isNotEmpty) 'Staff ID: $staffCode',
      ].join(' | ');

      final payload = {
        'staff_id': staffId,
        'venue_id': venueId,
        'clock_in': now.toIso8601String(),
        'device_latitude': position.latitude,
        'device_longitude': position.longitude,
        'distance_from_branch_meters':
            double.parse(distance.toStringAsFixed(2)),
        'is_within_geofence': true,
        if (metadata.isNotEmpty) 'notes': metadata,
      };

      final client = Supabase.instance.client;
      final res =
          await client.from('timesheets').insert(payload).select().single();

      _activeShift = ShiftLog.fromJson(Map<String, dynamic>.from(res));
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
      _error = 'You must be within ${radius}m of the branch to clock out.';
      notifyListeners();
      return;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final client = Supabase.instance.client;

      await client.from('timesheets').update({
        'clock_out': now.toIso8601String(),
      }).eq('id', _activeShift!.id);

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
