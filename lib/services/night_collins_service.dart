import 'package:dio/dio.dart';
import '../models/branch.dart';

/// Integration with the external Night Collins booking system.
/// Every call is scoped to a single [Branch] and authenticated using
/// that branch's own `nightCollinsBranchId` / `nightCollinsApiKey` —
/// these must always be read from the Branch record, never hardcoded,
/// so that each branch talks only to its own Night Collins account.
class NightCollinsService {
  final Dio _dio;

  NightCollinsService({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? 'https://api.nightcollins.example.com/v1',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ));

  Options _authOptions(Branch branch) => Options(headers: {
        'X-NC-Branch-Id': branch.nightCollinsBranchId,
        'Authorization': 'Bearer ${branch.nightCollinsApiKey}',
      });

  /// Fetches today's bookings for the given branch.
  Future<List<Map<String, dynamic>>> getBookings(Branch branch,
      {DateTime? date}) async {
    final res = await _dio.get(
      '/branches/${branch.nightCollinsBranchId}/bookings',
      queryParameters: {
        if (date != null) 'date': date.toIso8601String().split('T').first,
      },
      options: _authOptions(branch),
    );
    return List<Map<String, dynamic>>.from(res.data as List<dynamic>);
  }

  /// Alters an existing booking. Caller must have already verified
  /// `canAlterBooking` permission before invoking this.
  Future<Map<String, dynamic>> alterBooking({
    required Branch branch,
    required String bookingId,
    required Map<String, dynamic> changes,
  }) async {
    final res = await _dio.patch(
      '/branches/${branch.nightCollinsBranchId}/bookings/$bookingId',
      data: changes,
      options: _authOptions(branch),
    );
    return res.data as Map<String, dynamic>;
  }

  /// Syncs live table layout/status from Night Collins, if the branch
  /// uses Night Collins as the source of truth for table assignment.
  Future<List<Map<String, dynamic>>> getTableLayout(Branch branch) async {
    final res = await _dio.get(
      '/branches/${branch.nightCollinsBranchId}/tables',
      options: _authOptions(branch),
    );
    return List<Map<String, dynamic>>.from(res.data as List<dynamic>);
  }
}
