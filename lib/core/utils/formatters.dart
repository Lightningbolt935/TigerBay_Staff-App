import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  /// Formats a [Duration] as HH:mm:ss, e.g. "02:14:36".
  static String hhmmss(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = two(d.inHours);
    final minutes = two(d.inMinutes.remainder(60));
    final seconds = two(d.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  /// Short human duration, e.g. "2h 14m" — used on dashboard/profile cards.
  static String shortDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours <= 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  static String time(DateTime dt) => DateFormat('h:mm a').format(dt);

  static String date(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);

  /// Returns up to 2 uppercase initials from [fullName].
  ///
  /// Null-safe: returns 'ST' (Staff fallback) if [fullName] is null/empty.
  /// Single-word names return the first two characters (or one if shorter).
  /// This prevents RangeError when substring(0, 1) is called on empty strings.
  static String initials(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return 'ST';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'ST';
    if (parts.length == 1) {
      final word = parts.first;
      if (word.isEmpty) return 'ST';
      // For single names, use first 2 chars if available, else 1.
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.substring(0, 1).toUpperCase();
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';
    final result = '$first$last'.toUpperCase();
    return result.isEmpty ? 'ST' : result;
  }
}
