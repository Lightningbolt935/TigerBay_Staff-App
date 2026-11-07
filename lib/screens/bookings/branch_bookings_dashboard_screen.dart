import 'package:flutter/material.dart';

import '../../models/venue_booking.dart';
import '../../services/booking_sync_service.dart';
import 'widgets/booking_card.dart';
import 'widgets/booking_filter_bar.dart';

import 'collins_webview_screen.dart';

/// Dashboard showing bookings for [branchId]. Can show all bookings till date
/// or filter to a selectable date. Pull-to-refresh triggers a manual Collins sync
/// (via the Edge Function) and then reloads from Supabase; realtime Postgres changes
/// also refresh the list automatically as new bookings sync in.
class BranchBookingsDashboardScreen extends StatefulWidget {
  const BranchBookingsDashboardScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  final int branchId;
  final String branchName;

  @override
  State<BranchBookingsDashboardScreen> createState() =>
      _BranchBookingsDashboardScreenState();
}

class _BranchBookingsDashboardScreenState
    extends State<BranchBookingsDashboardScreen> {
  final BookingSyncService _service = BookingSyncService();

  // Null indicates "All Bookings Till Date"
  DateTime? _selectedDate;
  List<VenueBooking> _bookings = const [];

  bool _isInitialLoading = true;
  bool _isSyncing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant BranchBookingsDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      _loadInitial();
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isInitialLoading = true;
      _errorMessage = null;
    });

    // Always trigger a sync-and-fetch on load to get the latest Collins data.
    // triggerManualSync now uses include_bookings:true so bookings come back
    // in the same response without a second round-trip.
    try {
      final result = await _service.triggerSyncAndFetch(
        widget.branchId,
        date: _selectedDate,
      );
      if (mounted) {
        setState(() {
          _bookings = result;
          _errorMessage = null;
        });
      }
    } catch (_) {
      // Sync failed — fall back to fetching whatever is already cached locally
      await _fetchBookings();
    }

    _subscribeRealtime();
    if (mounted) setState(() => _isInitialLoading = false);
  }

  Future<void> _fetchBookings() async {
    try {
      final bookings =
          await _service.fetchBranchBookings(widget.branchId, _selectedDate);
      if (mounted) {
        setState(() {
          _bookings = bookings;
          _errorMessage = null;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not load bookings: $err');
      }
    }
  }

  void _subscribeRealtime() {
    _service.subscribeToBranchBookings(
      widget.branchId,
      _selectedDate,
      (updated) {
        if (mounted) setState(() => _bookings = updated);
      },
    );
  }

  Future<void> _onDateChanged(DateTime? date) async {
    setState(() {
      _selectedDate = date;
      _isInitialLoading = true;
    });
    await _fetchBookings();
    _subscribeRealtime(); // re-subscribe scoped to the new date's refresh
    if (mounted) setState(() => _isInitialLoading = false);
  }

  Future<void> _onPullToRefresh() async {
    setState(() {
      _isSyncing = true;
      _errorMessage = null;
    });
    try {
      final result = await _service.triggerSyncAndFetch(
        widget.branchId,
        date: _selectedDate,
      );
      if (mounted) setState(() => _bookings = result);
    } catch (err) {
      if (mounted) {
        setState(() => _errorMessage = 'Sync failed. Check your connection and try again.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not sync with Collins — showing cached data'),
            action: SnackBarAction(label: 'Retry', onPressed: _onPullToRefresh),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.branchName),
            const Text(
              'Customer Bookings · Realtime',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New customer booking',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CollinsWebViewScreen()),
            ),
          ),
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync with Collins',
              onPressed: _onPullToRefresh,
            ),
        ],
        bottom: BookingFilterBar(
          selectedDate: _selectedDate,
          onDateChanged: _onDateChanged,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _ErrorState(message: _errorMessage!, onRetry: _fetchBookings);
    }

    if (_bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onPullToRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _EmptyState(
              title: _selectedDate != null
                  ? 'No bookings for this day'
                  : 'No customer bookings yet',
              subtitle: _selectedDate != null
                  ? 'Pull down to sync with Collins or choose another day'
                  : 'Tap Sync to pull the latest reservations from Collins',
              onSync: _isSyncing ? null : _onPullToRefresh,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onPullToRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _bookings.length,
        itemBuilder: (context, index) => BookingCard(
          booking: _bookings[index],
          showDate: _selectedDate == null,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    this.title = 'No customer bookings found',
    this.subtitle = 'Pull down or tap Sync to fetch latest reservations',
    this.onSync,
  });

  final String title;
  final String subtitle;
  final Future<void> Function()? onSync;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_outlined, size: 56, color: Theme.of(context).hintColor),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
          if (onSync != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onSync,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Sync with Collins'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
