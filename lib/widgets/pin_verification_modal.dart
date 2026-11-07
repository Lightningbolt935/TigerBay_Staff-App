import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../services/pin_service.dart';

/// The 4-digit PIN accountability prompt shown before finalizing any
/// loyalty transaction (Module 3). Mirrors the "Staff Verification"
/// screenshot: title, lock icon, 4 boxes, numeric keypad, inline error.
class PinVerificationModal extends StatefulWidget {
  final String staffId;
  final PinService? pinService;

  const PinVerificationModal({
    super.key,
    required this.staffId,
    this.pinService,
  });

  /// Returns true if the PIN was verified successfully, false/null otherwise.
  static Future<bool?> show(BuildContext context, {required String staffId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PinVerificationModal(staffId: staffId),
    );
  }

  @override
  State<PinVerificationModal> createState() => _PinVerificationModalState();
}

class _PinVerificationModalState extends State<PinVerificationModal> {
  late final PinService _pinService;
  String _pin = '';
  bool _incorrect = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _pinService = widget.pinService ?? PinService();
  }

  void _onKeyTap(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _incorrect = false;
    });
    if (_pin.length == 4) _verify();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final ok = await _pinService.verifyPin(staffId: widget.staffId, pin: _pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _incorrect = true;
        _pin = '';
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const Expanded(
                  child: Text(
                    'Staff Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.goldPale,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_clock_outlined, color: AppColors.gold, size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Confirm Your PIN',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              "Enter your 4-digit staff PIN to finalize this transaction",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) => _pinBox(i)),
            ),
            if (_incorrect) ...[
              const SizedBox(height: 12),
              const Text('Incorrect PIN',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 24),
            _keypad(),
          ],
        ),
      ),
    );
  }

  Widget _pinBox(int index) {
    final filled = index < _pin.length;
    final isCurrent = index == _pin.length;
    return Container(
      width: 52,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _incorrect
              ? AppColors.danger
              : (isCurrent ? AppColors.gold : AppColors.border),
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: filled
          ? const Icon(Icons.circle, size: 12, color: AppColors.textPrimary)
          : null,
    );
  }

  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.7,
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox.shrink();
        if (k == 'del') {
          return IconButton(
            onPressed: _verifying ? null : _onBackspace,
            icon: const Icon(Icons.backspace_outlined),
          );
        }
        return TextButton(
          onPressed: _verifying ? null : () => _onKeyTap(k),
          child: Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        );
      }).toList(),
    );
  }
}
