import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/staff_provider.dart';
import 'collins_venue_mapper.dart';

/// Renders the per-venue Access Collins (DesignMyNight) booking widget
/// inside a [WebViewController].
///
/// Key behaviours:
/// - Loads the correct booking URL for the staff member's assigned branch.
/// - Intercepts navigation: Stripe / 3DS bank redirects are allowed through;
///   booking confirmation pages (booking-confirmed / thank-you) are
///   intercepted to show an in-app success screen.
/// - Pre-fills the staff member's name and email via JavaScript injection
///   once the page finishes loading.
class CollinsWebViewScreen extends StatefulWidget {
  const CollinsWebViewScreen({super.key});

  @override
  State<CollinsWebViewScreen> createState() => _CollinsWebViewScreenState();
}

class _CollinsWebViewScreenState extends State<CollinsWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _bookingConfirmed = false;
  String? _errorMessage;

  /// Domains/paths we must allow through without interception.
  static const _allowedPassThroughDomains = [
    'stripe.com',
    'stripe.network',
    'js.stripe.com',
    '3ds',           // 3D Secure redirects
    'checkout.stripe.com',
  ];

  /// URL patterns that indicate a completed booking.
  static const _confirmationPatterns = [
    'booking-confirmed',
    'thank-you',
    'confirmation',
    'booking_confirmed',
  ];

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    final staffProvider = context.read<StaffProvider>();
    final branch = staffProvider.branch;
    final staff = staffProvider.staff;

    final loadUrl = branch != null
        ? CollinsVenueMapper.widgetUrlFor(branch.name)
        : CollinsVenueMapper.widgetUrlFor('Kingsbury'); // safe fallback

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _isLoading = false);
            // Pre-fill staff details via JS injection.
            if (staff != null) {
              _injectStaffDetails(
                name: staff.name,
                email: staff.email,
              );
            }
          },
          onWebResourceError: (error) {
            // Only surface a full-screen error when the MAIN page itself
            // fails. Sub-resource failures (ads/analytics/fonts/scripts on
            // the DesignMyNight page) must NOT blank the whole screen —
            // the widget usually renders fine without them.
            bool isMainFrame = false;
            try {
              isMainFrame = error.isForMainFrame ?? _isLoading;
            } catch (_) {
              // Not exposed on all platforms; fall back to treating the
              // error as fatal only when the page hasn't finished loading.
              isMainFrame = _isLoading;
            }
            debugPrint(
              '🌐 [CollinsWebView] resource error '
              '(mainFrame=$isMainFrame, code=${error.errorCode}): '
              '${error.description} @ ${error.url ?? 'unknown url'}',
            );
            if (!isMainFrame || !mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = 'Unable to load booking page. Check your connection.';
            });
          },
          onNavigationRequest: (request) {
            final url = request.url.toLowerCase();

            // Always allow the main widget domain.
            if (url.contains('widgets.designmynight.com') ||
                url.contains('designmynight.com')) {
              return NavigationDecision.navigate;
            }

            // Allow Stripe and 3DS bank redirects.
            for (final domain in _allowedPassThroughDomains) {
              if (url.contains(domain)) {
                return NavigationDecision.navigate;
              }
            }

            // Intercept booking confirmation pages.
            for (final pattern in _confirmationPatterns) {
              if (url.contains(pattern)) {
                _onBookingConfirmed();
                return NavigationDecision.prevent;
              }
            }

            // Allow all other navigation by default.
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(loadUrl));
  }

  /// Injects JS to pre-fill name and email fields once the page loads.
  Future<void> _injectStaffDetails({
    required String name,
    required String email,
  }) async {
    const js = r'''
      (function() {
        // Common DesignMyNight field selectors
        const nameField = document.querySelector('input[name="name"], input[placeholder*="name" i], input[id*="name" i]');
        const emailField = document.querySelector('input[name="email"], input[type="email"], input[placeholder*="email" i]');
        if (nameField && !nameField.value) nameField.value = '$NAME';
        if (emailField && !emailField.value) emailField.value = '$EMAIL';
      })();
    ''';

    final script = js
        .replaceAll('\$NAME', name.replaceAll("'", "\\'"))
        .replaceAll('\$EMAIL', email.replaceAll("'", "\\'"));

    try {
      await _controller.runJavaScript(script);
    } catch (_) {
      // Non-fatal � page may not have those fields.
    }
  }

  void _onBookingConfirmed() {
    if (mounted) setState(() => _bookingConfirmed = true);
  }

  @override
  Widget build(BuildContext context) {
    final branch = context.watch<StaffProvider>().branch;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(branch?.name != null ? '${branch!.name} Bookings' : 'Bookings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _bookingConfirmed = false;
              });
              _controller.reload();
            },
          ),
        ],
      ),
      body: _bookingConfirmed
          ? _BookingSuccessView(
              onDone: () => Navigator.of(context).pop(),
              onViewAnother: () {
                setState(() => _bookingConfirmed = false);
                _controller.reload();
              },
            )
          : Stack(
              children: [
                if (_errorMessage != null)
                  _ErrorView(
                    message: _errorMessage!,
                    onRetry: () {
                      setState(() => _errorMessage = null);
                      _controller.reload();
                    },
                  )
                else
                  WebViewWidget(controller: _controller),
                if (_isLoading && _errorMessage == null)
                  const LinearProgressIndicator(
                    minHeight: 3,
                    valueColor: AlwaysStoppedAnimation(AppColors.gold),
                    backgroundColor: AppColors.goldPale,
                  ),
              ],
            ),
    );
  }
}

// =============================================================================
// Booking Success View
// =============================================================================

class _BookingSuccessView extends StatelessWidget {
  final VoidCallback onDone;
  final VoidCallback onViewAnother;

  const _BookingSuccessView({required this.onDone, required this.onViewAnother});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.successBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.success, size: 40),
            ),
            const SizedBox(height: 24),
            const Text('Booking Confirmed!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text(
              'The booking has been successfully placed. '
              'The customer will receive a confirmation email shortly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDone,
                child: const Text('Done'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onViewAnother,
                child: const Text('Make Another Booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Error View
// =============================================================================

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 20),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
