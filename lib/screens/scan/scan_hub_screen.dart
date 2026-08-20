import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/staff_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/permission_guard.dart';
import '../../widgets/pin_verification_modal.dart';
import '../rewards/reward_qr_screen.dart';
import '../billing/staff_billing_point_screen.dart';

enum ScanMode { issue, redeem }

/// Scan Hub — used for both "Scan & Issue" and "Scan & Redeem" flows.
/// Permission is checked (canIssuePoints / canRedeemVouchers) before the
/// scanner is even armed; a successful scan always routes through the
/// PIN Verification modal before the transaction is submitted.
class ScanHubScreen extends StatefulWidget {
  final ScanMode mode;
  const ScanHubScreen({super.key, required this.mode});

  @override
  State<ScanHubScreen> createState() => _ScanHubScreenState();
}

class _ScanHubScreenState extends State<ScanHubScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final SupabaseService _supabase = SupabaseService();
  bool _isProcessing = false;
  bool _scanning = true;

  bool get _isIssue => widget.mode == ScanMode.issue;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || !_scanning) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null) return;
    _handleScannedCode(code);
  }

  String _parseScannedQr(String raw) {
    final trimmed = raw.trim();
    try {
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        // Customer app format: { "uid": "...", "code": "100001", ... }
        if (decoded.containsKey('code') && decoded['code'] != null && decoded['code'].toString().isNotEmpty) {
          return decoded['code'].toString();
        }
        if (decoded.containsKey('uid') && decoded['uid'] != null && decoded['uid'].toString().isNotEmpty) {
          return decoded['uid'].toString();
        }
      }
    } catch (_) {}
    return trimmed;
  }

  Future<void> _handleScannedCode(String rawCode) async {
    final memberCode = _parseScannedQr(rawCode);
    final staffProvider = context.read<StaffProvider>();
    final allowed = _isIssue ? staffProvider.canIssuePoints : staffProvider.canRedeemVouchers;

    PermissionGuard.run(
      context,
      allowed: allowed,
      action: () async {
        if (_isIssue) {
          // For Issue mode, navigate to Bill Points screen with the parsed member code pre-filled!
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => StaffBillingPointScreen(
                  initialMemberCode: memberCode,
                ),
              ),
            );
          }
          return;
        }

        // For Redeem mode, verify staff PIN first
        setState(() {
          _isProcessing = true;
          _scanning = false;
        });

        final staff = staffProvider.staff;
        if (staff == null) {
          setState(() {
            _isProcessing = false;
            _scanning = true;
          });
          return;
        }

        final verified = await PinVerificationModal.show(context, staffId: staff.id);

        if (verified == true) {
          // Redeem flow — insert redemption row, show QR code screen.
          try {
            final redemptionId = await _supabase.insertRewardRedemption(
              rewardId: memberCode,
              staffId: staff.id,
              customerId: memberCode,
            );
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => RewardQrScreen(
                    redemptionId: redemptionId,
                    rewardTitle: 'Reward Redemption',
                  ),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Redemption failed. Please try again.'),
                backgroundColor: AppColors.danger,
              ));
              setState(() {
                _isProcessing = false;
                _scanning = true;
              });
            }
          }
        } else {
          setState(() {
            _isProcessing = false;
            _scanning = true;
          });
        }
      },
    );

    if (!allowed) {
      setState(() {
        _isProcessing = false;
        _scanning = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlack,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('Scan Hub',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(_isIssue ? 'Scan & Issue Points' : 'Scan & Redeem',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bolt_outlined, color: AppColors.gold),
                    onPressed: () => _controller.toggleTorch(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(controller: _controller, onDetect: _onDetect),
                      Center(
                        child: Container(
                          width: 220,
                          height: 2,
                          color: AppColors.gold,
                        ),
                      ),
                      const Positioned(
                        bottom: 24,
                        left: 0,
                        right: 0,
                        child: Text(
                          'Align QR code within the frame',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Text('Customer Loyalty QR',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text(
                    'Ask the customer to open the TigerBay app and show their digital wallet QR code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isProcessing ? null : () => _promptManualEntry(),
                    child: const Text('Enter Code Manually',
                        style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF17181C),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isProcessing ? 'Processing...' : 'Ready to Scan',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          _isProcessing ? 'Verifying transaction...' : 'Waiting for customer to present code...',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.goldPale,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: AppColors.success),
                        SizedBox(width: 6),
                        Text('active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _promptManualEntry() {
    showDialog(
      context: context,
      builder: (_) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Enter Customer Code'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (controller.text.trim().isNotEmpty) {
                  _handleScannedCode(controller.text.trim());
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }
}
