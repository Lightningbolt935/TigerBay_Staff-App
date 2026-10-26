import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/reward_redemption.dart';

class RewardFulfillmentProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

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
      final response = await _supabase
          .from('strips_ledger')
          .select('''
            id,
            user_id,
            amount,
            transaction_type,
            description,
            created_at,
            status,
            completed_at,
            completed_by
          ''')
          .eq('transaction_type', 'redeem')
          .order('created_at', ascending: false)
          .limit(100);

      _allRedemptions = (response as List)
          .map((row) =>
              RewardRedemption.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      _error = null;
    } catch (e) {
      _error = 'Failed to load reward redemptions: $e';
      debugPrint('❌ [RewardFulfillmentProvider] loadRedemptions error: $e');
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

    // Optimistic update
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
      // Revert if database update fails
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
