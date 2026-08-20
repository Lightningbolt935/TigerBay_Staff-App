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
                  _statCol('${tableProvider.availableCount}', 'Available'),
                  _statCol('${tableProvider.occupiedCount}', 'Occupied', color: AppColors.tableOccupiedText),
                  _statCol('${tableProvider.reservedCount}', 'Reserved', color: AppColors.tableReservedText),
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
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: tableProvider.tables.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 1.15,
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
              AppConstants.tableAvailable,
              AppConstants.tableOccupied,
              AppConstants.tableUnavailable,
            ])
              ListTile(
                title: Text(status),
                trailing: table.status == status ? const Icon(Icons.check, color: AppColors.gold) : null,
                onTap: () {
                  Navigator.pop(context);
                  tableProvider.updateStatus(
                    tableId: table.id,
                    newStatus: status,
                    updatedByStaffId: staffProvider.staff!.id,
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(table.tableNumber,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.fg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(table.status,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.people_outline, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('Seats ${table.seats}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
