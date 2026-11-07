import 'package:flutter/material.dart';

import '../../../models/venue_booking.dart';

/// A single booking row: time slot, guest name, party size badge,
/// assigned table chip, status badge, and deposit status badge.
class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.booking,
    this.showDate = false,
  });

  final VenueBooking booking;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time & Date slot
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDate)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          booking.formattedDate,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      booking.formattedTime,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${booking.guestCount} guest${booking.guestCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                // Name + special requests
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.guestDisplayName,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (booking.specialRequests != null &&
                          booking.specialRequests!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            booking.specialRequests!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                _StatusBadge(status: booking.status),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _PartySizeBadge(count: booking.guestCount),
                if (booking.assignedTable != null &&
                    booking.assignedTable!.trim().isNotEmpty)
                  _TableChip(label: booking.assignedTable!),
                _DepositBadge(booking: booking),
              ],
            ),
            if (booking.specialRequests != null &&
                booking.specialRequests!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _DietarySeatingChips(specialRequests: booking.specialRequests!),
            ],
          ],
        ),
      ),
    );
  }
}

class _PartySizeBadge extends StatelessWidget {
  const _PartySizeBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.people, size: 16),
      label: Text('$count'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _TableChip extends StatelessWidget {
  const _TableChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.table_bar, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  ({Color color, String label}) get _meta {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return (color: Colors.green, label: 'Confirmed');
      case 'complete':
        return (color: Colors.green.shade700, label: 'Complete');
      case 'seated':
        return (color: Colors.teal, label: 'Seated');
      case 'partial_arrival':
        return (color: Colors.lightBlue.shade700, label: 'Partial Arrival');
      case 'walk_in':
        return (color: Colors.indigo, label: 'Walk-in');
      case 'waiting_list':
        return (color: Colors.deepPurple, label: 'Waitlist');
      case 'no_show':
        return (color: Colors.red.shade700, label: 'No Show');
      case 'cancelled':
      case 'canceled':
        return (color: Colors.red, label: 'Cancelled');
      case 'pending':
        return (color: Colors.orange, label: 'Pending');
      case 'arrived':
        return (color: Colors.cyan.shade700, label: 'Arrived');
      default:
        // Title-case the raw status so it always reads cleanly
        final label = status
            .split('_')
            .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
        return (color: Colors.blueGrey, label: label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: meta.color.withValues(alpha: 0.4)),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
            color: meta.color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DepositBadge extends StatelessWidget {
  const _DepositBadge({required this.booking});
  final VenueBooking booking;

  @override
  Widget build(BuildContext context) {
    final color = booking.depositBadgeColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.payments, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            booking.depositAmount > 0
                ? '${booking.depositBadgeLabel} · ${booking.formattedDepositAmount}'
                : booking.depositBadgeLabel,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DietarySeatingChips extends StatelessWidget {
  const _DietarySeatingChips({required this.specialRequests});
  final String specialRequests;

  @override
  Widget build(BuildContext context) {
    final lower = specialRequests.toLowerCase();
    final List<Widget> chips = [];

    if (lower.contains('nut') || lower.contains('allergy') || lower.contains('allergies')) {
      chips.add(
        Chip(
          avatar: const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
          label: Text(
            lower.contains('nut') ? 'Nut Allergy' : 'Allergy Alert',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          backgroundColor: Colors.red.withValues(alpha: 0.12),
          side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    if (lower.contains('gluten')) {
      chips.add(
        Chip(
          avatar: const Text('🌾', style: TextStyle(fontSize: 12)),
          label: const Text(
            'Gluten-Free',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          backgroundColor: Colors.orange.withValues(alpha: 0.12),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.4)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    if (lower.contains('halal')) {
      chips.add(
        Chip(
          avatar: const Text('🥩', style: TextStyle(fontSize: 12)),
          label: const Text(
            'Halal Only',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          backgroundColor: Colors.green.withValues(alpha: 0.12),
          side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    if (lower.contains('vegan')) {
      chips.add(
        Chip(
          avatar: const Text('🥬', style: TextStyle(fontSize: 12)),
          label: const Text(
            'Vegan',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal),
          ),
          backgroundColor: Colors.teal.withValues(alpha: 0.12),
          side: BorderSide(color: Colors.teal.withValues(alpha: 0.4)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    } else if (lower.contains('vegetarian') || lower.contains('veg')) {
      chips.add(
        Chip(
          avatar: const Text('🥬', style: TextStyle(fontSize: 12)),
          label: const Text(
            'Vegetarian',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal),
          ),
          backgroundColor: Colors.teal.withValues(alpha: 0.12),
          side: BorderSide(color: Colors.teal.withValues(alpha: 0.4)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    if (lower.contains('booth')) {
      chips.add(
        Chip(
          avatar: const Icon(Icons.weekend_rounded, size: 14, color: Color(0xFFD4AF37)),
          label: const Text(
            'Booth Seating',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37)),
          ),
          backgroundColor: const Color(0xFFD4AF37).withValues(alpha: 0.12),
          side: const BorderSide(color: Color(0xFFD4AF37)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    if (lower.contains('terrace') || lower.contains('outdoor')) {
      chips.add(
        Chip(
          avatar: const Icon(Icons.deck_rounded, size: 14, color: Colors.cyan),
          label: const Text(
            'Outdoor Terrace',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyan),
          ),
          backgroundColor: Colors.cyan.withValues(alpha: 0.12),
          side: BorderSide(color: Colors.cyan.withValues(alpha: 0.4)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips,
    );
  }
}
