class RewardRedemption {
  final int id;
  final String userId;
  final int amount;
  final String transactionType;
  final String description;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? completedBy;
  final String? customerName;
  final String? customerEmail;

  const RewardRedemption({
    required this.id,
    required this.userId,
    required this.amount,
    required this.transactionType,
    required this.description,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.completedBy,
    this.customerName,
    this.customerEmail,
  });

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isCompleted => status.toLowerCase() == 'completed';

  String get rewardTitle {
    if (description.startsWith('Redeemed:')) {
      return description.replaceFirst('Redeemed:', '').trim();
    }
    return description;
  }

  factory RewardRedemption.fromJson(Map<String, dynamic> json) {
    int parsedAmount = 0;
    if (json['amount'] is num) {
      parsedAmount = (json['amount'] as num).toInt();
    } else if (json['amount'] is String) {
      parsedAmount = int.tryParse(json['amount']) ?? 0;
    }

    return RewardRedemption(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      userId: json['user_id']?.toString() ?? '',
      amount: parsedAmount,
      transactionType: json['transaction_type']?.toString() ?? 'redeem',
      description: json['description']?.toString() ?? 'Reward Item',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString())
          : null,
      completedBy: json['completed_by']?.toString(),
      customerName: json['profiles']?['full_name'] ??
          json['profiles']?['name'] ??
          json['customer_name'],
      customerEmail: json['profiles']?['email'] ?? json['customer_email'],
    );
  }

  RewardRedemption copyWith({
    String? status,
    DateTime? completedAt,
    String? completedBy,
  }) {
    return RewardRedemption(
      id: id,
      userId: userId,
      amount: amount,
      transactionType: transactionType,
      description: description,
      status: status ?? this.status,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      customerName: customerName,
      customerEmail: customerEmail,
    );
  }
}
