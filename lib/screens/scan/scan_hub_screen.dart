import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../main.dart' show routeObserver;
import '../../providers/staff_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/permission_guard.dart';
import '../../widgets/pin_verification_modal.dart';
import '../rewards/reward_qr_screen.dart';
import '../billing/staff_billing_point_screen.dart';

enum ScanMode { issue, redeem }

/// Lifecycle of the camera inside this screen.
enum _CameraPhase {
  /// Scanner widget unmounted and camera hardware fully released.
  idle,

  /// Permission checked out; waiting for the platform to start the camera.
  starting,

  /// Live preview running.
  running,

  /// Camera could not start (or died) — reason shown with a retry action.
  failed,

  /// Camera permission permanently denied — deep link to app settings.
  permissionBlocked,
}

/// Scan Hub — used for both "Scan & Issue" and "Scan & Redeem" flows.
/// Permission is checked (canIssuePoints / canRedeemVouchers) before the
/// scanner is even armed; a successful scan always routes through the
/// PIN Verification modal before the transaction is submitted.
class ScanHubScreen extends StatefulWidget {
  final ScanMode mode;

  /// Whether this instance is currently user-facing. The shell keeps this
  /// screen mounted inside an IndexedStack even when another tab is shown —
  /// the camera MUST release the hardware when [visible] is false, otherwise
  /// it blocks (and gets blocked by) any other scanner instance.
  final bool visible;

  const ScanHubScreen({super.key, required this.mode, this.visible = true});

  @override
  State<ScanHubScreen> createState() => _ScanHubScreenState();
}

class _ScanHubScreenState extends State<ScanHubScreen>
    with WidgetsBindingObserver, RouteAware {
  /// The controller is created with autoStart:false and driven exclusively by
  /// [_syncCamera]. mobile_scanner 5.x binds its controller in a `late final`
  /// field when the MobileScanner widget mounts — swapping controllers on a
  /// live widget is silently ignored, so recovery ALWAYS goes through a full
  /// widget remount ([_restartCamera]), never a controller swap.
  MobileScannerController? _controller;

  /// Bumped on every full restart; used as the scanner widget key so each
  /// retry gets a brand-new widget State bound to the fresh controller.
  int _scannerEpoch = 0;

  _CameraPhase _phase = _CameraPhase.idle;
  String? _failureDetail;

  bool _isProcessing = false;
  bool _scanning = true;
  bool _routeActive = true;
  bool _backgrounded = false;

  bool _routeSubscribed = false;

  /// Serializes all camera transitions (start/stop/restart) so overlapping
  /// triggers (tab switch + route push + lifecycle event in one frame)
  /// can never interleave stop() and start() against the native camera.
  bool _cameraBusy = false;
  bool _cameraSyncQueued = false;

  final SupabaseService _supabase = SupabaseService();

  bool get _isIssue => widget.mode == ScanMode.issue;

  /// The camera should run only while ALL of these hold.
  bool get _wantsCamera =>
      widget.visible &&
      _routeActive &&
      !_backgrounded &&
      _scanning &&
      !_isProcessing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer to after first frame so ModalRoute/dependencies are settled.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_routeSubscribed) {
      routeObserver.subscribe(this, ModalRoute.of(context)!);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      // Teardown path — no setState allowed here. autoStart is false so the
      // plugin does NOT stop the camera on widget dispose; we must do it.
      () async {
        try {
          await controller.stop();
        } catch (_) {}
        try {
          await controller.dispose();
        } catch (_) {}
      }();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(ScanHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      debugPrint('📷 [ScanHub] Tab visibility changed -> ${widget.visible}');
      _syncCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // With an externally-provided controller, mobile_scanner 5.x skips its
    // own lifecycle handling (`if (widget.controller != null) return;`), so
    // backgrounding/resuming must be handled here or the preview dies.
    if (state == AppLifecycleState.resumed) {
      if (_backgrounded && mounted) setState(() => _backgrounded = false);
      _syncCamera();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_backgrounded && mounted) setState(() => _backgrounded = true);
      _syncCamera();
    }
  }

  @override
  void didPushNext() {
    // Another route covers us (Billing, Reward QR…) — release the camera
    // so the next screen can claim the hardware.
    _routeActive = false;
    _syncCamera();
  }

  @override
  void didPopNext() {
    // Back from a covered route — reset transaction flags and re-arm the
    // camera. Without the flag reset the screen stayed dead after billing.
    _routeActive = true;
    if (mounted) {
      _isProcessing = false;
      _scanning = true;
      setState(() {});
    }
    _syncCamera();
  }

  // ── Camera control ───────────────────────────────────────────────────────

  /// Single funnel for every camera transition. If called mid-transition the
  /// request is queued and re-run once the current transition completes.
  Future<void> _syncCamera() async {
    if (!mounted) return;
    if (_cameraBusy) {
      _cameraSyncQueued = true;
      return;
    }
    _cameraBusy = true;
    try {
      do {
        _cameraSyncQueued = false;
        if (_wantsCamera) {
          await _startCameraLocked();
        } else {
          await _stopCameraLocked();
        }
      } while (_cameraSyncQueued);
    } finally {
      _cameraBusy = false;
    }
  }

  Future<void> _startCameraLocked() async {
    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    if (status.isPermanentlyDenied || status.isRestricted) {
      _setPhase(_CameraPhase.permissionBlocked,
          detail:
              'Camera access is blocked for TigerBay Staff. Enable it from system settings.');
      return;
    }
    if (!status.isGranted) {
      _setPhase(_CameraPhase.failed,
          detail:
              'Camera permission was not granted. Tap Restart and choose Allow.');
      return;
    }

    final controller = _controller ??= _createController();
    if (!controller.value.isRunning || controller.value.error != null) {
      _setPhase(_CameraPhase.starting);
      try {
        await controller.start();
      } catch (e) {
        debugPrint('❌ [ScanHub] controller.start threw: $e');
      }
      if (!mounted) return;
      final error = controller.value.error;
      if (error != null) {
        _setPhase(_CameraPhase.failed, detail: _describeError(error));
        return;
      }
    }
    _setPhase(_CameraPhase.running);
  }

  Future<void> _stopCameraLocked() async {
    final controller = _controller;
    if (controller != null && controller.value.isRunning) {
      try {
        await controller.stop();
      } catch (e) {
        debugPrint('⚠️ [ScanHub] controller.stop failed: $e');
      }
    }
    _setPhase(_CameraPhase.idle);
  }

  /// Hard recovery. Order matters: the scanner WIDGET must fully unmount
  /// before the old controller is retired, because the mounted widget keeps
  /// using whatever controller it was constructed with.
  Future<void> _restartCamera() async {
    if (!mounted || _isProcessing) return;
    debugPrint('🔄 [ScanHub] Full scanner restart requested');
    _setPhase(_CameraPhase.idle);
    await WidgetsBinding.instance.endOfFrame;

    final old = _controller;
    _controller = null;
    if (old != null) {
      try {
        await old.stop();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _failureDetail = null;
      _scannerEpoch++;
      _controller = _createController();
    });
    await _syncCamera();
  }

  MobileScannerController _createController() {
    return MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  void _setPhase(_CameraPhase phase, {String? detail}) {
    if (!mounted) return;
    if (_phase == phase && _failureDetail == detail) return;
    setState(() {
      _phase = phase;
      _failureDetail = detail;
    });
  }

  String _describeError(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Camera permission was denied. Tap Restart and choose Allow.';
      case MobileScannerErrorCode.unsupported:
        return 'This device does not support barcode scanning.';
      case MobileScannerErrorCode.controllerAlreadyInitialized:
        return 'The scanner was already active. Tap Restart to recover.';
      case MobileScannerErrorCode.controllerDisposed:
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.genericError:
        final message = error.errorDetails?.message;
        final code = error.errorDetails?.code;
        if (message != null && message.isNotEmpty) return message;
        if (code != null && code.isNotEmpty) return 'Camera error: $code';
        return 'The camera could not be opened. It may be busy — close other '
            'camera apps, then tap Restart.';
    }
  }

  void _toggleTorch() {
    final controller = _controller;
    if (controller == null || !controller.value.isRunning) return;
    controller.toggleTorch().catchError((_) {});
  }

  // ── Scanning ─────────────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    // Synchronous guard FIRST — onDetect fires for every frame, so without
    // this bursts of frames trigger duplicate transactions.
    if (_isProcessing || !_scanning || !mounted) return;
    if (_phase != _CameraPhase.running) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.trim().isEmpty) return;
    _isProcessing = true;
    _handleScannedCode(code);
  }

  /// Resumes scanning after cancel/failure paths.
  void _resumeScanning() {
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _scanning = true;
    });
    _syncCamera();
  }

  String _parseScannedQr(String raw) {
    final trimmed = raw.trim();
    try {
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        // Customer app format: { "uid": "...", "code": "100001", ... }
        if (decoded.containsKey('code') &&
            decoded['code'] != null &&
            decoded['code'].toString().isNotEmpty) {
          return decoded['code'].toString();
        }
        if (decoded.containsKey('uid') &&
            decoded['uid'] != null &&
            decoded['uid'].toString().isNotEmpty) {
          return decoded['uid'].toString();
        }
      }
    } catch (_) {}
    return trimmed;
  }

  List<String> _parseScannedPrefs(String raw) {
    final trimmed = raw.trim();
    try {
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        if (decoded.containsKey('prefs') && decoded['prefs'] is List) {
          return (decoded['prefs'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _handleScannedCode(String rawCode) async {
    // Release the camera while we resolve/navigate — frees the hardware
    // immediately instead of holding it behind pushed screens.
    unawaited(_syncCamera());

    final memberCode = _parseScannedQr(rawCode);
    final scannedPrefs = _parseScannedPrefs(rawCode);
    final staffProvider = context.read<StaffProvider>();
    final allowed =
        _isIssue ? staffProvider.canIssuePoints : staffProvider.canRedeemVouchers;

    PermissionGuard.run(
      context,
      allowed: allowed,
      action: () async {
        if (_isIssue) {
          // Resolve the member FIRST so the billing page opens pre-filled
          // AND showing the customer's name for identity confirmation.
          Map<String, dynamic>? customer;
          try {
            customer = await _supabase.findCustomerByIdentifier(memberCode);
          } catch (e) {
            debugPrint('❌ [ScanHub] Member lookup failed: $e');
          }

          if (!mounted) return;
          if (customer == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'No TigerBay member found for "$memberCode". Ask them to show their QR again or check the code.'),
              backgroundColor: AppColors.danger,
            ));
            _resumeScanning();
            return;
          }

          final canonicalCode =
              (customer['member_code'] ?? '').toString().isNotEmpty
                  ? customer['member_code'].toString()
                  : memberCode;
          final memberName = (customer['full_name'] ??
                  customer['name'] ??
                  customer['email'] ??
                  'Member $canonicalCode')
              .toString();

          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StaffBillingPointScreen(
                  initialMemberCode: canonicalCode,
                  initialMemberName: memberName,
                  initialDiningPrefs: scannedPrefs,
                ),
              ),
            );
          }
          return;
        }

        // ── Redeem mode: resolve customer → pick reward → verify PIN. ──
        setState(() => _scanning = false);

        final staff = staffProvider.staff;
        if (staff == null) {
          _resumeScanning();
          return;
        }

        Map<String, dynamic>? customer;
        try {
          customer = await _supabase.findCustomerByIdentifier(memberCode);
        } catch (e) {
          debugPrint('❌ [ScanHub] Customer lookup failed: $e');
        }

        if (!mounted) return;
        if (customer == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'No TigerBay member found for "$memberCode". Ask them to show their QR again or check the code.'),
            backgroundColor: AppColors.danger,
          ));
          _resumeScanning();
          return;
        }

        final customerName = (customer['full_name'] ??
                customer['name'] ??
                customer['email'] ??
                'Member $memberCode')
            .toString();

        final selectedReward = await _showRewardPicker(customerName);
        if (!mounted) return;
        if (selectedReward == null) {
          _resumeScanning();
          return;
        }
        final rewardTitle =
            (selectedReward['title'] ?? 'Reward Redemption').toString();

        final verified =
            await PinVerificationModal.show(context, staffId: staff.id);
        if (!mounted) return;
        if (verified != true) {
          _resumeScanning();
          return;
        }

        final requiredStrips =
            (selectedReward['strips_cost'] as num?)?.toInt() ?? 0;
        try {
          if (requiredStrips <= 0) {
            throw Exception('Reward "$rewardTitle" has no valid strips cost.');
          }
          final client = Supabase.instance.client;
          final result = await client.rpc('redeem_strips_for_member', params: {
            'p_member_code': memberCode,
            'p_strips_cost': requiredStrips,
            'p_reward_title': rewardTitle,
            'p_staff_id': staff.id,
          });

          final map = Map<String, dynamic>.from(result as Map);
          if (map['ok'] != true) {
            final balance = (map['balance'] as num?)?.toInt() ?? 0;
            final needed = (map['required'] as num?)?.toInt() ?? requiredStrips;
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '$customerName only has $balance strips — "$rewardTitle" requires $needed.'),
              backgroundColor: AppColors.danger,
            ));
            _resumeScanning();
            return;
          }

          final remainingBalance = (map['balance'] as num?)?.toInt() ?? 0;
          debugPrint(
              '✅ [ScanHub] Redemption OK for $customerName — remaining strips: $remainingBalance');
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => RewardQrScreen(
                  redemptionId:
                      'redeem-${DateTime.now().millisecondsSinceEpoch}',
                  rewardTitle: rewardTitle,
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint('❌ [ScanHub] Redemption failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Redemption failed: $e'),
              backgroundColor: AppColors.danger,
            ));
            _resumeScanning();
          }
        }
      },
    );

    if (!allowed && mounted) {
      _resumeScanning();
    }
  }

  /// Bottom sheet listing all available rewards so staff can select what
  /// the scanned customer wants to redeem. Returns the chosen reward row
  /// (Map with at least `id`, `title`, `strips_cost`) or null on cancel.
  Future<Map<String, dynamic>?> _showRewardPicker(String customerName) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded, color: AppColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Select Reward to Redeem',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        const SizedBox(height: 2),
                        Text('Redeeming for: $customerName',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _supabase.getRewards(),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: CircularProgressIndicator(color: AppColors.gold)),
                    );
                  }
                  final rewards = snapshot.data ?? const [];
                  if (rewards.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No rewards configured.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetCtx).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: rewards.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFF26272C)),
                      itemBuilder: (ctx, i) {
                        final reward = rewards[i];
                        final points = reward['strips_cost'];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.goldPale,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.redeem_rounded,
                                color: AppColors.gold, size: 20),
                          ),
                          title: Text(
                            (reward['title'] ?? 'Unnamed reward').toString(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: points != null
                              ? Text('$points strips',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12))
                              : null,
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textSecondary),
                          onTap: () => Navigator.pop(sheetCtx, reward),
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetCtx, null),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      backgroundColor: AppColors.primaryBlack,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Only show a back button when this instance is actually a
                  // pushed route — the shell-tab instance would otherwise pop
                  // the entire RootShell out from under the other tabs.
                  if (canPop)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    const SizedBox(width: 48),
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
                    onPressed: _toggleTorch,
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
                      _buildScannerArea(),
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
                        Text(_statusTitle(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          _statusSubtitle(),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle,
                            size: 8,
                            color: _phase == _CameraPhase.failed ||
                                    _phase == _CameraPhase.permissionBlocked
                                ? AppColors.danger
                                : AppColors.success),
                        const SizedBox(width: 6),
                        Text(_statusBadgeLabel(),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
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

  String _statusTitle() {
    if (_isProcessing) return 'Processing...';
    switch (_phase) {
      case _CameraPhase.starting:
        return 'Starting camera…';
      case _CameraPhase.running:
        return 'Ready to Scan';
      case _CameraPhase.failed:
        return 'Camera unavailable';
      case _CameraPhase.permissionBlocked:
        return 'Camera blocked';
      case _CameraPhase.idle:
        return 'Camera paused';
    }
  }

  String _statusSubtitle() {
    if (_isProcessing) return 'Verifying transaction...';
    switch (_phase) {
      case _CameraPhase.starting:
        return 'Opening the scanner…';
      case _CameraPhase.running:
        return 'Waiting for customer to present code...';
      case _CameraPhase.failed:
        return _failureDetail ?? 'Tap restart to re-open the scanner.';
      case _CameraPhase.permissionBlocked:
        return 'Enable the camera permission from system settings.';
      case _CameraPhase.idle:
        return 'Waiting for customer to present code...';
    }
  }

  String _statusBadgeLabel() {
    if (_isProcessing) return 'busy';
    switch (_phase) {
      case _CameraPhase.running:
      case _CameraPhase.starting:
        return 'active';
      case _CameraPhase.failed:
      case _CameraPhase.permissionBlocked:
        return 'error';
      case _CameraPhase.idle:
        return 'paused';
    }
  }

  Widget _buildScannerArea() {
    if (_phase == _CameraPhase.permissionBlocked) {
      return _PermissionBlockedOverlay(onRetry: _restartCamera);
    }
    if (_phase == _CameraPhase.failed) {
      return _CameraFailedOverlay(detail: _failureDetail, onRetry: _restartCamera);
    }

    final controller = _controller;
    if (_wantsCamera && controller != null) {
      return MobileScanner(
        key: ValueKey('scanner-$_scannerEpoch'),
        controller: controller,
        onDetect: _onDetect,
        placeholderBuilder: (_, __) => const ColoredBox(
          color: AppColors.primaryBlack,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          ),
        ),
        errorBuilder: (context, error, child) => _CameraFailedOverlay(
          detail: _describeError(error),
          onRetry: _restartCamera,
        ),
      );
    }

    return ColoredBox(
      color: AppColors.primaryBlack,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner_rounded,
                color: Colors.white24, size: 44),
            const SizedBox(height: 12),
            Text(
              _isProcessing ? 'Processing transaction...' : 'Camera paused',
              style: const TextStyle(
                  color: Colors.white38, fontWeight: FontWeight.w600),
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
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '6-digit code, TB-xxxxxx or email',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (!_isProcessing && controller.text.trim().isNotEmpty) {
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

/// Full-bleed overlay shown when the camera can't start or has died.
/// Gives staff a visible way to recover instead of a silent black box.
class _CameraFailedOverlay extends StatelessWidget {
  final String? detail;
  final Future<void> Function() onRetry;

  const _CameraFailedOverlay({this.detail, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryBlack,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded,
                color: Colors.white54, size: 44),
            const SizedBox(height: 12),
            const Text(
              'Camera unavailable',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              detail ?? 'Tap restart to re-open the scanner.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Restart Camera'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the OS-level camera permission is permanently denied.
class _PermissionBlockedOverlay extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _PermissionBlockedOverlay({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryBlack,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: AppColors.warning, size: 44),
            const SizedBox(height: 12),
            const Text(
              'Camera permission needed',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'TigerBay Staff needs camera access to scan member QR codes.\n'
              'Enable it in Settings › Apps › TigerBay Staff › Permissions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => onRetry(),
              child: const Text('I have enabled it — check again',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
