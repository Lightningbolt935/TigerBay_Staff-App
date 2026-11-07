import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../providers/staff_provider.dart';
import '../attendance/attendance_screen.dart';
import '../bookings/branch_bookings_dashboard_screen.dart';
import '../bookings/collins_venue_mapper.dart';
import '../scan/scan_hub_screen.dart';
import '../rewards/rewards_fulfillment_screen.dart';
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
    final role = staffProvider.role;

    // ── Build Action Cards Strictly by Role Hierarchy ───────────
    final List<Widget> actionCards = [
      // 1. Bookings: Accessible to Concierge, Staff, Manager, Director
      _actionCard(
        context,
        icon: Icons.calendar_month_outlined,
        title: 'Bookings',
        subtitle: 'Live reservations',
        onTap: () {
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

      // 2. Scan & Redeem: Accessible to Staff, Manager, Director (Hidden for Concierge)
      if (staffProvider.canRedeemRewards)
        _actionCard(
          context,
          icon: Icons.card_giftcard_outlined,
          title: 'Scan & Redeem',
          subtitle: 'Claim rewards',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ScanHubScreen(mode: ScanMode.redeem),
            ),
          ),
        ),

      // 3. Scan & Issue (Award Points): Manager & Director only
      if (staffProvider.canAwardStrips)
        _actionCard(
          context,
          icon: Icons.qr_code_scanner_outlined,
          title: 'Scan & Issue',
          subtitle: 'Award points',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ScanHubScreen(mode: ScanMode.issue),
            ),
          ),
        ),

      // 4. Bill Points (Credit Strips): Manager & Director only
      if (staffProvider.canAwardStrips)
        _actionCard(
          context,
          icon: Icons.receipt_long_outlined,
          title: 'Bill Points',
          subtitle: 'Credit strips',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StaffBillingPointScreen(),
            ),
          ),
        ),

      // 5. Rewards Fulfillment Queue: Manager & Director only
      if (staffProvider.canAccessFulfillment)
        _actionCard(
          context,
          icon: Icons.inventory_2_outlined,
          title: 'Rewards',
          subtitle: 'Fulfill & serve',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RewardsFulfillmentScreen(),
            ),
          ),
        ),

      // 6. Shift Attendance: Available to all staff roles
      _actionCard(
        context,
        icon: Icons.access_time_outlined,
        title: 'Attendance',
        subtitle: 'Shift logs',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AttendanceScreen(),
          ),
        ),
      ),

      // 7. Leave Requests: Available to all staff roles
      _actionCard(
        context,
        icon: Icons.event_available_outlined,
        title: 'Leave',
        subtitle: 'Apply & track',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const StaffLeaveScreen(),
          ),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _topBar(context, branch?.name ?? 'TigerBay'),
            const SizedBox(height: 20),
            _welcomeCard(
              context,
              name: staff?.name ?? 'Staff',
              tier: role.label,
              branchName: branch?.name ?? '',
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.95,
              children: actionCards,
            ),
            const SizedBox(height: 24),
            _todaysActivity(staffProvider),
            const SizedBox(height: 24),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Recent Transactions",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                Text(
                  'See All',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
          child: const Icon(Icons.shield_outlined,
              color: AppColors.gold, size: 20),
        ),
        const SizedBox(width: 10),
        const Text(
          'TigerBay',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StaffProfileScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.goldPale,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              branchName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _welcomeCard(
    BuildContext context, {
    required String name,
    required String tier,
    required String branchName,
  }) {
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
                  child: Text(
                    Formatters.initials(name),
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back, $name',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.goldPale,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tier,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· $branchName Branch',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
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
                final roleLabel = sp.role.label;
                return Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$roleLabel · Shift active',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
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
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _todaysActivity(StaffProvider staffProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Activity",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (staffProvider.canAwardStrips) ...[
              const Expanded(
                  child: _StatTile(value: '—', label: 'Points Issued')),
              const SizedBox(width: 12),
            ],
            if (staffProvider.canRedeemRewards) ...[
              const Expanded(
                  child: _StatTile(value: '—', label: 'Redemptions')),
              const SizedBox(width: 12),
            ],
            if (staffProvider.canAccessFulfillment) ...[
              const Expanded(
                  child: _StatTile(value: 'Live', label: 'Rewards Queue')),
            ] else ...[
              const Expanded(
                  child: _StatTile(value: 'Active', label: 'Floor Status')),
            ],
          ],
        ),
      ],
    );
  }
}

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
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
