import 'package:flutter/material.dart';

import '../../models/venue_booking.dart';
import '../../services/booking_sync_service.dart';
import 'widgets/booking_card.dart';
import 'widgets/booking_filter_bar.dart';

/// Dashboard showing bookings for [branchId] on a selectable date.
/// Pull-to-refresh triggers a manual Collins sync (via the Edge
/// Function) and then reloads from Supabase; realtime Postgres changes
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

  DateTime _selectedDate = DateTime.now();
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

    await _fetchBookings();
    _subscribeRealtime();

    if (mounted) {
      setState(() => _isInitialLoading = false);
    }
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

  Future<void> _onDateChanged(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _isInitialLoading = true;
    });
    await _fetchBookings();
    _subscribeRealtime(); // re-subscribe scoped to the new date's refresh
    if (mounted) setState(() => _isInitialLoading = false);
  }

  Future<void> _onPullToRefresh() async {
    setState(() => _isSyncing = true);
    try {
      await _service.triggerManualSync(widget.branchId);
      await _fetchBookings();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $err')),
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
        title: Text(widget.branchName),
        actions: [
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
              tooltip: 'Sync now',
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
          children: const [
            _EmptyState(),
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
        itemBuilder: (context, index) => BookingCard(booking: _bookings[index]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 96),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy, size: 48, color: Theme.of(context).hintColor),
          const SizedBox(height: 12),
          Text(
            'No bookings for this day',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Pull down to sync with Collins',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
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
