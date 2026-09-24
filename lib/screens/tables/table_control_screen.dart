import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../models/table_status.dart';
import '../../providers/staff_provider.dart';
import '../../providers/table_provider.dart';
import '../../widgets/permission_guard.dart';
import '../profile/staff_profile_screen.dart';

class TableControlScreen extends StatefulWidget {
  const TableControlScreen({super.key});

  @override
  State<TableControlScreen> createState() => _TableControlScreenState();
}

class _TableControlScreenState extends State<TableControlScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final staffProvider = context.read<StaffProvider>();
      final branch = staffProvider.branch;
      if (branch != null) {
        context.read<TableProvider>().loadTables(branch.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final staffProvider = context.watch<StaffProvider>();
    final tableProvider = context.watch<TableProvider>();
    final branch = staffProvider.branch;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Table Control',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(branch?.name ?? '—',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StaffProfileScreen()),
                    ),
                    child: CircleAvatar(
                      radius: 18,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  _statCol('${tableProvider.occupiedCount}', 'Occupied', color: AppColors.tableOccupiedText),
                  _statCol('${tableProvider.reservedCount}', 'Reserved', color: AppColors.tableReservedText),
                  _statCol('${tableProvider.tables.length}', 'Total Booked', color: AppColors.gold),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      if (branch != null) tableProvider.loadTables(branch.id);
                    },
                    icon: const Icon(Icons.refresh, size: 18, color: AppColors.gold),
                    label: const Text('Refresh', style: TextStyle(color: AppColors.gold)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tableProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : tableProvider.tables.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.border,
                                      width: 1,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.table_restaurant_outlined,
                                    size: 40,
                                    color: AppColors.gold,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'No Tables Booked',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Currently no tables are occupied or reserved. Tables will appear here when actually booked.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: tableProvider.tables.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 1.05,
                          ),
                          itemBuilder: (context, index) {
                            final table = tableProvider.tables[index];
                            return _TableCard(
                              table: table,
                              onTap: () => PermissionGuard.run(
                                context,
                                allowed: staffProvider.canOverrideTables,
                                action: () => _showStatusPicker(context, table, tableProvider, staffProvider),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCol(String value, String label, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color ?? AppColors.textPrimary)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  void _showStatusPicker(
    BuildContext context,
    TableStatus table,
    TableProvider tableProvider,
    StaffProvider staffProvider,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text('Update ${table.tableNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final status in [
              AppConstants.tableOccupied,
              AppConstants.tableUnavailable,
              AppConstants.tableAvailable,
            ])
              ListTile(
                title: Text(status == AppConstants.tableAvailable ? 'Mark Available (Release Table)' : status),
                trailing: table.status == status ? const Icon(Icons.check, color: AppColors.gold) : null,
                onTap: () {
                  Navigator.pop(context);
                  tableProvider.updateStatus(
                    tableId: table.id,
                    newStatus: status,
                    updatedByStaffId: staffProvider.staff?.id ?? 'staff',
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final TableStatus table;
  final VoidCallback onTap;

  const _TableCard({required this.table, required this.onTap});

  ({Color bg, Color fg}) get _colors {
    switch (table.status) {
      case AppConstants.tableAvailable:
        return (bg: AppColors.tableAvailable, fg: AppColors.tableAvailableText);
      case AppConstants.tableOccupied:
        return (bg: AppColors.tableOccupied, fg: AppColors.tableOccupiedText);
      default:
        return (bg: AppColors.tableReserved, fg: AppColors.tableReservedText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    table.tableNumber,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.fg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                table.status,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            if (table.guestName != null && table.guestName!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                table.guestName!,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('Seats ${table.seats}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                if (table.bookingTime != null && table.bookingTime!.trim().isNotEmpty) ...[
                  const Spacer(),
                  const Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(table.bookingTime!,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
