import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

/// Maps to `tables_status`. Drives the Table Control grid. Status
/// mutation via the UI must be guarded by `canOverrideTables`.
class TableStatus extends Equatable {
  final String id;
  final String branchId;
  final String tableNumber;
  final String status; // 'Available' | 'Occupied' | 'Unavailable'
  final String lastUpdatedBy;
  final DateTime lastUpdatedAt;
  final int seats;
  final String? guestName;
  final String? bookingTime;

  const TableStatus({
    required this.id,
    required this.branchId,
    required this.tableNumber,
    required this.status,
    required this.lastUpdatedBy,
    required this.lastUpdatedAt,
    this.seats = 2,
    this.guestName,
    this.bookingTime,
  });

  bool get isAvailable => status == AppConstants.tableAvailable;
  bool get isOccupied => status == AppConstants.tableOccupied;
  bool get isUnavailable => status == AppConstants.tableUnavailable;

  factory TableStatus.fromJson(Map<String, dynamic> json) {
    return TableStatus(
      id: json['id'] as String,
      branchId: json['branchId'] as String,
      tableNumber: json['tableNumber'] as String,
      status: json['status'] as String,
      lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
      lastUpdatedAt: json['lastUpdatedAt'] != null
          ? DateTime.parse(json['lastUpdatedAt'] as String)
          : DateTime.now(),
      seats: json['seats'] as int? ?? 2,
      guestName: json['guestName'] as String?,
      bookingTime: json['bookingTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'branchId': branchId,
      'tableNumber': tableNumber,
      'status': status,
      'lastUpdatedBy': lastUpdatedBy,
      'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
      'seats': seats,
      if (guestName != null) 'guestName': guestName,
      if (bookingTime != null) 'bookingTime': bookingTime,
    };
  }

  TableStatus copyWith({
    String? status,
    String? lastUpdatedBy,
    DateTime? lastUpdatedAt,
    String? guestName,
    String? bookingTime,
  }) {
    return TableStatus(
      id: id,
      branchId: branchId,
      tableNumber: tableNumber,
      status: status ?? this.status,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      seats: seats,
      guestName: guestName ?? this.guestName,
      bookingTime: bookingTime ?? this.bookingTime,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        tableNumber,
        status,
        lastUpdatedBy,
        lastUpdatedAt,
        seats,
        guestName,
        bookingTime,
      ];
}
