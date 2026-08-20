import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/branch.dart';
import '../models/staff_member.dart';
import '../models/shift_log.dart';
import '../models/loyalty_transaction.dart';
import '../models/table_status.dart';
import 'secure_storage_service.dart';

/// Central HTTP client for the TigerBay backend (NOT Night Collins —
/// see NightCollinsService for that). Handles auth header injection
/// and typed (de)serialization for every model in the schema.
class ApiService {
  final Dio _dio;
  final SecureStorageService _secureStorage;

  ApiService({Dio? dio, SecureStorageService? secureStorage})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConstants.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              // ADDED: Supabase requires the apikey header for all requests
              headers: {
                'apikey': AppConstants.supabaseAnonKey,
                'Authorization': 'Bearer ${AppConstants.supabaseAnonKey}',
              },
            )),
        _secureStorage = secureStorage ?? SecureStorageService() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _secureStorage.getAuthToken();
        if (token != null) {
          // Upgrades the default Anon Key to the Staff JWT if logged in
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (DioException error, handler) {
        // Logs the error to console instead of silently failing
        debugPrint(
            '⚠️ ApiService DioException [${error.type}]: ${error.message}');
        handler.next(error);
      },
    ));
  }

  // ---- Auth ----
  Future<StaffMember> login(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final data = res.data as Map<String, dynamic>;
    await _secureStorage.saveAuthToken(data['token'] as String);
    return StaffMember.fromJson(data['staff'] as Map<String, dynamic>);
  }

  // ---- Branch ----
  Future<Branch?> getBranch(String branchId) async {
    try {
      final res = await _dio.get('/branches/$branchId');
      return Branch.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint('❌ getBranch failed: ${e.message}');
      return null;
    }
  }

  // ---- Staff ----
  Future<StaffMember?> getStaffMember(String staffId) async {
    try {
      final res = await _dio.get('/staff/$staffId');
      return StaffMember.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint('❌ getStaffMember failed: ${e.message}');
      return null;
    }
  }

  // ---- Shift logs ----
  Future<ShiftLog?> getActiveShift(String staffId) async {
    try {
      final res = await _dio.get('/shift-logs/active', queryParameters: {
        'staffId': staffId,
      });
      if (res.data == null) return null;
      return ShiftLog.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint(
          '⚠️ getActiveShift unreachable: ${e.message}. Treating as no active shift.');
      return null;
    }
  }

  Future<ShiftLog> checkIn({
    required String staffId,
    required String branchId,
    required double lat,
    required double lng,
    required String wifiBssid,
  }) async {
    final res = await _dio.post('/shift-logs/check-in', data: {
      'staffId': staffId,
      'branchId': branchId,
      'checkInLat': lat,
      'checkInLng': lng,
      'checkInWifiBssid': wifiBssid,
    });
    return ShiftLog.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ShiftLog> checkOut(String shiftLogId) async {
    final res = await _dio.post('/shift-logs/$shiftLogId/check-out');
    return ShiftLog.fromJson(res.data as Map<String, dynamic>);
  }

  // ---- Loyalty ----
  Future<LoyaltyTransaction> submitLoyaltyTransaction({
    required String staffId,
    required String customerId,
    required String branchId,
    required String transactionType,
    required int pointsStripesAmount,
    String? voucherCode,
    required bool pinVerified,
  }) async {
    final res = await _dio.post('/loyalty-transactions', data: {
      'staffId': staffId,
      'customerId': customerId,
      'branchId': branchId,
      'transactionType': transactionType,
      'pointsStripesAmount': pointsStripesAmount,
      'voucherCode': voucherCode,
      'pinVerified': pinVerified,
    });
    return LoyaltyTransaction.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<LoyaltyTransaction>> getRecentTransactions(String branchId,
      {int limit = 10}) async {
    try {
      final res = await _dio.get('/loyalty-transactions', queryParameters: {
        'branchId': branchId,
        'limit': limit,
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => LoyaltyTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      debugPrint('❌ getRecentTransactions failed: ${e.message}');
      return [];
    }
  }

  // ---- Tables ----
  Future<List<TableStatus>> getTableStatuses(String branchId) async {
    try {
      final res = await _dio.get('/tables-status', queryParameters: {
        'branchId': branchId,
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => TableStatus.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      debugPrint('❌ getTableStatuses failed: ${e.message}');
      return [];
    }
  }

  Future<TableStatus> updateTableStatus({
    required String tableId,
    required String status,
    required String updatedByStaffId,
  }) async {
    final res = await _dio.patch('/tables-status/$tableId', data: {
      'status': status,
      'lastUpdatedBy': updatedByStaffId,
    });
    return TableStatus.fromJson(res.data as Map<String, dynamic>);
  }
}
