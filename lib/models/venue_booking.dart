import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Deposit status as stored in `bookings.deposit_status`.
enum DepositStatus { paid, pending, refunded, unknown }

DepositStatus depositStatusFromString(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'paid':
      return DepositStatus.paid;
    case 'pending':
      return DepositStatus.pending;
    case 'refunded':
      return DepositStatus.refunded;
    default:
      return DepositStatus.unknown;
  }
}

/// Maps 1:1 onto the extended `bookings` table (existing columns +
/// the Collins integration columns added by
/// `20260915_collins_bookings_integration.sql`).
class VenueBooking {
  final dynamic id;
  final String? userId;
  final int branchId;

  final DateTime bookingDate; // date-only
  final String bookingTime; // "HH:mm:ss" or "HH:mm" as returned by Postgres
  final int guestCount;
  final String? specialRequests;
  final String status;
  final bool stripsAwarded;
  final DateTime createdAt;

  // Collins integration columns
  final String? collinsBookingId;
  final String? reference;
  final String? customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String? assignedTable;
  final String? bookingType;
  final double depositAmount;
  final DepositStatus depositStatus;
  final Map<String, dynamic>? rawPayload;

  const VenueBooking({
    required this.id,
    required this.branchId,
    required this.bookingDate,
    required this.bookingTime,
    required this.guestCount,
    required this.status,
    required this.stripsAwarded,
    required this.createdAt,
    required this.depositAmount,
    required this.depositStatus,
    this.userId,
    this.specialRequests,
    this.collinsBookingId,
    this.reference,
    this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.assignedTable,
    this.bookingType,
    this.rawPayload,
  });

  factory VenueBooking.fromJson(Map<String, dynamic> json) {
    return VenueBooking(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      branchId: json['branch_id'] is int
          ? json['branch_id'] as int
          : (int.tryParse(json['branch_id']?.toString() ?? '') ?? 2),
      bookingDate: json['booking_date'] != null
          ? (DateTime.tryParse(json['booking_date'].toString()) ?? DateTime.now())
          : DateTime.now(),
      bookingTime: json['booking_time']?.toString() ?? '',
      guestCount: (json['guest_count'] as num?)?.toInt() ?? 1,
      specialRequests: json['special_requests']?.toString(),
      status: json['status']?.toString() ?? 'confirmed',
      stripsAwarded: json['strips_awarded'] == true,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      collinsBookingId: json['collins_booking_id']?.toString(),
      reference: json['reference']?.toString(),
      customerName: json['customer_name']?.toString(),
      customerEmail: json['customer_email']?.toString(),
      customerPhone: json['customer_phone']?.toString(),
      assignedTable: json['assigned_table']?.toString(),
      bookingType: json['booking_type']?.toString(),
      depositAmount: (json['deposit_amount'] as num?)?.toDouble() ?? 0.0,
      depositStatus: depositStatusFromString(json['deposit_status']?.toString()),
      rawPayload: json['raw_payload'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'branch_id': branchId,
      'booking_date': bookingDate.toIso8601String().split('T').first,
      'booking_time': bookingTime,
      'guest_count': guestCount,
      'special_requests': specialRequests,
      'status': status,
      'strips_awarded': stripsAwarded,
      'created_at': createdAt.toIso8601String(),
      'collins_booking_id': collinsBookingId,
      'reference': reference,
      'customer_name': customerName,
      'customer_email': customerEmail,
      'customer_phone': customerPhone,
      'assigned_table': assignedTable,
      'booking_type': bookingType,
      'deposit_amount': depositAmount,
      'deposit_status': depositStatus.name,
      'raw_payload': rawPayload,
    };
  }

  /// Display name for the booking's guest, falling back gracefully.
  String get guestDisplayName {
    if (customerName != null && customerName!.trim().isNotEmpty) {
      return customerName!.trim();
    }
    return 'Guest';
  }

  /// e.g. "Fri, 8 Nov 2026"
  String get formattedDate => DateFormat('EEE, d MMM yyyy').format(bookingDate);

  /// e.g. "1:00 PM" — parses the "HH:mm[:ss]" time string from Postgres.
  String get formattedTime {
    final parts = bookingTime.split(':');
    final hour = int.tryParse(parts.elementAt(0)) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final dt = DateTime(2000, 1, 1, hour, minute);
    return DateFormat('h:mm a').format(dt);
  }

  /// Whether this booking originated from Collins (vs. created in-app).
  bool get isFromCollins => collinsBookingId != null;

  /// Short label for the deposit badge, e.g. "Paid", "Pending", "—".
  String get depositBadgeLabel {
    switch (depositStatus) {
      case DepositStatus.paid:
        return 'Paid';
      case DepositStatus.pending:
        return 'Pending';
      case DepositStatus.refunded:
        return 'Refunded';
      case DepositStatus.unknown:
        return depositAmount > 0 ? 'Unpaid' : '—';
    }
  }

  /// Color for the deposit badge: green = paid, orange = pending,
  /// grey = refunded/unknown/no deposit.
  Color get depositBadgeColor {
    switch (depositStatus) {
      case DepositStatus.paid:
        return Colors.green;
      case DepositStatus.pending:
        return Colors.orange;
      case DepositStatus.refunded:
        return Colors.blueGrey;
      case DepositStatus.unknown:
        return Colors.grey;
    }
  }

  /// Formatted deposit amount, e.g. "£100.00" (assumes GBP; adjust if
  /// you store/support multiple currencies).
  String get formattedDepositAmount =>
      NumberFormat.currency(symbol: '£', decimalDigits: 2).format(depositAmount);
}
