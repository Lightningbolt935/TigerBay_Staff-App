import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

/// Dialog shown when the stored device fingerprint (IDFV / Android ID) does
/// not match the current device, which happens after:
///   - App reinstalls on iOS (IDFV resets per-vendor).
///   - Device replacement without an explicit sign-out.
///
/// Rather than hard-locking the account, the dialog offers a self-service
/// escape hatch: staff authenticate with their local biometrics (Face ID,
/// fingerprint) or device passcode to authorise a re-bind.  The actual
/// backend release is performed by [onPasscodeReleaseRequested], which the
/// caller is responsible for wiring to the appropriate Supabase RPC.
class DeviceMismatchDialog extends StatelessWidget {
  /// Called when biometric / passcode authentication succeeds, or when the
  /// device does not support biometrics and the fallback path is taken.
  ///
  /// The caller should call the backend device-release RPC here and, on
  /// success, store the new device fingerprint and continue the login flow.
  final VoidCallback onPasscodeReleaseRequested;

  const DeviceMismatchDialog({
    super.key,
    required this.onPasscodeReleaseRequested,
  });

  Future<void> _authenticateWithBiometrics(BuildContext context) async {
    final LocalAuthentication auth = LocalAuthentication();

    try {
      // Check if the device is capable of biometric / passcode auth.
      final bool canAuthenticate =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();

      if (!canAuthenticate) {
        // Device has no biometrics and no passcode — fall through directly.
        onPasscodeReleaseRequested();
        return;
      }

      final bool didAuthenticate = await auth.authenticate(
        localizedReason:
            'Authenticate to release the device lock and pair this phone.',
        options: const AuthenticationOptions(
          // biometricOnly: false  → allows passcode fallback if biometrics
          // are unavailable or the user chooses it.
          biometricOnly: false,
          // stickyAuth: true  → keeps the auth prompt alive when the user
          // briefly backgrounds the app (e.g., opens Settings).
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        onPasscodeReleaseRequested();
      }
      // If !didAuthenticate the user cancelled — do nothing; the dialog
      // was already dismissed by Navigator.pop before this call.
    } catch (_) {
      // On any plugin / OS error, fall back to the passcode release path
      // rather than leaving the user permanently blocked.
      onPasscodeReleaseRequested();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Device Mismatch Detected'),
      content: const Text(
        'Your account is linked to another device, or your app session was '
        'reset after reinstalling.\n\n'
        'If this is your current device, you can unbind the old registration '
        'using your local biometrics or passcode.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            _authenticateWithBiometrics(context);
          },
          child: const Text('Release Device & Sign In'),
        ),
      ],
    );
  }
}
