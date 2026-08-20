import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_colors.dart';

/// Displays a scannable QR code for a completed reward redemption.
///
/// The QR code encodes a JSON payload:
/// ```json
/// {"redemption_id": "<row_id>", "type": "reward_redeem"}
/// ```
///
/// A live 15-minute countdown timer is shown below the QR code.
/// After expiry, the QR is marked invalid and the user is prompted to
/// return to the scan hub.
class RewardQrScreen extends StatefulWidget {
  /// The reward redemption row ID from Supabase.
  final String redemptionId;

  /// Human-readable reward name shown above the QR.
  final String rewardTitle;

  const RewardQrScreen({
    super.key,
    required this.redemptionId,
    required this.rewardTitle,
  });

  @override
  State<RewardQrScreen> createState() => _RewardQrScreenState();
}

class _RewardQrScreenState extends State<RewardQrScreen> {
  static const _totalSeconds = 15 * 60; // 15 minutes
  int _secondsRemaining = _totalSeconds;
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        setState(() {
          _secondsRemaining = 0;
          _expired = true;
        });
        _timer?.cancel();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  String get _formattedTime {
    final m = _secondsRemaining ~/ 60;
    final s = _secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _qrData => jsonEncode({
        'redemption_id': widget.redemptionId,
        'type': 'reward_redeem',
      });

  double get _progress => _secondsRemaining / _totalSeconds;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Reward QR Code'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // ---- Reward title ----
              Text(
                widget.rewardTitle,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Ask the customer to scan this code at the till',
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ---- QR Code container ----
              Expanded(
                child: Center(
                  child: _expired
                      ? _ExpiredView(
                          onDone: () => Navigator.of(context).pop(),
                        )
                      : _QrView(qrData: _qrData),
                ),
              ),

              // ---- Countdown timer ----
              if (!_expired) ...[
                const SizedBox(height: 24),
                _CountdownWidget(
                  formattedTime: _formattedTime,
                  progress: _progress,
                  secondsRemaining: _secondsRemaining,
                ),
                const SizedBox(height: 8),
                const Text(
                  'QR code expires after 15 minutes for security',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done � Return to Scan Hub'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// QR View
// =============================================================================

class _QrView extends StatelessWidget {
  final String qrData;

  const _QrView({required this.qrData});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: QrImageView(
        data: qrData,
        version: QrVersions.auto,
        size: 240,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: AppColors.primaryBlack,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: AppColors.primaryBlack,
        ),
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      ),
    );
  }
}

// =============================================================================
// Countdown Widget
// =============================================================================

class _CountdownWidget extends StatelessWidget {
  final String formattedTime;
  final double progress;
  final int secondsRemaining;

  const _CountdownWidget({
    required this.formattedTime,
    required this.progress,
    required this.secondsRemaining,
  });

  Color get _timerColor {
    if (secondsRemaining > 5 * 60) return AppColors.success;
    if (secondsRemaining > 2 * 60) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, color: _timerColor, size: 18),
            const SizedBox(width: 6),
            Text(
              'Expires in $formattedTime',
              style: TextStyle(
                color: _timerColor,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(_timerColor),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Expired View
// =============================================================================

class _ExpiredView extends StatelessWidget {
  final VoidCallback onDone;

  const _ExpiredView({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: AppColors.dangerBg,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.timer_off_outlined,
            color: AppColors.danger,
            size: 40,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'QR Code Expired',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'The 15-minute window has passed.\nPlease restart the redemption process.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: onDone,
          child: const Text('Return to Scan Hub'),
        ),
      ],
    );
  }
}
