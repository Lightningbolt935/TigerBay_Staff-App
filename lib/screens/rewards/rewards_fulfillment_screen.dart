import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/reward_redemption.dart';
import '../../providers/staff_provider.dart';
import '../../providers/reward_fulfillment_provider.dart';
import '../profile/staff_profile_screen.dart';

class RewardsFulfillmentScreen extends StatelessWidget {
  const RewardsFulfillmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RewardFulfillmentProvider()
        ..loadRedemptions()
        ..subscribeToRealtime(),
      child: const _RewardsFulfillmentView(),
    );
  }
}

class _RewardsFulfillmentView extends StatelessWidget {
  const _RewardsFulfillmentView();

  @override
  Widget build(BuildContext context) {
    final staffProvider = context.watch<StaffProvider>();
    final rewardsProvider = context.watch<RewardFulfillmentProvider>();
    final branch = staffProvider.branch;

    final pendingCount = rewardsProvider.pendingCount;
    final servedTodayCount = rewardsProvider.completedTodayCount;
    final activeFilter = rewardsProvider.activeFilter;
    final items = rewardsProvider.filteredRedemptions;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0B0E),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header Row ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rewards Fulfillment',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              branch?.name ?? 'TigerBay Lounge',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StaffProfileScreen(),
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 19,
                      backgroundColor: AppColors.goldPale,
                      child: Text(
                        Formatters.initials(staffProvider.staff?.name),
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Live Stats Counter Row ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  _statCol('$pendingCount', 'Pending Serve',
                      color: const Color(0xFFFFA726)),
                  _statCol('$servedTodayCount', 'Served Today',
                      color: const Color(0xFF66BB6A)),
                  _statCol('${rewardsProvider.allRedemptions.length}',
                      'Total Records',
                      color: AppColors.gold),
                  const Spacer(),
                  IconButton(
                    onPressed: () => rewardsProvider.loadRedemptions(),
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.gold, size: 22),
                    tooltip: 'Refresh Ledger',
                  ),
                ],
              ),
            ),

            // ── Segment Filter Chips ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _filterChip(
                    context,
                    label: 'Pending ($pendingCount)',
                    isSelected: activeFilter == 'pending',
                    onTap: () => rewardsProvider.setFilter('pending'),
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    context,
                    label: 'Served ($servedTodayCount)',
                    isSelected: activeFilter == 'completed',
                    onTap: () => rewardsProvider.setFilter('completed'),
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    context,
                    label: 'All History',
                    isSelected: activeFilter == 'all',
                    onTap: () => rewardsProvider.setFilter('all'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFF222026)),

            // ── Redemptions List ───────────────────────────────────────────
            Expanded(
              child: rewardsProvider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    )
                  : items.isEmpty
                      ? _emptyView(activeFilter)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          physics: const BouncingScrollPhysics(),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _RewardRedemptionCard(
                              redemption: item,
                              onMarkCompleted: () async {
                                final staffName = staffProvider.staff?.name ??
                                    staffProvider.staff?.staffId ??
                                    'Staff';
                                final ok =
                                    await rewardsProvider.markAsCompleted(
                                  redemptionId: item.id,
                                  staffNameOrId: staffName,
                                );
                                if (ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF1E2E1E),
                                      content: Text(
                                        'Marked "${item.rewardTitle}" as served',
                                        style: const TextStyle(
                                            color: Color(0xFF81C784)),
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              onRevert: () async {
                                await rewardsProvider.revertToPending(item.id);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCol(String value, String label, {required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.gold : const Color(0xFF19181E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.gold : const Color(0xFF2C2A34),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.black : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _emptyView(String filter) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF19181E),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF2C2A34)),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 38,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              filter == 'pending' ? 'All Rewards Served!' : 'No Records Found',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filter == 'pending'
                  ? 'No guest redemptions are currently awaiting fulfillment.'
                  : 'Redeemed member rewards will appear here automatically.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardRedemptionCard extends StatelessWidget {
  final RewardRedemption redemption;
  final VoidCallback onMarkCompleted;
  final VoidCallback onRevert;

  const _RewardRedemptionCard({
    required this.redemption,
    required this.onMarkCompleted,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = redemption.isPending;
    final timeStr = _formatTime(redemption.createdAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16151B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? AppColors.gold.withValues(alpha: 0.35)
              : const Color(0xFF24222B),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPending
                      ? AppColors.gold.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: isPending ? AppColors.gold : Colors.white60,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      redemption.rewardTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Redeemed for ${redemption.amount} Strips',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isPending
                      ? const Color(0xFF332009)
                      : const Color(0xFF132A15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPending
                        ? const Color(0xFFFF9800)
                        : const Color(0xFF4CAF50),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  isPending ? 'PENDING' : 'SERVED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isPending
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFF81C784),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF24222C)),
          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  redemption.customerName ??
                      'User ${redemption.userId.substring(0, redemption.userId.length.clamp(0, 8))}...',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.access_time_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                timeStr,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action Button
          if (isPending)
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onMarkCompleted,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text(
                  'MARK AS SERVED / COMPLETED',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6),
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  redemption.completedBy != null
                      ? 'Served by ${redemption.completedBy}'
                      : 'Fulfilled',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF81C784),
                      fontWeight: FontWeight.w500),
                ),
                TextButton(
                  onPressed: onRevert,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: const Text('Revert to pending',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
