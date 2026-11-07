import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerbay_staff_app/core/constants/app_constants.dart';
import 'package:tigerbay_staff_app/models/table_status.dart';
import 'package:tigerbay_staff_app/models/venue_booking.dart';

void main() {
  group('Table Control & Status Tests', () {
    test('TableStatus initializes correctly with guest name and booking time', () {
      final now = DateTime.now();
      final table = TableStatus(
        id: 'tbl_101',
        branchId: '2',
        tableNumber: 'Table 5',
        status: AppConstants.tableOccupied,
        lastUpdatedBy: 'Staff Member',
        lastUpdatedAt: now,
        seats: 4,
        guestName: 'Sarah Connor',
        bookingTime: '19:30',
      );

      expect(table.isOccupied, isTrue);
      expect(table.isAvailable, isFalse);
      expect(table.guestName, equals('Sarah Connor'));
      expect(table.bookingTime, equals('19:30'));
      expect(table.seats, equals(4));
    });

    test('TableStatus JSON round-trip serialization maintains booking details', () {
      final json = {
        'id': 'tbl_202',
        'branchId': '2',
        'tableNumber': 'Table 12',
        'status': 'Occupied',
        'lastUpdatedBy': 'System Sync',
        'lastUpdatedAt': '2026-09-24T18:00:00.000Z',
        'seats': 6,
        'guestName': 'John Wick',
        'bookingTime': '20:00',
      };

      final table = TableStatus.fromJson(json);
      expect(table.id, equals('tbl_202'));
      expect(table.guestName, equals('John Wick'));
      expect(table.bookingTime, equals('20:00'));
      expect(table.seats, equals(6));

      final outputJson = table.toJson();
      expect(outputJson['guestName'], equals('John Wick'));
      expect(outputJson['bookingTime'], equals('20:00'));
    });
  });

  group('VenueBooking Defensive Parsing Tests', () {
    test('VenueBooking parses UUID string ID without crashing', () {
      final json = {
        'id': '8c77fdc6-6ce2-475a-939e-97ec958c2196',
        'branch_id': 2,
        'booking_date': '2026-09-24',
        'booking_time': '19:30:00',
        'guest_count': 4,
        'status': 'confirmed',
        'customer_name': 'Emma Watson',
        'deposit_amount': 20.0,
        'deposit_status': 'paid',
      };

      final booking = VenueBooking.fromJson(json);
      expect(booking.id, equals('8c77fdc6-6ce2-475a-939e-97ec958c2196'));
      expect(booking.customerName, equals('Emma Watson'));
      expect(booking.guestDisplayName, equals('Emma Watson'));
      expect(booking.formattedTime, equals('7:30 PM'));
      expect(booking.depositStatus, equals(DepositStatus.paid));
      expect(booking.depositBadgeLabel, equals('Paid'));
      expect(booking.depositBadgeColor, equals(Colors.green));
      expect(booking.formattedDepositAmount, contains('20.00'));
    });

    test('VenueBooking handles missing fields with safe defaults', () {
      final json = <String, dynamic>{
        'id': 105,
      };

      final booking = VenueBooking.fromJson(json);
      expect(booking.id, equals('105'));
      expect(booking.guestDisplayName, equals('Guest'));
      expect(booking.branchId, equals(2));
      expect(booking.guestCount, equals(1));
      expect(booking.depositStatus, equals(DepositStatus.unknown));
      expect(booking.depositBadgeLabel, equals('—'));
    });
  });
}
