# TigerBay Staff App (Flutter)

Cross-platform (iOS/Android) staff app for attendance, loyalty ("stripes"),
and table control — built to match the provided UI screenshots and driven
entirely by backend data (no hardcoded branch/geofence/permission values).

## Getting started

```bash
flutter pub get
flutter run
```

Set your backend URLs at build/run time instead of hardcoding them:

```bash
flutter run --dart-define=API_BASE_URL=https://api.yourdomain.com/v1 \
            --dart-define=NIGHT_COLLINS_BASE_URL=https://api.nightcollins.com/v1
```

### Permissions to declare

- **iOS** (`ios/Runner/Info.plist`): `NSLocationWhenInUseUsageDescription`,
  `NSCameraUsageDescription` (QR scanning), local network usage description
  if required by `network_info_plus`.
- **Android** (`android/app/src/main/AndroidManifest.xml`):
  `ACCESS_FINE_LOCATION`, `ACCESS_WIFI_STATE`, `CAMERA`.

## Folder structure

```
lib/
  core/
    constants/       # app_constants.dart — API URLs, storage keys, enums
    theme/            # app_colors.dart, app_theme.dart
    utils/            # formatters.dart — duration/date/initials helpers
  models/             # 1:1 with backend schema (fromJson/toJson + Equatable)
    branch.dart
    staff_roles_permissions.dart
    staff_member.dart
    shift_log.dart
    loyalty_transaction.dart
    table_status.dart
  services/
    api_service.dart            # Dio client for the TigerBay backend
    night_collins_service.dart  # Branch-scoped Night Collins integration
    geofence_service.dart       # GPS + Wi-Fi BSSID validation
    secure_storage_service.dart # flutter_secure_storage wrapper
    pin_service.dart            # PIN hashing/verification
  providers/          # Provider-based state management
    staff_provider.dart   # session, active branch, permission getters
    shift_provider.dart   # attendance / geofence validation / live timer
    table_provider.dart   # branch-scoped table grid state
  widgets/
    permission_guard.dart        # Module 1 — wraps restricted actions
    access_denied_dialog.dart    # Module 1 — access-denied bottom sheet
    pin_verification_modal.dart  # Module 3 — PIN prompt before loyalty txns
    status_chip.dart
    root_shell.dart              # bottom-tab navigation
  screens/
    auth/       # login_screen.dart, pin_setup_screen.dart
    home/       # home_screen.dart — dashboard
    attendance/ # attendance_screen.dart — geofence/Wi-Fi clock in/out
    scan/       # scan_hub_screen.dart — QR issue/redeem flows
    tables/     # table_control_screen.dart — floor grid
    profile/    # staff_profile_screen.dart
  main.dart
```

## How each module maps to the code

**Module 1 — Tiered Permissions & Dynamic UI Guards**
`StaffProvider` exposes `canAlterBooking`, `canIssuePoints`,
`canRedeemVouchers`, `canOverrideTables`, `canViewAnalytics` getters read
from the signed-in `StaffMember.permissions`. Any restricted action is
wrapped with `PermissionGuard.run(context, allowed: ..., action: ...)`,
which shows `AccessDeniedDialog` when `allowed` is false. See its use in
`table_control_screen.dart` and `scan_hub_screen.dart`.

**Module 2 — Attendance & Shift Management**
`GeofenceService` wraps `geolocator` (distance calc against
`branch.latitude`/`branch.longitude`/`geofenceRadiusMeters`) and
`network_info_plus` (BSSID match against `branch.wifiBssid`).
`ShiftProvider.canToggleAttendance` is only true when both checks pass,
which gates the Clock In / Clock Out button in `attendance_screen.dart`.
Live shift duration is ticked every second and formatted with
`Formatters.hhmmss` / `Formatters.shortDuration`.

**Module 3 — Loyalty Handshake & PIN Verification**
On first login, `StaffProvider.needsPinSetup()` checks
`staffMember.pinHash` and local secure storage; if unset, the user is
routed to `PinSetupScreen`, which hashes and stores the PIN via
`PinService` (SHA-256 + `flutter_secure_storage`). `ScanHubScreen` uses
`mobile_scanner` to read a customer QR, then always shows
`PinVerificationModal` before calling
`ApiService.submitLoyaltyTransaction(..., pinVerified: true)`.

**Module 4 — Table Control & Night Collins Integration**
`TableProvider.loadTables` / `updateStatus` are always scoped to the
signed-in staff member's `branchId`. `NightCollinsService` authenticates
every request using that specific branch's
`nightCollinsBranchId`/`nightCollinsApiKey`, so branches never cross-talk.
Status toggles in `table_control_screen.dart` are wrapped in
`PermissionGuard` against `canOverrideTables`.

## Notes / next steps for a production build

- `ApiService`/`NightCollinsService` currently assume REST endpoints
  matching the schema; adjust paths to your actual backend contract.
- Add integration tests around `GeofenceService.validate` and
  `PinService.verifyPin` since they gate financially/operationally
  sensitive actions.
- Consider adding a `canViewAnalytics`-gated Analytics screen (permission
  already modeled, screen not yet built).
