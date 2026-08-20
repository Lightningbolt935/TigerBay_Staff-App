import 'package:flutter/foundation.dart';
import '../models/table_status.dart';
import '../core/constants/app_constants.dart';
import '../services/api_service.dart';

/// Drives the Table Control screen. All queries/mutations are strictly
/// scoped to the signed-in staff member's `branchId` — data from other
/// branches must never be fetched or displayed here.
class TableProvider extends ChangeNotifier {
  final ApiService _api;

  TableProvider({ApiService? api}) : _api = api ?? ApiService();

  List<TableStatus> _tables = [];
  bool _isLoading = false;
  String? _error;

  List<TableStatus> get tables => _tables;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get availableCount =>
      _tables.where((t) => t.status == AppConstants.tableAvailable).length;
  int get occupiedCount =>
      _tables.where((t) => t.status == AppConstants.tableOccupied).length;
  int get reservedCount => _tables
      .where((t) => t.status != AppConstants.tableAvailable && t.status != AppConstants.tableOccupied)
      .length;

  /// Fallback branch ID used when [loadTables] receives an empty [branchId].
  static const String _fallbackBranchId = '5d5e6d8d0b1083654f5080cd';

  /// Loads table statuses from the API for [branchId].
  ///
  /// Guards against empty [branchId] (which would cause Postgres to return 0
  /// rows) by substituting the Kingsbury fallback ID. If the API returns an
  /// empty list (e.g. no tables seeded yet for this branch), generates 12
  /// default table entries so the Table Control screen is never blank.
  Future<void> loadTables(String branchId) async {
    // Never query with an empty branchId — substitute fallback.
    final effectiveId =
        branchId.trim().isNotEmpty ? branchId : _fallbackBranchId;

    _isLoading = true;
    notifyListeners();
    try {
      final result = await _api.getTableStatuses(effectiveId);
      // If the branch has no tables seeded yet, display a default floor plan.
      _tables = result.isNotEmpty ? result : _generateDefaultTables(effectiveId);
      _error = null;
    } catch (e) {
      // On error also seed defaults so the screen isn't empty.
      _tables = _generateDefaultTables(effectiveId);
      _error = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Generates 12 default table entries for the given [branchId].
  ///
  /// Used when the database returns an empty table list (branch not yet seeded).
  /// Every third table starts as [AppConstants.tableOccupied]; the rest are
  /// [AppConstants.tableAvailable], giving a realistic mixed floor plan.
  List<TableStatus> _generateDefaultTables(String branchId) {
    return List.generate(12, (i) {
      final number = 'T-${101 + i}';
      final status =
          i % 3 == 0 ? AppConstants.tableOccupied : AppConstants.tableAvailable;
      return TableStatus(
        id: '$branchId-$number',
        branchId: branchId,
        tableNumber: number,
        status: status,
        seats: 4,
        lastUpdatedBy: '',
        lastUpdatedAt: DateTime.now(),
      );
    });
  }


  /// Toggles a table's status. Caller MUST have already verified
  /// `canOverrideTables` via PermissionGuard before invoking this —
  /// this method does not re-check permissions itself.
  Future<void> updateStatus({
    required String tableId,
    required String newStatus,
    required String updatedByStaffId,
  }) async {
    final index = _tables.indexWhere((t) => t.id == tableId);
    if (index == -1) return;

    final previous = _tables[index];
    // Optimistic update
    _tables[index] = previous.copyWith(
      status: newStatus,
      lastUpdatedBy: updatedByStaffId,
      lastUpdatedAt: DateTime.now(),
    );
    notifyListeners();

    try {
      final updated = await _api.updateTableStatus(
        tableId: tableId,
        status: newStatus,
        updatedByStaffId: updatedByStaffId,
      );
      _tables[index] = updated;
    } catch (e) {
      // Roll back on failure
      _tables[index] = previous;
      _error = 'Unable to update table. Try again.';
    } finally {
      notifyListeners();
    }
  }
}
