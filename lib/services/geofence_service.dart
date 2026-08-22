import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../models/branch.dart';

/// High-level outcome of the location pre-flight gate.
enum GeoPermissionState {
  /// No definitive answer yet (never checked this session).
  unknown,

  /// Runtime permission granted AND device GPS toggle is ON.
  granted,

  /// Device-level Location toggle (GPS) is turned OFF.
  serviceDisabled,

  /// OS dialog shown but refused — can be re-asked via a user gesture.
  denied,

  /// "Don't ask again" was selected — only App Settings can fix this.
  permanentlyDenied,
}

/// Result of a check-in/out eligibility check.
class GeoValidationResult {
  final bool withinGeofence;
  final double distanceMeters;

  const GeoValidationResult({
    required this.withinGeofence,
    required this.distanceMeters,
  });

  bool get isEligible => withinGeofence;
}

/// Wraps `geolocator` & `permission_handler` to validate that a device is
/// physically inside a branch's geofence.
class GeofenceService {
  /// Asks the OS for location access exactly like the camera prompt:
  /// the native dialog pops whenever permission is not yet granted.
  ///
  /// Unlike the previous implementation, this NEVER silently bounces the
  /// user to Settings — every outcome is returned as a [GeoPermissionState]
  /// so the UI can show a clear, actionable message instead.
  Future<GeoPermissionState> ensurePermissions() async {
    // 1. Check if GPS / Location toggle is enabled on device.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('⚠️ [GeofenceService] Device GPS/Location toggle is OFF.');
      return GeoPermissionState.serviceDisabled;
    }

    // 2. Read the current runtime permission state.
    var perm = await Geolocator.checkPermission();
    debugPrint('📍 [GeofenceService] Current location permission: $perm');

    if (perm == LocationPermission.deniedForever) {
      debugPrint('❌ [GeofenceService] Location permanently denied.');
      return GeoPermissionState.permanentlyDenied;
    }

    // 3. Trigger the NATIVE OS dialog (same UX as the camera prompt).
    //    `unableToDetermine` happens on first launch on some platforms and
    //    must also trigger an ask.
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.unableToDetermine) {
      debugPrint('⚠️ [GeofenceService] Showing native location permission dialog...');
      perm = await Geolocator.requestPermission();
      debugPrint('📍 [GeofenceService] Post-request permission: $perm');
    }

    switch (perm) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return GeoPermissionState.granted;
      case LocationPermission.deniedForever:
        return GeoPermissionState.permanentlyDenied;
      default:
        return GeoPermissionState.denied;
    }
  }

  /// Opens the system Location settings (GPS toggle screen).
  Future<void> openDeviceLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Opens this app's page in system Settings (grant/deny permissions).
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  /// Returns device position using a 5-tier resilient strategy.
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Device GPS is turned OFF. Please turn on Location in quick settings.');
    }

    // ── Tier 1: Recent Last Known Position ───────────────────────────────────
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final age = DateTime.now().difference(last.timestamp);
        debugPrint('📍 [GeofenceService] Tier 1: Last known fix (${age.inMinutes}m old): ${last.latitude}, ${last.longitude}');
        if (age.inMinutes < 15) {
          return last;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [GeofenceService] Tier 1 note: $e');
    }

    // ── Tier 2: Medium / Fused accuracy (GPS + WiFi + Cell) ───────────────────
    try {
      debugPrint('📍 [GeofenceService] Tier 2: Requesting Fused Medium fix...');
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
      debugPrint('📍 [GeofenceService] Tier 2 fix: lat=${pos.latitude}, lng=${pos.longitude}');
      return pos;
    } catch (e) {
      debugPrint('⚠️ [GeofenceService] Tier 2 note: $e');
    }

    // ── Tier 3: Low accuracy (Network / Cell tower fast fix) ───────────────────
    try {
      debugPrint('📍 [GeofenceService] Tier 3: Requesting Low accuracy fix...');
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );
      debugPrint('📍 [GeofenceService] Tier 3 fix: lat=${pos.latitude}, lng=${pos.longitude}');
      return pos;
    } catch (e) {
      debugPrint('⚠️ [GeofenceService] Tier 3 note: $e');
    }

    // ── Tier 3b: Android platform LocationManager ─────────────────────────────
    // forceAndroidLocationManager bypasses Google Play Services' fused
    // provider entirely — essential on budget handsets / emulators where
    // every FusedLocationProvider call fails instantly.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        debugPrint('📍 [GeofenceService] Tier 3b: Requesting Android LocationManager fix...');
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 15),
          forceAndroidLocationManager: true,
        );
        debugPrint('📍 [GeofenceService] Tier 3b fix: lat=${pos.latitude}, lng=${pos.longitude}');
        return pos;
      } catch (e) {
        debugPrint('⚠️ [GeofenceService] Tier 3b note: $e');
      }
    }

    // ── Tier 4: Position Stream ───────────────────────────────────────────────
    try {
      debugPrint('📍 [GeofenceService] Tier 4: Listening to stream...');
      final completer = Completer<Position>();
      StreamSubscription<Position>? sub;

      sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 0,
        ),
      ).listen(
        (pos) {
          debugPrint('📍 [GeofenceService] Tier 4 fix: lat=${pos.latitude}, lng=${pos.longitude}');
          if (!completer.isCompleted) {
            completer.complete(pos);
            sub?.cancel();
          }
        },
        onError: (e) {
          debugPrint('⚠️ [GeofenceService] Tier 4 stream note: $e');
          if (!completer.isCompleted) {
            completer.completeError(e);
            sub?.cancel();
          }
        },
        cancelOnError: true,
      );

      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          sub?.cancel();
          throw TimeoutException('Stream timeout');
        },
      );
    } catch (e) {
      debugPrint('⚠️ [GeofenceService] Tier 4 note: $e');
    }

    // ── Tier 5: Fallback to any last known position ──────────────────────────
    final lastFallback = await Geolocator.getLastKnownPosition();
    if (lastFallback != null) {
      debugPrint('📍 [GeofenceService] Tier 5 fallback fix: ${lastFallback.latitude}, ${lastFallback.longitude}');
      return lastFallback;
    }

    throw Exception('Could not get GPS fix. Please ensure Location is ON and has high accuracy enabled.');
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
      '🗺️ [GeofenceService] Geofence check: device=(${position.latitude}, ${position.longitude}) '
      'branch=${branch.name}(${branch.latitude}, ${branch.longitude}) '
      'dist=${distance.toStringAsFixed(1)}m, allowed=${branch.geofenceRadiusMeters}m -> within=$within',
    );

    return GeoValidationResult(
      withinGeofence: within,
      distanceMeters: distance,
    );
  }
}
