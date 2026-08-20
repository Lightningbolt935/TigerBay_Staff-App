import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import 'package:tigerbay_staff_app/providers/auth_provider.dart';
import '../../providers/staff_provider.dart';
import '../../services/pin_service.dart';
import '../../widgets/root_shell.dart';
import 'login_screen.dart';

/// Full-screen PIN lock shown every time the app is opened with a restored
/// session. Prevents access without re-entering the 4-digit staff PIN.
///
/// The user can choose "Sign in differently" to fully sign out and return
/// to [LoginScreen] for a fresh OTP-based login.
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  final PinService _pinService = PinService();
  String _pin = '';
  bool _incorrect = false;
  bool _verifying = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onKeyTap(String digit) {
    if (_pin.length >= 4 || _verifying) return;
    setState(() {
      _pin += digit;
      _incorrect = false;
    });
    if (_pin.length == 4) _verify();
  }

  void _onBackspace() {
    if (_pin.isEmpty || _verifying) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final staffProvider = context.read<StaffProvider>();
    final staff = staffProvider.staff;
    if (staff == null) {
      setState(() => _verifying = false);
      return;
    }

    final ok = await _pinService.verifyPin(staffId: staff.id, pin: _pin);
    if (!mounted) return;

    if (ok) {
      context.read<AuthProvider>().unlockSession();
      // Load branch data before showing the main shell.
      await staffProvider.loadBranch();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RootShell()),
      );
    } else {
      _shakeController.forward(from: 0);
      setState(() {
        _incorrect = true;
        _pin = '';
        _verifying = false;
      });
    }
  }

  Future<void> _signInDifferently() async {
    await context.read<AuthProvider>().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<AuthProvider>().staff;
    final name = staff?.name ?? 'Staff Member';

    return Scaffold(
      backgroundColor: AppColors.primaryBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ---- Brand icon ----
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.gold,
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),

              // ---- Welcome back ----
              Text(
                'Welcome back,',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter your PIN to continue',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 40),

              // ---- PIN dots with shake animation ----
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  final offset = _incorrect
                      ? 10 *
                          (0.5 - _shakeAnimation.value).abs() *
                          (_shakeAnimation.value > 0.5 ? 1 : -1)
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) => _pinDot(i)),
                ),
              ),

              if (_incorrect) ...[
                const SizedBox(height: 12),
                const Text(
                  'Incorrect PIN. Try again.',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 36),

              // ---- Keypad ----
              _keypad(),
              const SizedBox(height: 24),

              // ---- Sign in differently ----
              TextButton(
                onPressed: _signInDifferently,
                child: Text(
                  'Sign in differently',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinDot(int index) {
    final filled = index < _pin.length;
    return Container(
      width: 56,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: filled
            ? AppColors.gold.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: _incorrect
              ? AppColors.danger.withValues(alpha: 0.6)
              : filled
                  ? AppColors.gold.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.1),
          width: 1.5,
        ),
      ),
      child: filled
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }

  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.5,
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox.shrink();
        if (k == 'del') {
          return IconButton(
            onPressed: _verifying ? null : _onBackspace,
            icon: const Icon(Icons.backspace_outlined, color: Colors.white60),
          );
        }
        return TextButton(
          onPressed: _verifying ? null : () => _onKeyTap(k),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            overlayColor: AppColors.gold.withValues(alpha: 0.08),
          ),
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        );
      }).toList(),
    );
  }
}
