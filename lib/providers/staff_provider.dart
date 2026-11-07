import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff_member.dart';
import '../models/branch.dart';
import '../services/pin_service.dart';
import 'auth_provider.dart';

/// Role hierarchy matching dropdown values: Concierge, Staff, Manager, Director.
enum StaffRole {
  concierge('Concierge'),
  staff('Staff'),
  manager('Manager'),
  director('Director');

  final String label;
  const StaffRole(this.label);

  static StaffRole fromString(String? role) {
    if (role == null) return StaffRole.staff;
    switch (role.trim().toLowerCase()) {
      case 'concierge':
        return StaffRole.concierge;
      case 'manager':
        return StaffRole.manager;
      case 'director':
        return StaffRole.director;
      case 'staff':
      default:
        return StaffRole.staff;
    }
  }

  /// 1. Bookings: All roles can view bookings
  bool get canViewBookings => true;

  /// 2. Redeem Rewards: Staff, Manager, Director (Concierge cannot)
  bool get canRedeemRewards =>
      this == StaffRole.staff ||
      this == StaffRole.manager ||
      this == StaffRole.director;

  /// 3. Award Strips (Give points): Manager & Director only
  bool get canAwardStrips =>
      this == StaffRole.manager || this == StaffRole.director;

  /// 4. Complete / Revert Rewards: Manager & Director only
  bool get canCompleteRewards =>
      this == StaffRole.manager || this == StaffRole.director;

  /// 5. Access Fulfillment Queue Screen: Manager & Director only
  bool get canAccessFulfillmentScreen =>
      this == StaffRole.manager || this == StaffRole.director;
}

/// Holds the signed-in StaffMember's operational context (permissions,
/// active Branch) loaded directly from Supabase database tables.
class StaffProvider extends ChangeNotifier {
  final PinService _pinService;
  final AuthProvider _authProvider;

  StaffProvider({
    required AuthProvider authProvider,
    PinService? pinService,
  })  : _authProvider = authProvider,
        _pinService = pinService ?? PinService() {
    _authProvider.addListener(_onAuthChanged);
  }

  Branch? _branch;
  bool _isLoading = false;
  String? _error;
  String? _liveDbRole;

  StaffMember? get staff => _authProvider.staff;
  Branch? get branch => _branch;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _authProvider.isSignedIn;

  // ── Role Hierarchy & Permissions ──────────────────────────────
  StaffRole get role => StaffRole.fromString(_liveDbRole ?? staff?.role);

  bool get canViewBookings => role.canViewBookings;
  bool get canRedeemRewards => role.canRedeemRewards;
  bool get canAwardStrips => role.canAwardStrips;
  bool get canCompleteRewards => role.canCompleteRewards;
  bool get canAccessFulfillment => role.canAccessFulfillmentScreen;

  // ── Backward-Compatible Legacy Permissions ────────────────────
  bool get canAlterBooking =>
      role == StaffRole.manager ||
      role == StaffRole.director ||
      (staff?.permissions.canAlterBooking ?? false);

  bool get canIssuePoints => canAwardStrips;

  bool get canRedeemVouchers => canRedeemRewards;

  bool get canOverrideTables =>
      role == StaffRole.manager ||
      role == StaffRole.director ||
      (staff?.permissions.canOverrideTables ?? false);

  bool get canViewAnalytics =>
      role == StaffRole.manager ||
      role == StaffRole.director ||
      (staff?.permissions.canViewAnalytics ?? false);

  /// Converts a Supabase `branches` row into a typed [Branch] model.
  Branch _branchFromMap(Map<String, dynamic> m) {
    final idStr = m['id']?.toString() ?? '';
    final nameStr = (m['name'] ?? m['title'] ?? 'Branch').toString();
    final lat = (m['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (m['longitude'] as num?)?.toDouble() ?? 0.0;
    final radius = (m['geofence_radius_meters'] as num?)?.toDouble() ?? 1000.0;
    final collinsVenueId = (m['collins_venue_id'] ?? '').toString();

    try {
      return Branch.fromJson({
        'id': idStr,
        'name': nameStr,
        'latitude': lat,
        'longitude': lng,
        'geofence_radius_meters': radius,
        'wifi_ssid': m['wifi_ssid'] ?? 'TigerBay-Staff',
        'wifi_bssid': m['wifi_bssid'] ?? '00:00:00:00:00:00',
        'night_collins_branch_id': collinsVenueId,
        'night_collins_api_key': '',
        ...m,
      });
    } catch (_) {
      return Branch(
        id: idStr,
        name: nameStr,
        latitude: lat,
        longitude: lng,
        geofenceRadiusMeters: radius,
        wifiSsid: m['wifi_ssid']?.toString() ?? 'TigerBay-Staff',
        wifiBssid: m['wifi_bssid']?.toString() ?? '00:00:00:00:00:00',
        nightCollinsBranchId: collinsVenueId,
        nightCollinsApiKey: '',
      );
    }
  }

  /// Loads Branch coordinates and role strictly from the database tables.
  Future<void> loadBranch() async {
    if (staff == null) return;
    _setLoading(true);
    _error = null;

    try {
      final client = Supabase.instance.client;
      Map<String, dynamic>? branchRow;
      String? branchIdRaw = staff!.branchId?.trim();
      String? venueIdRaw;

      // 1. Fetch live assigned branch, venue, and role for current staff member
      try {
        final staffData = await client
            .from('staff_members')
            .select('branch_id, venue_id, role')
            .or('staff_id.eq.${staff!.staffId},id.eq.${staff!.id}')
            .maybeSingle();

        if (staffData != null) {
          if (staffData['branch_id'] != null) {
            branchIdRaw = staffData['branch_id'].toString();
          }
          if (staffData['venue_id'] != null) {
            venueIdRaw = staffData['venue_id'].toString();
          }
          if (staffData['role'] != null) {
            _liveDbRole = staffData['role'].toString();
          }
        }
      } catch (e) {
        debugPrint('⚠️ [StaffProvider] Notice querying staff_members: $e');
      }

      final branchIdInt = int.tryParse(branchIdRaw ?? '');

      // 2. Query `branches` by integer id
      if (branchIdInt != null) {
        try {
          final row = await client
              .from('branches')
              .select()
              .eq('id', branchIdInt)
              .maybeSingle();
          if (row != null) branchRow = Map<String, dynamic>.from(row);
        } catch (e) {
          debugPrint('⚠️ [StaffProvider] Query branches by int ID failed: $e');
        }
      }

      // 3. Query `branches` by collins_venue_id
      if (branchRow == null) {
        final candidateVenue = venueIdRaw ?? branchIdRaw;
        if (candidateVenue != null && candidateVenue.isNotEmpty) {
          try {
            final row = await client
                .from('branches')
                .select()
                .eq('collins_venue_id', candidateVenue)
                .maybeSingle();
            if (row != null) branchRow = Map<String, dynamic>.from(row);
          } catch (e) {
            debugPrint(
                '⚠️ [StaffProvider] Query branches by venue_id failed: $e');
          }
        }
      }

      // 4. Fallback to the first active branch configured in the table
      if (branchRow == null) {
        try {
          final row = await client
              .from('branches')
              .select()
              .eq('is_active', true)
              .order('id', ascending: true)
              .limit(1)
              .maybeSingle();
          if (row != null) branchRow = Map<String, dynamic>.from(row);
        } catch (e) {
          debugPrint(
              '⚠️ [StaffProvider] Query fallback branch from DB failed: $e');
        }
      }

      if (branchRow != null) {
        _branch = _branchFromMap(branchRow);
        debugPrint(
            '📍 [StaffProvider] Loaded branch: ${_branch?.name} | Active Role: ${role.label}');
        _error = null;
      } else {
        _error = 'No active branch found in the database.';
        debugPrint('❌ [StaffProvider] $_error');
      }
    } catch (e) {
      _error = 'Failed to load branch from database: $e';
      debugPrint('❌ [StaffProvider] loadBranch error: $e');
    } finally {
      _setLoading(false);
    }
  }

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

  void _onAuthChanged() {
    if (!_authProvider.isSignedIn) {
      _branch = null;
      _liveDbRole = null;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authProvider.signOut();
    _branch = null;
    _liveDbRole = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }
}
