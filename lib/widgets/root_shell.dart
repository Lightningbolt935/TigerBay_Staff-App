import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/scan/scan_hub_screen.dart';
import '../screens/rewards/rewards_fulfillment_screen.dart';
import 'session_device_guard.dart';

/// Bottom-tab shell (Home / Attendance / Scan / Rewards).
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return SessionDeviceGuard(
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            const HomeScreen(),
            const AttendanceScreen(),
            // `visible` tells the scanner whether its tab is on-screen —
            // the camera must NOT hold the hardware while another tab is active.
            ScanHubScreen(mode: ScanMode.issue, visible: _index == 2),
            const RewardsFulfillmentScreen(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFD4AF37), // AppColors.gold
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.access_time_outlined),
              activeIcon: Icon(Icons.access_time_filled),
              label: 'Attendance',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner_outlined),
              activeIcon: Icon(Icons.qr_code_scanner),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2),
              label: 'Rewards',
            ),
          ],
        ),
      ),
    );
  }
}
