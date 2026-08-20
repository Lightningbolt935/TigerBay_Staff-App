import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/branch.dart';

/// Result of a check-in/out eligibility check.
class GeoValidationResult {
  final bool withinGeofence;
  final double distanceMeters;

  const GeoValidationResult({
    required this.withinGeofence,
    required this.distanceMeters,
  });

  /// Now ONLY requires GPS validation to be true
  bool get isEligible => withinGeofence;
}

/// Wraps `geolocator` to validate that a device is
/// physically inside a branch's geofence.
class GeofenceService {
  /// Requests the runtime permissions needed for location.
  /// Returns true only if all required permissions are granted.
  Future<bool> ensurePermissions() async {
    // Check GPS toggle.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('⚠️ [GeofenceService] Location service is disabled on device.');
      await Geolocator.openLocationSettings();
      return false;
    }

    // Check / request runtime permission.
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      debugPrint('⚠️ [GeofenceService] Requesting location permissions...');
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ [GeofenceService] Location permission permanently denied.');
      await Geolocator.openAppSettings();
      return false;
    }

    final granted = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    debugPrint('✅ [GeofenceService] Location permission granted: $granted ($permission)');
    return granted;
  }

  /// Returns the current device position with a 10-second timeout.
  Future<Position> getCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
        forceAndroidLocationManager: true, // Required for Android emulators & devices
      );
      debugPrint('📍 [GeofenceService] GPS Fix: lat=${pos.latitude}, lng=${pos.longitude}, acc=${pos.accuracy}m, isMocked=${pos.isMocked}');
      return pos;
    } catch (e) {
      debugPrint('⚠️ [GeofenceService] getCurrentPosition timed out or failed: $e. Checking lastKnownPosition...');
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        debugPrint('📍 [GeofenceService] Fallback to Last Known GPS Fix: lat=${last.latitude}, lng=${last.longitude}');
        return last;
      }
      rethrow;
    }
  }

  /// Core validation used to gate the Clock In / Clock Out buttons.
  Future<GeoValidationResult> validate(Branch branch) async {
    final position = await getCurrentPosition();
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      branch.latitude,
      branch.longitude,
    );

    final within = distance <= branch.geofenceRadiusMeters;
    debugPrint(
      '🗺️ [GeofenceService] Geofence check: current=(${position.latitude}, ${position.longitude}) '
      'target ${branch.name}=(${branch.latitude}, ${branch.longitude}) '
      'distance=${distance.toStringAsFixed(1)}m, allowed=${branch.geofenceRadiusMeters}m -> within=$within',
    );

    return GeoValidationResult(
      withinGeofence: within,
      distanceMeters: distance,
    );
  }
}
