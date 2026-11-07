import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/reward_redemption.dart';

class RewardFulfillmentProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// The dynamic branch ID of the logged-in staff member
  final String? branchId;

  RewardFulfillmentProvider({dynamic branchId})
      : branchId = branchId?.toString().trim();

  List<RewardRedemption> _allRedemptions = [];
  bool _isLoading = false;
  String? _error;
  String _activeFilter = 'pending'; // 'pending', 'completed', 'all'
  RealtimeChannel? _realtimeSubscription;

  List<RewardRedemption> get allRedemptions => _allRedemptions;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get activeFilter => _activeFilter;

  List<RewardRedemption> get filteredRedemptions {
    switch (_activeFilter) {
      case 'pending':
        return _allRedemptions.where((r) => r.isPending).toList();
      case 'completed':
        return _allRedemptions.where((r) => r.isCompleted).toList();
      default:
        return _allRedemptions;
    }
  }

  int get pendingCount => _allRedemptions.where((r) => r.isPending).length;

  int get completedTodayCount {
    final now = DateTime.now();
    return _allRedemptions.where((r) {
      if (!r.isCompleted) return false;
      final targetDate = r.completedAt ?? r.createdAt;
      return targetDate.year == now.year &&
          targetDate.month == now.month &&
          targetDate.day == now.day;
    }).length;
  }

  void setFilter(String filter) {
    _activeFilter = filter;
    notifyListeners();
  }

  Future<void> loadRedemptions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Build query against strips_ledger with branch_id included
      var query = _supabase.from('strips_ledger').select('''
            id,
            user_id,
            amount,
            transaction_type,
            description,
            branch_id,
            created_at,
            status,
            completed_at,
            completed_by
          ''').eq('transaction_type', 'redeem');

      // 2. Query branch at database level if branchId is provided
      if (branchId != null && branchId!.isNotEmpty) {
        final parsedBranchId = int.tryParse(branchId!);
        if (parsedBranchId != null) {
          query = query.eq('branch_id', parsedBranchId);
        } else {
          query = query.eq('branch_id', branchId!);
        }
      }

      final response =
          await query.order('created_at', ascending: false).limit(100);
      final rawList = (response as List).cast<Map<String, dynamic>>();

      // 3. Extract unique non-null user IDs
      final userIds = rawList
          .map((r) => r['user_id']?.toString().trim())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      // 4. Batch fetch guest profiles using proper inFilter syntax
      Map<String, Map<String, dynamic>> profileMap = {};
      if (userIds.isNotEmpty) {
        try {
          final profilesResponse = await _supabase
              .from('profiles')
              .select('id, full_name, email, home_site_id')
              .inFilter('id', userIds);

          for (final p in (profilesResponse as List)) {
            final id = p['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              profileMap[id] = Map<String, dynamic>.from(p);
            }
          }
        } catch (profileError) {
          debugPrint(
              '⚠️ [RewardFulfillmentProvider] Could not load profiles: $profileError');
        }
      }

      // 5. Construct display entities
      final List<RewardRedemption> loadedList = [];
      for (final rawRow in rawList) {
        final row = Map<String, dynamic>.from(rawRow);
        final uId = row['user_id']?.toString() ?? '';
        final profile = profileMap[uId];

        final fullName = profile?['full_name']?.toString().trim();
        final email = profile?['email']?.toString().trim();
        final displayName = (fullName != null && fullName.isNotEmpty)
            ? fullName
            : (uId.isNotEmpty
                ? 'Guest (${uId.length >= 6 ? uId.substring(0, 6) : uId})'
                : 'Guest');

        // Bridge field names to ensure RewardRedemption model parses cleanly
        row['customer_name'] = displayName;
        row['customer_email'] = email ?? '';
        row['reward_title'] = row['description'] ?? 'Reward Redemption';
        row['profiles'] = {
          'full_name': displayName,
          'email': email ?? '',
        };

        loadedList.add(RewardRedemption.fromJson(row));
      }

      _allRedemptions = loadedList;
      _error = null;
    } catch (e, stack) {
      _error = 'Failed to load reward redemptions: $e';
      debugPrint(
          '❌ [RewardFulfillmentProvider] loadRedemptions error: $e\n$stack');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> markAsCompleted({
    required int redemptionId,
    required String staffNameOrId,
  }) async {
    final originalIndex =
        _allRedemptions.indexWhere((r) => r.id == redemptionId);
    if (originalIndex == -1) return false;

    final originalItem = _allRedemptions[originalIndex];
    final now = DateTime.now();

    // Optimistic UI update
    _allRedemptions[originalIndex] = originalItem.copyWith(
      status: 'completed',
      completedAt: now,
      completedBy: staffNameOrId,
    );
    notifyListeners();

    try {
      await _supabase.from('strips_ledger').update({
        'status': 'completed',
        'completed_at': now.toIso8601String(),
        'completed_by': staffNameOrId,
      }).eq('id', redemptionId);

      return true;
    } catch (e) {
      _allRedemptions[originalIndex] = originalItem;
      _error = 'Could not update status: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> revertToPending(int redemptionId) async {
    final originalIndex =
        _allRedemptions.indexWhere((r) => r.id == redemptionId);
    if (originalIndex == -1) return false;

    final originalItem = _allRedemptions[originalIndex];

    _allRedemptions[originalIndex] = originalItem.copyWith(
      status: 'pending',
      completedAt: null,
      completedBy: null,
    );
    notifyListeners();

    try {
      await _supabase.from('strips_ledger').update({
        'status': 'pending',
        'completed_at': null,
        'completed_by': null,
      }).eq('id', redemptionId);

      return true;
    } catch (e) {
      _allRedemptions[originalIndex] = originalItem;
      _error = 'Could not revert status: $e';
      notifyListeners();
      return false;
    }
  }

  void subscribeToRealtime() {
    _realtimeSubscription?.unsubscribe();
    _realtimeSubscription = _supabase
        .channel('public:strips_ledger')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'strips_ledger',
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord.isEmpty) return;
            if (newRecord['transaction_type'] == 'redeem') {
              loadRedemptions();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _realtimeSubscription?.unsubscribe();
    super.dispose();
  }
}
