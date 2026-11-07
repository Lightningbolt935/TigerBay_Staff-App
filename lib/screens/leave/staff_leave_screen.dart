import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/staff_provider.dart';
import '../../providers/auth_provider.dart';

/// Staff Leave Management screen.
///
/// Provides two tabs:
///  - **Apply Leave** – form to submit a new leave request.
///  - **Request History** – real-time stream of past requests for the
///    logged-in staff member.
class StaffLeaveScreen extends StatefulWidget {
  const StaffLeaveScreen({super.key});

  @override
  State<StaffLeaveScreen> createState() => _StaffLeaveScreenState();
}

class _StaffLeaveScreenState extends State<StaffLeaveScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  String _selectedLeaveType = 'Annual';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;

  static const List<String> _leaveTypes = [
    'Annual',
    'Casual',
    'Sick',
    'Emergency',
    'Unpaid',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  // ---- Submission -------------------------------------------------------

  Future<void> _submitLeaveRequest() async {
    final bool datesValid = _startDate != null && _endDate != null;
    if (!_formKey.currentState!.validate() || !datesValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select valid start and end dates.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final staff = context.read<StaffProvider>().staff ??
        context.read<AuthProvider>().staff;

    if (staff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staff session missing. Please log in again.'),
          backgroundColor: AppColors.danger,
        ),
      );
      setState(() => _isSubmitting = false);
      return;
    }

    try {
      final venueId = staff.venueId ?? staff.branchId;
      final client = Supabase.instance.client;
      final leaveType = _selectedLeaveType.toLowerCase();
      final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate!);
      final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate!);
      final reason = _reasonController.text.trim();

      bool submitted = false;

      // 1. Try RPC (SECURITY DEFINER — bypasses RLS)
      try {
        await client.rpc('insert_staff_leave_request', params: {
          'p_staff_id': staff.id,
          'p_venue_id': (venueId != null && venueId.isNotEmpty) ? venueId : null,
          'p_leave_type': leaveType,
          'p_start_date': startDateStr,
          'p_end_date': endDateStr,
          'p_reason': reason,
        });
        submitted = true;
        debugPrint('✅ [Leave] Submitted via RPC.');
      } catch (rpcErr) {
        debugPrint('⚠️ [Leave] RPC failed: $rpcErr');
      }

      // 2. Fallback: direct insert (works when RLS is disabled or policy allows)
      if (!submitted) {
        await client.from('staff_leave_requests').insert({
          'staff_id': staff.id,
          if (venueId != null && venueId.isNotEmpty) 'venue_id': venueId,
          'leave_type': leaveType,
          'start_date': startDateStr,
          'end_date': endDateStr,
          'reason': reason,
          'status': 'pending',
        });
        debugPrint('✅ [Leave] Submitted via direct insert.');
      }

      _reasonController.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: const Text('Leave request submitted successfully.'),
          ),
        );
        _tabController.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text('Error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---- Date pickers -----------------------------------------------------

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  // ---- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Management'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Apply Leave'),
            Tab(text: 'Request History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildApplyLeaveForm(),
          const _LeaveHistoryList(),
        ],
      ),
    );
  }

  Widget _buildApplyLeaveForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Info banner -------------------------------------------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.goldPale,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.gold, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Leave requests are subject to manager approval. '
                      'Allow 2–3 working days for a response.',
                      style: TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ---- Leave type --------------------------------------------
            _sectionLabel('Leave Type', Icons.category_outlined),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedLeaveType,
              decoration: const InputDecoration(hintText: 'Select Type'),
              items: _leaveTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedLeaveType = v!),
            ),
            const SizedBox(height: 20),

            // ---- Dates -------------------------------------------------
            _sectionLabel('Leave Period', Icons.date_range_outlined),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: _startDate == null
                        ? 'Start Date'
                        : DateFormat('dd MMM yyyy').format(_startDate!),
                    isSelected: _startDate != null,
                    onTap: _pickStartDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateButton(
                    label: _endDate == null
                        ? 'End Date'
                        : DateFormat('dd MMM yyyy').format(_endDate!),
                    isSelected: _endDate != null,
                    onTap: _pickEndDate,
                  ),
                ),
              ],
            ),

            // ---- Duration chip -----------------------------------------
            if (_startDate != null && _endDate != null) ...[
              const SizedBox(height: 12),
              _DurationChip(start: _startDate!, end: _endDate!),
            ],
            const SizedBox(height: 20),

            // ---- Reason ------------------------------------------------
            _sectionLabel('Reason', Icons.edit_note_outlined),
            const SizedBox(height: 8),
            TextFormField(
              controller: _reasonController,
              maxLines: 4,
              decoration: const InputDecoration(
                  hintText: 'Provide a detailed reason for your leave...'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter a reason' : null,
            ),
            const SizedBox(height: 28),

            // ---- Submit ------------------------------------------------
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitLeaveRequest,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('SUBMIT LEAVE REQUEST'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.gold),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Realtime History List
// ---------------------------------------------------------------------------

class _LeaveHistoryList extends StatelessWidget {
  const _LeaveHistoryList();

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<StaffProvider>().staff ??
        context.watch<AuthProvider>().staff;
    final staffId = staff?.id ?? '';

    if (staffId.isEmpty) {
      return const Center(
        child: Text(
          'Please sign in to view your leave requests.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('staff_leave_requests')
          .stream(primaryKey: ['id'])
          .eq('staff_id', staffId)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.gold));
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}',
                style: const TextStyle(color: AppColors.textSecondary)),
          );
        }

        final records = snapshot.data ?? [];

        if (records.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.event_busy_outlined,
                      size: 30, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                const Text('No leave requests yet.',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                const Text('Your submitted requests will appear here.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: records.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _LeaveHistoryCard(item: records[index]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// History card
// ---------------------------------------------------------------------------

class _LeaveHistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _LeaveHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final status = (item['status']?.toString() ?? 'pending').toLowerCase();

    Color badgeColor;
    Color badgeBg;
    IconData statusIcon;

    switch (status) {
      case 'approved':
        badgeColor = AppColors.success;
        badgeBg = AppColors.successBg;
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case 'rejected':
        badgeColor = AppColors.danger;
        badgeBg = AppColors.dangerBg;
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        badgeColor = AppColors.warning;
        badgeBg = AppColors.goldPale;
        statusIcon = Icons.hourglass_top_rounded;
    }

    final leaveType = (item['leave_type'] ?? 'Leave').toString().toUpperCase();
    final startDate = item['start_date']?.toString() ?? '—';
    final endDate = item['end_date']?.toString() ?? '—';
    final reason = item['reason']?.toString() ?? 'N/A';
    final rejectionReason = item['rejection_reason']?.toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.goldPale,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.beach_access_outlined,
                      size: 18, color: AppColors.gold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(leaveType,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: badgeColor),
                      const SizedBox(width: 4),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Dates
            Row(
              children: [
                const Icon(Icons.date_range_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '$startDate  →  $endDate',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Reason
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.edit_note_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(reason,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ),
              ],
            ),

            // Rejection note
            if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Rejection note: $rejectionReason',
                        style: const TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _DateButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _DateButton(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.calendar_today_outlined,
          size: 14,
          color: isSelected ? AppColors.gold : AppColors.textSecondary),
      label: Text(
        label,
        style: TextStyle(
            fontSize: 13,
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        side: BorderSide(color: isSelected ? AppColors.gold : AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  const _DurationChip({required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    final days = end.difference(start).inDays + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.goldPale,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            '$days day${days == 1 ? "" : "s"} selected',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
