import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Horizontal date selector strip: previous/next day arrows, a scrollable
/// row of nearby days, and a button to open a full date picker.
class BookingFilterBar extends StatelessWidget implements PreferredSizeWidget {
  const BookingFilterBar({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    this.daysWindow = 14,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  /// How many days before/after today to show in the scroll strip.
  final int daysWindow;

  @override
  Size get preferredSize => const Size.fromHeight(96);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _openDatePicker(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) onDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final days = List<DateTime>.generate(
      daysWindow * 2 + 1,
      (i) => DateTime(today.year, today.month, today.day)
          .add(Duration(days: i - daysWindow)),
    );

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () =>
                        onDateChanged(selectedDate.subtract(const Duration(days: 1))),
                  ),
                  Expanded(
                    child: Center(
                      child: TextButton.icon(
                        onPressed: () => _openDatePicker(context),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          DateFormat('EEEE, d MMM yyyy').format(selectedDate),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () =>
                        onDateChanged(selectedDate.add(const Duration(days: 1))),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final isSelected = _isSameDay(day, selectedDate);
                  final isToday = _isSameDay(day, today);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(
                        isToday ? 'Today' : DateFormat('E d').format(day),
                      ),
                      selected: isSelected,
                      onSelected: (_) => onDateChanged(day),
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
}
