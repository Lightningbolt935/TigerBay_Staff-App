import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/staff_provider.dart';
import '../../providers/auth_provider.dart';

/// Point Attribution / Bill Processing Screen.
///
/// Staff enter a member code (or receive it via QR from [ScanHubScreen])
/// and a bill total. On submit the RPC [allocate_points_by_member_code]
/// calculates the correct points using the member's tier multiplier and
/// credits them, returning a summary that is presented in a success dialog.
class StaffBillingPointScreen extends StatefulWidget {
  /// Optional member code pre-filled via QR scan from [ScanHubScreen].
  final String? initialMemberCode;

  const StaffBillingPointScreen({super.key, this.initialMemberCode});

  @override
  State<StaffBillingPointScreen> createState() =>
      _StaffBillingPointScreenState();
}

class _StaffBillingPointScreenState extends State<StaffBillingPointScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _memberCodeController;
  final _billAmountController = TextEditingController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _memberCodeController =
        TextEditingController(text: widget.initialMemberCode ?? '');
  }

  @override
  void dispose() {
    _memberCodeController.dispose();
    _billAmountController.dispose();
    super.dispose();
  }

  // ---- Processing logic --------------------------------------------------

  Future<void> _processBillPoints() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isProcessing = true);

    final staff = context.read<StaffProvider>().staff ??
        context.read<AuthProvider>().staff;

    if (staff == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Staff session missing. Please log in again.'),
          ),
        );
        setState(() => _isProcessing = false);
      }
      return;
    }

    final rawCode = _memberCodeController.text.trim();
    final billAmount = double.parse(_billAmountController.text.trim());
    final venueId = staff.venueId ?? staff.branchId ?? '';

    try {
      Map<String, dynamic>? resultData;

      // 1. Try Supabase RPC first
      try {
        final rpcRes = await Supabase.instance.client.rpc(
          'allocate_points_by_member_code',
          params: {
            'p_member_code': rawCode,
            'p_bill_amount': billAmount,
            'p_venue_id': venueId.isNotEmpty ? venueId : null,
            'p_staff_id': staff.id,
          },
        );
        if (rpcRes != null && rpcRes is Map) {
          resultData = Map<String, dynamic>.from(rpcRes);
        }
      } catch (rpcErr) {
        debugPrint('[BillingPoint] RPC failed, using direct DB logic: $rpcErr');
      }

      // 2. Fallback: Direct database resolution if RPC is not available
      resultData ??= await _processDirectPointAllocation(
        memberCode: rawCode,
        billAmount: billAmount,
        staffId: staff.id,
        venueId: venueId,
      );

      if (mounted) _showSuccessDialog(resultData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            content: Text('Transaction Failed: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Direct client-side logic to resolve member code, fetch tier multiplier,
  /// credit strips/points to loyalty_accounts, and log loyalty_transactions.
  Future<Map<String, dynamic>> _processDirectPointAllocation({
    required String memberCode,
    required double billAmount,
    required String staffId,
    required String venueId,
  }) async {
    final client = Supabase.instance.client;

    // A. Find customer profile by member_code, id, or email
    Map<String, dynamic>? profile;

    // Try matching member_code
    final byMemberCode = await client
        .from('profiles')
        .select()
        .eq('member_code', memberCode)
        .maybeSingle();

    if (byMemberCode != null) {
      profile = Map<String, dynamic>.from(byMemberCode);
    } else {
      // Try matching UUID id
      final byId = await client
          .from('profiles')
          .select()
          .eq('id', memberCode)
          .maybeSingle();

      if (byId != null) {
        profile = Map<String, dynamic>.from(byId);
      } else {
        // Try matching email
        final byEmail = await client
            .from('profiles')
            .select()
            .ilike('email', memberCode)
            .maybeSingle();
        if (byEmail != null) {
          profile = Map<String, dynamic>.from(byEmail);
        }
      }
    }

    if (profile == null) {
      throw Exception('No customer found with member number "$memberCode".');
    }

    final customerId = profile['id'] as String;
    final customerName = (profile['full_name'] ??
            profile['name'] ??
            profile['email'] ??
            'Member $memberCode')
        .toString();

    // B. Resolve Tier and Multiplier
    double multiplier = 1.0;
    String tierName = 'Bronze';

    final membershipTierId = profile['membership_tier_id'];
    if (membershipTierId != null) {
      try {
        final tierRow = await client
            .from('membership_tiers')
            .select()
            .eq('id', membershipTierId)
            .maybeSingle();

        if (tierRow != null) {
          tierName = (tierRow['name'] as String?) ?? 'Tier';
          final stripsRate = tierRow['strips_per_booking'];
          if (stripsRate != null) {
            multiplier = (stripsRate is num) ? stripsRate.toDouble() : 1.0;
          }
        }
      } catch (e) {
        debugPrint('[BillingPoint] Error loading membership_tier: $e');
      }
    } else {
      // Check loyalty_tier text column (e.g. 'bronze', 'silver', 'gold', 'platinum')
      final rawTier = (profile['loyalty_tier'] as String? ?? 'bronze').toLowerCase();
      switch (rawTier) {
        case 'black diamond':
        case 'black_diamond':
          tierName = 'Black Diamond';
          multiplier = 4.0;
          break;
        case 'platinum':
          tierName = 'Platinum';
          multiplier = 3.0;
          break;
        case 'gold':
          tierName = 'Gold';
          multiplier = 2.0;
          break;
        case 'silver':
          tierName = 'Silver';
          multiplier = 1.5;
          break;
        case 'bronze':
        default:
          tierName = 'Bronze';
          multiplier = 1.0;
          break;
      }
    }

    // C. Calculate Points / Strips earned
    final pointsEarned = (billAmount * multiplier).round();

    // D. Fetch or create loyalty_accounts row
    int currentBalance = 0;
    final existingAccount = await client
        .from('loyalty_accounts')
        .select()
        .eq('user_id', customerId)
        .maybeSingle();

    if (existingAccount != null) {
      currentBalance = (existingAccount['points_balance'] as int?) ?? 0;
      final newBalance = currentBalance + pointsEarned;
      await client
          .from('loyalty_accounts')
          .update({
            'points_balance': newBalance,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', customerId);
    } else {
      await client.from('loyalty_accounts').insert({
        'user_id': customerId,
        'points_balance': pointsEarned,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }

    final newBalance = currentBalance + pointsEarned;

    // E. Insert transaction record in loyalty_transactions
    await client.from('loyalty_transactions').insert({
      'user_id': customerId,
      'branch_id': venueId.isNotEmpty ? venueId : null,
      'points': pointsEarned,
      'type': 'earned',
      'description': 'Bill award (£${billAmount.toStringAsFixed(2)}) × ${multiplier}x ($tierName)',
      'spend_amount': billAmount,
      'created_at': DateTime.now().toIso8601String(),
    });

    // F. Try calling update_loyalty_tier RPC if exists
    try {
      await client.rpc('update_loyalty_tier', params: {'p_user_id': customerId});
    } catch (_) {}

    return {
      'customer_name': customerName,
      'tier_name': tierName,
      'multiplier': multiplier,
      'bill_amount': billAmount.toStringAsFixed(2),
      'points_earned': pointsEarned,
      'new_balance': newBalance,
    };
  }

  // ---- Success dialog ---------------------------------------------------

  void _showSuccessDialog(dynamic data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.success, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Points Credited',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            const SizedBox(height: 4),
            _dialogRow(
                Icons.person_outline_rounded,
                'Customer',
                data['customer_name']?.toString() ?? '—'),
            _dialogRow(
                Icons.military_tech_outlined,
                'Tier',
                '${data['tier_name'] ?? '—'} (${data['multiplier'] ?? 1}x)'),
            const Divider(height: 20),
            _dialogRow(
                Icons.receipt_long_outlined,
                'Bill Total',
                '£${data['bill_amount'] ?? '0.00'}'),
            const SizedBox(height: 8),
            // Prominent points earned section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '+${data['points_earned'] ?? 0}',
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success),
                  ),
                  const Text(
                    'Strips Added',
                    style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _dialogRow(
                Icons.account_balance_wallet_outlined,
                'New Balance',
                '${data['new_balance'] ?? 0} Strips'),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _billAmountController.clear();
                _memberCodeController.clear();
              },
              child: const Text('DONE'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ---- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Process Bill & Award Points'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Info card -------------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.goldPale,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.gold, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Enter the member code manually or scan a QR card. '
                        'Points are calculated using the member\'s tier multiplier.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ---- Member code ----------------------------------------
              _sectionLabel('Member Code', Icons.badge_outlined),
              const SizedBox(height: 8),
              TextFormField(
                controller: _memberCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'e.g. TB-MEM-001',
                  prefixIcon: const Icon(Icons.credit_card_outlined,
                      color: AppColors.textSecondary),
                  suffixIcon: widget.initialMemberCode != null
                      ? const Tooltip(
                          message: 'Pre-filled via QR scan',
                          child: Icon(Icons.qr_code_2_outlined,
                              color: AppColors.gold),
                        )
                      : null,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Enter member code'
                        : null,
              ),
              const SizedBox(height: 24),

              // ---- Bill amount ----------------------------------------
              _sectionLabel('Total Bill (£)', Icons.receipt_long_outlined),
              const SizedBox(height: 8),
              TextFormField(
                controller: _billAmountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.attach_money_outlined,
                      color: AppColors.textSecondary),
                  prefixText: '£ ',
                ),
                validator: (v) =>
                    (v == null || double.tryParse(v) == null)
                        ? 'Enter a valid bill amount'
                        : null,
              ),
              const SizedBox(height: 32),

              // ---- Submit button ---------------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bolt_rounded),
                  label: Text(_isProcessing
                      ? 'Processing...'
                      : 'CALCULATE & CREDIT POINTS'),
                  onPressed: _isProcessing ? null : _processBillPoints,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.gold),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}
