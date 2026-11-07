import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Production-grade geofence attendance guard.
///
/// Handles the full pre-flight checklist before accepting a check-in position:
///   1. GPS service enabled check.
///   2. Runtime permission request with permanent-denial redirect to Settings.
///   3. iOS 14+ / Android 12+ Precise Location accuracy gate.
///   4. GPS drift filter — rejects fixes with an accuracy margin > 30 m.
///   5. Android mock-location (spoofing) detection via [Position.isMocked].
///
/// Returns a validated [Position] on success, or `null` if any check fails
/// (in which case an appropriate dialog is shown to the user).
class AttendanceService {
  /// Performs all location pre-flight checks and returns a validated [Position].
  ///
  /// Returns `null` if any check fails — a dialog is always shown to the user
  /// explaining the failure reason before returning null.
  static Future<Position?> getValidCheckInPosition(BuildContext context) async {
    // ── 1. Check Location Services ───────────────────────────────────────────
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Actively prompt the user to open device GPS settings.
      await Geolocator.openLocationSettings();
      if (!context.mounted) return null;
      _showErrorDialog(
        context,
        'Location Disabled',
        'GPS is required to verify your venue attendance. Please enable it and try again.',
      );
      return null;
    }

    // ── 2. Permission Handling ────────────────────────────────────────────────
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!context.mounted) return null;
        _showErrorDialog(
          context,
          'Permission Required',
          'Location access is required to verify venue attendance.',
        );
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return null;
      _showSettingsDialog(context);
      return null;
    }

    // ── 3. Verify Precise Location (iOS 14+ / Android 12+) ───────────────────
    // Approximate Location is insufficient for geofence radius verification.
    final LocationAccuracyStatus accuracyStatus =
        await Geolocator.getLocationAccuracy();
    if (accuracyStatus == LocationAccuracyStatus.reduced) {
      if (!context.mounted) return null;
      _showErrorDialog(
        context,
        'Precise Location Needed',
        "You have granted Approximate Location. Please enable 'Precise Location' "
            'in Settings for venue verification.',
      );
      return null;
    }

    // ── 4. Fetch Position with platform-tuned settings & fallback ─────────────
    // AndroidSettings: forceLocationManager ensures compatibility on emulators
    // and budget Android handsets that don't support Google Play location APIs.
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
        forceAndroidLocationManager: true, // Required for emulators & budget handsets
      );
    } catch (_) {
      // Timeout or any GPS error — attempt the last known position as fallback.
      position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        if (!context.mounted) return null;
        _showErrorDialog(
          context,
          'GPS Timeout',
          'Could not obtain a location fix. Please step near a window and try again.',
        );
        return null;
      }
    }

    // Filter GPS drift — reject fixes with an accuracy margin > 30 m.
    if (position.accuracy > 30.0) {
      if (!context.mounted) return null;
      _showErrorDialog(
        context,
        'Weak GPS Signal',
        'GPS accuracy is too low (${position.accuracy.toStringAsFixed(1)} m). '
            'Please step near a window or move outdoors.',
      );
      return null;
    }

    // ── 5. Anti-Spoofing Check (Android only) ─────────────────────────────────
    // [Position.isMocked] is always false on iOS; on Android it reflects the
    // "Allow mock locations" developer option or spoofing apps.
    if (position.isMocked) {
      if (kDebugMode) {
        debugPrint('⚠️ [AttendanceService] Mock Location detected but allowed in Debug Mode for emulator testing.');
      } else {
        if (!context.mounted) return null;
        _showErrorDialog(
          context,
          'Mock Location Detected',
          'Fake location services are active. Please disable spoofing '
              'applications to check in.',
        );
        return null;
      }
    }

    if (kDebugMode) {
      debugPrint('📍 [AttendanceService] Valid position obtained: ${position.latitude}, ${position.longitude} (acc: ${position.accuracy}m, isMocked: ${position.isMocked})');
    }

    return position;
  }

  // ── Private UI helpers ──────────────────────────────────────────────────────

  static void _showSettingsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Location Permission Permanently Denied'),
        content: const Text(
          'Please grant location permissions in App Settings to proceed with '
          'check-in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  static void _showErrorDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
