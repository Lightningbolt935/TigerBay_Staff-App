import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// OTP input widget designed for email-delivered 6-digit codes.
///
/// Because email OTPs do not trigger the native SMS / SMS-autofill OS flow,
/// this widget adds two UX compensations:
///
///   1. **Clipboard Paste Button** — a paste icon in the text field's suffix
///      that reads the clipboard, strips non-digit characters, and auto-submits
///      if a 6-digit sequence is found.
///
///   2. **Resend Cooldown Timer** — prevents spam resends with a 60-second
///      countdown.  [onResendCode] is called when the staff taps "Resend";
///      the cooldown restarts only if the callback returns `true` (i.e. the
///      backend successfully enqueued a new email).
class OtpVerificationWidget extends StatefulWidget {
  /// Called with the 6-digit code when the user submits or pastes a valid OTP.
  final void Function(String code) onVerify;

  /// Called when the user requests a new code.  Return `true` if the resend
  /// was accepted by the backend (which will restart the cooldown timer),
  /// `false` otherwise (cooldown is not reset so the user isn't spammed).
  final Future<bool> Function() onResendCode;

  const OtpVerificationWidget({
    super.key,
    required this.onVerify,
    required this.onResendCode,
  });

  @override
  State<OtpVerificationWidget> createState() => _OtpVerificationWidgetState();
}

class _OtpVerificationWidgetState extends State<OtpVerificationWidget> {
  final TextEditingController _otpController = TextEditingController();
  int _cooldownSeconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  // ── Cooldown ────────────────────────────────────────────────────────────────

  void _startCooldown() {
    setState(() => _cooldownSeconds = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSeconds > 0) {
        setState(() => _cooldownSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  // ── Clipboard paste ─────────────────────────────────────────────────────────

  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;

    // Strip everything that is not a digit, then check for a 6-digit code.
    final String cleanCode =
        data!.text!.trim().replaceAll(RegExp(r'\D'), '');

    if (cleanCode.length == 6) {
      _otpController.text = cleanCode;
      widget.onVerify(cleanCode);
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          onSubmitted: (value) {
            final clean = value.trim().replaceAll(RegExp(r'\D'), '');
            if (clean.length == 6) widget.onVerify(clean);
          },
          decoration: InputDecoration(
            hintText: '000000',
            counterText: '', // hide the default character counter
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste),
              tooltip: 'Paste from Clipboard',
              onPressed: _pasteFromClipboard,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _cooldownSeconds == 0
              ? () async {
                  final bool success = await widget.onResendCode();
                  if (success) _startCooldown();
                }
              : null,
          child: Text(
            _cooldownSeconds > 0
                ? 'Resend code in ${_cooldownSeconds}s'
                : 'Resend Email Code',
          ),
        ),
      ],
    );
  }
}
