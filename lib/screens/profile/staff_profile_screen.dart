import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../providers/shift_provider.dart';
import '../../providers/staff_provider.dart';
import '../../widgets/device_change_modal.dart';

class StaffProfileScreen extends StatelessWidget {
  const StaffProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final staffProvider = context.watch<StaffProvider>();
    final shiftProvider = context.watch<ShiftProvider>();
    final staff = staffProvider.staff;
    final branch = staffProvider.branch;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Profile'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.settings_outlined)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.background,
                      child: Text(
                        Formatters.initials(staff?.name ?? ''),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(staff?.name ?? '—',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Center(
              child: Text(staff?.email ?? '—',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: AppColors.goldPale, borderRadius: BorderRadius.circular(20)),
                child: Text(staff?.permissions.tierName ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Current Shift', style: TextStyle(fontWeight: FontWeight.w700)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: shiftProvider.isClockedIn ? AppColors.successBg : AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            shiftProvider.isClockedIn ? 'ACTIVE' : 'OFF SHIFT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: shiftProvider.isClockedIn ? AppColors.success : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        _iconLabelValue(
                          Icons.access_time,
                          'Clocked In',
                          shiftProvider.activeShift != null
                              ? Formatters.time(shiftProvider.activeShift!.checkInTime)
                              : '—',
                        ),
                        const SizedBox(width: 24),
                        _iconLabelValue(
                          Icons.timer_outlined,
                          'Duration',
                          shiftProvider.isClockedIn
                              ? Formatters.shortDuration(shiftProvider.liveDuration)
                              : '—',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(branch?.name ?? '—', style: const TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Account Information', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    _infoRow(Icons.badge_outlined, 'Staff ID', staff?.staffId ?? '—'),
                    const Divider(height: 1),
                    _infoRow(Icons.apartment_outlined, 'Assigned Branch', branch?.name ?? '—'),
                    const Divider(height: 1),
                    _infoRow(Icons.event_available_outlined, 'Joined Date', '—'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Security', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.goldPale,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.smartphone_outlined, size: 18, color: AppColors.gold),
                      ),
                      title: const Text('Request Device Change',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: const Text('Switch to a new phone',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                      onTap: () => DeviceChangeModal.show(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.read<StaffProvider>().signOut(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.dangerBg),
                ),
                child: const Text('Sign Out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconLabelValue(IconData icon, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.goldPale, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.gold),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.goldPale, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.gold),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
