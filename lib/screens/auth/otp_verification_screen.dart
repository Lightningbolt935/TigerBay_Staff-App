import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import 'package:tigerbay_staff_app/providers/auth_provider.dart';
import '../../providers/staff_provider.dart';
import '../auth/pin_setup_screen.dart';
import '../../widgets/root_shell.dart';

/// OTP verification screen shown after a successful OTP request.
///
/// Displays:
/// - The identifier (Staff ID or email) the code was sent to.
/// - A 6-digit OTP input field.
/// - An active 60-second countdown timer.
/// - A "Resend OTP" button that enables when the timer reaches 0.
///
/// On successful verification, navigates to [PinSetupScreen] (if PIN
/// is not yet configured) or [RootShell] (main app).
class OtpVerificationScreen extends StatefulWidget {
  /// The Staff ID or email used to request the OTP.
  final String identifier;

  const OtpVerificationScreen({super.key, required this.identifier});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  /// Six individual controllers for each OTP digit box.
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());

  /// Focus nodes for auto-advancing between digit fields.
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;

  @override
  void dispose() {
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  /// Concatenates all 6 digit controllers into the full OTP string.
  String get _otpCode =>
      _digitControllers.map((c) => c.text).join();

  /// Whether all 6 digit fields are filled.
  bool get _isComplete =>
      _digitControllers.every((c) => c.text.length == 1);

  /// Handles digit entry: auto-advances focus and auto-submits when
  /// all 6 digits are entered.
  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      // Advance to next field.
      _focusNodes[index + 1].requestFocus();
    }
    if (_isComplete) {
      _verify();
    }
  }

  /// Handles backspace: clears current field and moves focus back.
  void _onDigitKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _digitControllers[index].text.isEmpty &&
        index > 0) {
      _digitControllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  /// Verifies the entered OTP via [AuthProvider.verifyOtp].
  Future<void> _verify() async {
    if (_isVerifying || !_isComplete) return;

    setState(() => _isVerifying = true);

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.verifyOtp(_otpCode);

    if (!mounted) return;

    if (success) {
      // Load Branch data before navigating.
      final staffProvider = context.read<StaffProvider>();
      await staffProvider.loadBranch();
      if (!mounted) return;

      final needsPin = authProvider.needsPinSetup;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              needsPin ? const PinSetupScreen() : const RootShell(),
        ),
        (_) => false, // Remove all previous routes.
      );
    } else {
      setState(() => _isVerifying = false);
      // Show error snackbar.
      if (authProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error!),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  /// Formats seconds into "M:SS" display string.
  String _formatCountdown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            authProvider.resetOtpFlow();
            Navigator.of(context).pop();
          },
        ),
        title: const Text('Verify OTP'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // ---- Lock icon ----
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.goldPale,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.lock_clock_outlined,
                  color: AppColors.gold,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              // ---- Instructions ----
              const Text(
                'Enter Verification Code',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'A 6-digit code was sent to\n${widget.identifier}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),

              // ---- 6-digit OTP input boxes ----
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  return Container(
                    width: 48,
                    height: 56,
                    margin: EdgeInsets.only(
                      left: index == 0 ? 0 : 8,
                      right: index == 5 ? 0 : 0,
                    ),
                    child: KeyboardListener(
                      focusNode: FocusNode(), // Wrapper for key events.
                      onKeyEvent: (event) => _onDigitKeyEvent(index, event),
                      child: TextField(
                        controller: _digitControllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          counterText: '', // Hide the "0/1" counter.
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceMuted,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.gold,
                              width: 2,
                            ),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) => _onDigitChanged(index, value),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),

              // ---- Countdown timer / Resend button ----
              if (authProvider.countdown > 0)
                Text(
                  'Resend OTP in ${_formatCountdown(authProvider.countdown)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                TextButton(
                  onPressed: authProvider.isLoading
                      ? null
                      : () => authProvider.resendOtp(),
                  child: const Text(
                    'Resend OTP',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 32),

              // ---- Verify button ----
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isComplete && !_isVerifying)
                      ? _verify
                      : null,
                  child: _isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify & Sign In'),
                ),
              ),

              // ---- Error display ----
              if (authProvider.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  authProvider.error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
