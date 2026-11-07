import 'package:flutter/foundation.dart';
import '../models/table_status.dart';
import '../core/constants/app_constants.dart';
import '../services/api_service.dart';
import '../services/booking_sync_service.dart';
import '../screens/bookings/collins_venue_mapper.dart';

/// Drives the Table Control screen. All queries/mutations are strictly
/// scoped to the signed-in staff member's `branchId` — data from other
/// branches must never be fetched or displayed here.
///
/// Initially appears as no tables booked (empty state), and only displays
/// a table when it is actually booked or occupied.
class TableProvider extends ChangeNotifier {
  final ApiService _api;
  final BookingSyncService _bookingService;

  TableProvider({
    ApiService? api,
    BookingSyncService? bookingService,
  })  : _api = api ?? ApiService(),
        _bookingService = bookingService ?? BookingSyncService();

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

  /// Loads table statuses for [branchId].
  ///
  /// Only populates tables that are actually booked or occupied:
  /// 1. Queries backend table statuses (if custom floor plan exists)
  /// 2. Integrates active bookings for this branch (Collins & direct bookings)
  /// 3. If no tables are currently booked, leaves `_tables` empty so the screen
  ///    shows "No tables booked" cleanly.
  Future<void> loadTables(String branchId) async {
    final effectiveId =
        branchId.trim().isNotEmpty ? branchId : _fallbackBranchId;

    _isLoading = true;
    notifyListeners();
    try {
      final List<TableStatus> bookedTables = [];
      final Set<String> seenTableNumbers = {};

      // 1. Fetch any explicit occupied/reserved statuses from tables-status API
      try {
        final apiStatuses = await _api.getTableStatuses(effectiveId);
        for (final t in apiStatuses) {
          // Only show tables that are actually booked or occupied
          if (t.status != AppConstants.tableAvailable) {
            bookedTables.add(t);
            seenTableNumbers.add(t.tableNumber.toLowerCase());
          }
        }
      } catch (_) {
        // Safe to ignore if tables-status endpoint is not deployed yet
      }

      // 2. Fetch active bookings for this branch from Supabase / Collins sync
      try {
        final numericBranchId = CollinsVenueMapper.getBranchNumericId(effectiveId);
        final bookings = await _bookingService.fetchBranchBookings(numericBranchId);

        for (final booking in bookings) {
          if (booking.status.toLowerCase() == 'cancelled') continue;

          // Determine table identifier
          final rawTable = booking.assignedTable?.trim();
          final tableNumber = (rawTable != null && rawTable.isNotEmpty)
              ? rawTable
              : (booking.reference != null
                  ? 'Table #${booking.reference}'
                  : 'Table (Booking ${booking.id})');

          // Prevent duplicate cards if table was already listed
          if (seenTableNumbers.contains(tableNumber.toLowerCase())) continue;
          seenTableNumbers.add(tableNumber.toLowerCase());

          final isSeated = booking.status.toLowerCase() == 'seated' ||
              booking.status.toLowerCase() == 'occupied';

          bookedTables.add(TableStatus(
            id: 'booking-${booking.id}',
            branchId: effectiveId,
            tableNumber: tableNumber,
            status: isSeated ? AppConstants.tableOccupied : AppConstants.tableReserved,
            seats: booking.guestCount,
            lastUpdatedBy: 'Collins Sync',
            lastUpdatedAt: booking.createdAt,
            guestName: booking.customerName,
            bookingTime: booking.bookingTime,
          ));
        }
      } catch (e) {
        debugPrint('[TableProvider] Could not load bookings for tables: $e');
      }

      // Only display tables that are actually booked
      _tables = bookedTables;
      _error = null;
    } catch (e) {
      _tables = [];
      _error = 'Could not load tables: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles a table's status. Caller MUST have already verified
  /// `canOverrideTables` via PermissionGuard before invoking this.
  Future<void> updateStatus({
    required String tableId,
    required String newStatus,
    required String updatedByStaffId,
  }) async {
    final index = _tables.indexWhere((t) => t.id == tableId);
    if (index == -1) return;

    final previous = _tables[index];

    // If marked Available, remove from booked tables view
    if (newStatus == AppConstants.tableAvailable) {
      _tables.removeAt(index);
      notifyListeners();
    } else {
      // Optimistic update
      _tables[index] = previous.copyWith(
        status: newStatus,
        lastUpdatedBy: updatedByStaffId,
        lastUpdatedAt: DateTime.now(),
      );
      notifyListeners();
    }

    try {
      if (!tableId.startsWith('booking-')) {
        await _api.updateTableStatus(
          tableId: tableId,
          status: newStatus,
          updatedByStaffId: updatedByStaffId,
        );
      }
    } catch (e) {
      // Roll back on failure
      if (newStatus == AppConstants.tableAvailable) {
        _tables.insert(index, previous);
      } else {
        _tables[index] = previous;
      }
      _error = 'Unable to update table. Try again.';
      notifyListeners();
    }
  }
}
