import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/venue_booking.dart';

/// Handles all Supabase access for the branch bookings dashboard:
/// reading bookings, subscribing to realtime changes, and triggering a
/// manual Collins sync. This is the ONLY place in the Flutter app that
/// should know about the `bookings` table or the `sync-collins-bookings`
/// Edge Function — the app never calls the Collins API directly.
class BookingSyncService {
  BookingSyncService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  RealtimeChannel? _activeChannel;

  /// Loads all bookings for [branchId] on [date], ordered by time.
  Future<List<VenueBooking>> fetchBranchBookings(
    int branchId,
    DateTime date,
  ) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final dateString = dateOnly.toIso8601String().split('T').first;

    final response = await _client
        .from('bookings')
        .select()
        .eq('branch_id', branchId)
        .eq('booking_date', dateString)
        .order('booking_time', ascending: true);

    return (response as List)
        .map((row) => VenueBooking.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Subscribes to realtime INSERT/UPDATE/DELETE changes on `bookings`
  /// for [branchId], invoking [onUpdate] with a freshly-fetched list
  /// each time something changes. Returns the channel so the caller can
  /// unsubscribe (e.g. in `dispose()`).
  ///
  /// Note: this re-fetches today's bookings on every change event rather
  /// than patching the in-memory list, which keeps ordering/filtering
  /// correct with negligible cost at typical per-branch booking volumes.
  RealtimeChannel subscribeToBranchBookings(
    int branchId,
    DateTime date,
    void Function(List<VenueBooking> bookings) onUpdate,
  ) {
    unsubscribe();

    final channel = _client
        .channel('bookings-branch-$branchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'branch_id',
            value: branchId,
          ),
          callback: (payload) async {
            final refreshed = await fetchBranchBookings(branchId, date);
            onUpdate(refreshed);
          },
        )
        .subscribe();

    _activeChannel = channel;
    return channel;
  }

  /// Unsubscribes from the currently active realtime channel, if any.
  void unsubscribe() {
    final channel = _activeChannel;
    if (channel != null) {
      _client.removeChannel(channel);
      _activeChannel = null;
    }
  }

  /// Invokes the `sync-collins-bookings` Edge Function to pull the
  /// latest bookings from Collins for [branchId] (or all active
  /// branches if `null`), and upsert them into `bookings`.
  ///
  /// Returns the raw function response body for callers that want to
  /// inspect per-branch sync results/errors.
  Future<Map<String, dynamic>> triggerManualSync(int? branchId) async {
    final response = await _client.functions.invoke(
      'sync-collins-bookings',
      body: branchId != null ? {'branch_id': branchId} : <String, dynamic>{},
    );

    if (response.status != 200 && response.status != 207) {
      throw BookingSyncException(
        'Sync failed with status ${response.status}: ${response.data}',
      );
    }

    return Map<String, dynamic>.from(response.data as Map);
  }

  void dispose() {
    unsubscribe();
  }
}

class BookingSyncException implements Exception {
  BookingSyncException(this.message);
  final String message;

  @override
  String toString() => 'BookingSyncException: $message';
}
