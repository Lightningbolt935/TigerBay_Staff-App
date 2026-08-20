import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

/// Maps to `loyalty_transactions`. Created after a successful QR scan
/// AND successful PIN verification (`pinVerified` must be true before
/// the transaction is ever persisted — see Module 3).
class LoyaltyTransaction extends Equatable {
  final String id;
  final String staffId;
  final String customerId;
  final String branchId;
  final String transactionType; // 'ISSUE_POINTS' | 'REDEEM_VOUCHER'
  final int pointsStripesAmount;
  final String? voucherCode;
  final DateTime timestamp;
  final bool pinVerified;

  const LoyaltyTransaction({
    required this.id,
    required this.staffId,
    required this.customerId,
    required this.branchId,
    required this.transactionType,
    required this.pointsStripesAmount,
    this.voucherCode,
    required this.timestamp,
    required this.pinVerified,
  });

  bool get isIssue => transactionType == AppConstants.txnIssuePoints;
  bool get isRedeem => transactionType == AppConstants.txnRedeemVoucher;

  factory LoyaltyTransaction.fromJson(Map<String, dynamic> json) {
    return LoyaltyTransaction(
      id: json['id'] as String,
      staffId: json['staffId'] as String,
      customerId: json['customerId'] as String,
      branchId: json['branchId'] as String,
      transactionType: json['transactionType'] as String,
      pointsStripesAmount: json['pointsStripesAmount'] as int,
      voucherCode: json['voucherCode'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      pinVerified: json['pinVerified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'staffId': staffId,
      'customerId': customerId,
      'branchId': branchId,
      'transactionType': transactionType,
      'pointsStripesAmount': pointsStripesAmount,
      'voucherCode': voucherCode,
      'timestamp': timestamp.toIso8601String(),
      'pinVerified': pinVerified,
    };
  }

  @override
  List<Object?> get props => [
        id,
        staffId,
        customerId,
        branchId,
        transactionType,
        pointsStripesAmount,
        voucherCode,
        timestamp,
        pinVerified,
      ];
}
