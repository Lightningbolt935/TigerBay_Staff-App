import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/staff_provider.dart';
import '../../services/pin_service.dart';
import '../../widgets/root_shell.dart';

/// Shown once, right after first login, if `staffMember.pinHash` is null.
/// Requires the staff member to enter and confirm a 4-digit PIN, which
/// is hashed and stored via flutter_secure_storage (Module 3).
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final PinService _pinService = PinService();
  String _pin = '';
  String? _firstEntry;
  bool _confirming = false;
  String? _error;

  void _onKeyTap(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) _handleComplete();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _handleComplete() async {
    if (!_confirming) {
      setState(() {
        _firstEntry = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }

    if (_pin != _firstEntry) {
      setState(() {
        _error = 'PINs do not match. Start again.';
        _pin = '';
        _firstEntry = null;
        _confirming = false;
      });
      return;
    }

    final staffProvider = context.read<StaffProvider>();
    final staff = staffProvider.staff!;
    await _pinService.setPin(staffId: staff.id, pin: _pin);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.goldPale, shape: BoxShape.circle),
                child: const Icon(Icons.lock_outline, color: AppColors.gold, size: 30),
              ),
              const SizedBox(height: 20),
              Text(
                _confirming ? 'Confirm Your PIN' : 'Create Your Staff PIN',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'This PIN will be used to verify loyalty transactions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) => _pinBox(i)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 24),
              _keypad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinBox(int index) {
    final filled = index < _pin.length;
    return Container(
      width: 52,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: filled ? const Icon(Icons.circle, size: 12) : null,
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
          return IconButton(onPressed: _onBackspace, icon: const Icon(Icons.backspace_outlined));
        }
        return TextButton(
          onPressed: () => _onKeyTap(k),
          child: Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        );
      }).toList(),
    );
  }
}
