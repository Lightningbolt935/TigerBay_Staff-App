import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'package:tigerbay_staff_app/providers/auth_provider.dart';
import 'providers/staff_provider.dart';
import 'providers/shift_provider.dart';
import 'providers/table_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/pin_lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
  );

  runApp(const TigerBayStaffApp());
}

/// Global route observer — lets screens react to being covered/uncovered
/// by pushed routes (e.g. pause the camera when Billing opens on top of
/// the scanner). Registered on MaterialApp below.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class TigerBayStaffApp extends StatelessWidget {
  const TigerBayStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, StaffProvider>(
          create: (ctx) => StaffProvider(
            authProvider: ctx.read<AuthProvider>(),
          ),
          update: (_, authProvider, previous) =>
              previous ?? StaffProvider(authProvider: authProvider),
        ),
        ChangeNotifierProvider(create: (_) => ShiftProvider()),
        ChangeNotifierProvider(create: (_) => TableProvider()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        navigatorObservers: [routeObserver],
        home: const AppRouter(),
      ),
    );
  }
}

/// Determines the initial screen based on whether a persisted session exists.
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _checked = false;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final authProvider = context.read<AuthProvider>();
    final restored = await authProvider.restoreSession();
    if (mounted) {
      setState(() {
        _hasSession = restored;
        _checked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _hasSession ? const PinLockScreen() : const LoginScreen();
  }
}
