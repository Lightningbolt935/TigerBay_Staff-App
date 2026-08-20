import 'package:flutter/foundation.dart';
import '../models/staff_member.dart';
import '../models/branch.dart';
import '../services/api_service.dart';
import '../services/pin_service.dart';
import 'auth_provider.dart'; // <-- Fixed relative import

/// Holds the signed-in StaffMember's operational context (permissions,
/// active Branch) for the lifetime of the session.
///
/// **Auth is delegated to [AuthProvider]** — this provider reads
/// [AuthProvider.staff] for the current session and exposes convenience
/// permission getters used by [PermissionGuard] throughout the app.
///
/// Every Branch-scoped query in the app reads from this provider's
/// [staff.branchId] to enforce data isolation.
class StaffProvider extends ChangeNotifier {
  final ApiService _api;
  final PinService _pinService;
  final AuthProvider _authProvider;

  StaffProvider({
    required AuthProvider authProvider,
    ApiService? api,
    PinService? pinService,
  })  : _authProvider = authProvider,
        _api = api ?? ApiService(),
        _pinService = pinService ?? PinService() {
    // Listen to auth state changes so we can react to sign-in / sign-out
    // and live tier updates from the permission guard service.
    _authProvider.addListener(_onAuthChanged);
  }

  Branch? _branch;
  bool _isLoading = false;
  String? _error;

  /// The Kingsbury Branch ID used as a fallback when a staff profile has no
  /// `branch_id` set in Supabase (venue_id is null/empty).
  static const String _fallbackBranchId = '5d5e6d8d0b1083654f5080cd';

  /// A hard-coded fallback [Branch] returned when the API call fails, ensuring
  /// downstream screens always receive non-null Branch data.
  static Branch get _fallbackBranch => const Branch(
        id: _fallbackBranchId,
        name: 'TigerBay Kingsbury',
        latitude: 51.5847,
        longitude: -0.2756,
        geofenceRadiusMeters: 150,
        wifiSsid: 'TigerBay-Staff',
        wifiBssid: '00:00:00:00:00:00',
        nightCollinsBranchId: '',
        nightCollinsApiKey: '',
      );

  /// The currently authenticated staff member, read from [AuthProvider].
  StaffMember? get staff => _authProvider.staff;

  Branch? get branch => _branch;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _authProvider.isSignedIn;

  /// Loads the Branch details for the authenticated staff member's [branchId].
  ///
  /// If [branchId] is empty (profile has no venue assigned in Supabase),
  /// the Kingsbury fallback ID is used instead of querying with an empty string.
  /// If the API call fails, [_fallbackBranch] is used so Branch is never null
  /// after this call — preventing '-' placeholders throughout the UI.
  Future<void> loadBranch() async {
    if (staff == null) return;

    // Guard: branchId is nullable — use null-coalescing before .trim()
    // so we never call methods on a null String?.
    final effectiveBranchId =
        (staff!.branchId?.trim().isNotEmpty == true)
            ? staff!.branchId!
            : _fallbackBranchId;

    _setLoading(true);
    try {
      _branch = await _api.getBranch(effectiveBranchId);
      _error = null;
    } catch (e) {
      // API unreachable or unknown ID — use fallback so UI is never blank.
      debugPrint('[StaffProvider] loadBranch failed, using fallback: $e');
      _branch = _fallbackBranch;
      _error = null;
    } finally {
      _setLoading(false);
    }
  }

  /// Checks whether the staff member needs to complete PIN setup.
  Future<bool> needsPinSetup() async {
    if (staff == null) return false;
    if (staff!.hasPinConfigured) return false;
    return !(await _pinService.hasPinConfigured());
  }

  void updateStaff(StaffMember updatedStaff) {
    _authProvider.updateTierLevel(updatedStaff.tierLevel);
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Reacts to changes in [AuthProvider] (sign-in, sign-out, tier updates).
  void _onAuthChanged() {
    if (!_authProvider.isSignedIn) {
      // Auth was cleared — reset local Branch state.
      _branch = null;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authProvider.signOut();
    _branch = null;
    notifyListeners();
  }

  // ---- Permission helpers (used by PermissionGuard widget) ----
  // These read from the cached permissions on the StaffMember model.
  // For sensitive actions, use PermissionGuardService for LIVE checks.
  bool get canAlterBooking => staff?.permissions.canAlterBooking ?? false;
  bool get canIssuePoints => staff?.permissions.canIssuePoints ?? false;
  bool get canRedeemVouchers => staff?.permissions.canRedeemVouchers ?? false;
  bool get canOverrideTables => staff?.permissions.canOverrideTables ?? false;
  bool get canViewAnalytics => staff?.permissions.canViewAnalytics ?? false;

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }
}