import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../providers/staff_provider.dart';
import '../attendance/attendance_screen.dart';
import '../bookings/branch_bookings_dashboard_screen.dart';
import '../bookings/collins_venue_mapper.dart';
import '../catalog/catalog_manager_screen.dart';
import '../scan/scan_hub_screen.dart';
import '../tables/table_control_screen.dart';
import '../profile/staff_profile_screen.dart';
import '../leave/staff_leave_screen.dart';
import '../billing/staff_billing_point_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final staffProvider = context.watch<StaffProvider>();
    final staff = staffProvider.staff;
    final branch = staffProvider.branch;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _topBar(context, branch?.name ?? 'TigerBay'),
            const SizedBox(height: 20),
            _welcomeCard(context, staff?.name ?? 'Staff', staff?.permissions.tierName ?? '—', branch?.name ?? ''),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.95,
              children: [
                _actionCard(
                  context,
                  icon: Icons.qr_code_scanner_outlined,
                  title: 'Scan & Issue',
                  subtitle: 'Award points',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ScanHubScreen(mode: ScanMode.issue))),
                ),
                _actionCard(
                  context,
                  icon: Icons.card_giftcard_outlined,
                  title: 'Scan & Redeem',
                  subtitle: 'Claim rewards',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ScanHubScreen(mode: ScanMode.redeem))),
                ),
                _actionCard(
                  context,
                  icon: Icons.table_restaurant_outlined,
                  title: 'Table Control',
                  subtitle: 'Manage floor',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const TableControlScreen())),
                ),
                _actionCard(
                  context,
                  icon: Icons.access_time_outlined,
                  title: 'Attendance',
                  subtitle: 'Shift logs',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const AttendanceScreen())),
                ),
                _actionCard(
                  context,
                  icon: Icons.calendar_month_outlined,
                  title: 'Bookings',
                  subtitle: 'Live reservations',
                  onTap: () {
                    // Use branch.name (e.g. "Kingsbury") as the lookup key —
                    // more reliable than the Collins venue ID string for getBranchNumericId.
                    final branchName = branch?.name ?? 'Kingsbury';
                    final branchId = CollinsVenueMapper.getBranchNumericId(branchName);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BranchBookingsDashboardScreen(
                          branchId: branchId,
                          branchName: branchName,
                        ),
                      ),
                    );
                  },
                ),
                _actionCard(
                  context,
                  icon: Icons.restaurant_menu_outlined,
                  title: 'Catalog',
                  subtitle: 'Manage items',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const CatalogManagerScreen())),
                ),
                _actionCard(
                  context,
                  icon: Icons.event_available_outlined,
                  title: 'Leave',
                  subtitle: 'Apply & track',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const StaffLeaveScreen())),
                ),
                _actionCard(
                  context,
                  icon: Icons.receipt_long_outlined,
                  title: 'Bill Points',
                  subtitle: 'Credit strips',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const StaffBillingPointScreen())),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _todaysActivity(),
            const SizedBox(height: 24),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Recent Transactions",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('See All', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            // Recent transactions list would be populated from
            // ApiService.getRecentTransactions(branch.id) via a provider.
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, String branchName) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryBlack,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.shield_outlined, color: AppColors.gold, size: 20),
        ),
        const SizedBox(width: 10),
        const Text('TigerBay', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const StaffProfileScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.goldPale,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(branchName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _welcomeCard(BuildContext context, String name, String tier, String branchName) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.goldPale,
                  child: Text(Formatters.initials(name),
                      style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back, $name',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.goldPale,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(tier, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          Text('· $branchName Branch',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Consumer<StaffProvider>(
              builder: (context, sp, _) {
                // Shift tracking via attendance system — display 'Active' when clocked in.
                // Full elapsed timer will be available once AttendanceProvider is wired.
                final role = sp.staff?.role ?? 'Staff';
                return Row(
                  children: [
                    const Icon(Icons.access_time, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text('$role · Shift active',
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.goldPale,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.gold),
              ),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _todaysActivity() {
    return Consumer<StaffProvider>(
      builder: (context, sp, _) {
        // Live shift stats — populated by AttendanceProvider once clocked in.
        // Shows '—' until real data is available, avoiding fake hardcoded numbers.
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's Activity",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatTile(value: '—', label: 'Points Issued')),
                SizedBox(width: 12),
                Expanded(child: _StatTile(value: '—', label: 'Redemptions')),
                SizedBox(width: 12),
                Expanded(child: _StatTile(value: '—', label: 'Table Updates')),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Extracted stat tile so it can be used inside a Consumer without Expanded context issues.
class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
