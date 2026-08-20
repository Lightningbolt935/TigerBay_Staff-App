import 'dart:async';
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
  Timer? _ticker;
  Duration _liveDuration = Duration.zero;

  ShiftLog? get activeShift => _activeShift;
  GeoValidationResult? get validation => _validation;
  bool get isValidating => _isValidating;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  Duration get liveDuration => _liveDuration;
  bool get isClockedIn => _activeShift != null && _activeShift!.isActive;

  /// Enables the Clock In / Clock Out button only when GPS geofence passes.
  bool get canToggleAttendance => _validation?.isEligible ?? false;

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

    // 2. Fallback to API Service
    _activeShift = await _api.getActiveShift(staffId);
    _restartTickerIfNeeded();
    notifyListeners();
  }

  Future<void> refreshValidation(Branch branch) async {
    _isValidating = true;
    _error = null;
    notifyListeners();
    try {
      debugPrint('📍 [ShiftProvider] Refreshing location validation for branch: ${branch.name} (lat: ${branch.latitude}, lng: ${branch.longitude}, radius: ${branch.geofenceRadiusMeters}m)');
      final granted = await _geofence.ensurePermissions();
      if (!granted) {
        _error = 'Location permission is required for attendance.';
        debugPrint('❌ [ShiftProvider] Location permission not granted.');
        return;
      }
      _validation = await _geofence.validate(branch);
      _error = null;
      debugPrint('✅ [ShiftProvider] Validation result: inside=${_validation?.withinGeofence}, distance=${_validation?.distanceMeters.toStringAsFixed(1)}m');
    } catch (e) {
      _error = 'Unable to verify location ($e). Try again.';
      debugPrint('❌ [ShiftProvider] refreshValidation error: $e');
    } finally {
      _isValidating = false;
      notifyListeners();
    }
  }

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
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
