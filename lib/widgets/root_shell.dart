import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/scan/scan_hub_screen.dart';
import '../screens/tables/table_control_screen.dart';
import 'session_device_guard.dart';

/// Bottom-tab shell matching the nav bars seen across the Attendance and
/// Table Control screenshots (Home / Attendance / Scan / Tables).
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  final _tabs = const [
    HomeScreen(),
    AttendanceScreen(),
    ScanHubScreen(mode: ScanMode.issue),
    TableControlScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return SessionDeviceGuard(
      child: Scaffold(
        body: IndexedStack(index: _index, children: _tabs),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.access_time_outlined), label: 'Attendance'),
            BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner_outlined), label: 'Scan'),
            BottomNavigationBarItem(icon: Icon(Icons.table_restaurant_outlined), label: 'Tables'),
          ],
        ),
      ),
    );
  }
}
