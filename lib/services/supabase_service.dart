import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff_member.dart';
import '../models/permission_check_result.dart';

/// Thin wrapper around [SupabaseClient] providing typed methods for
/// all Supabase RPC calls in the TigerBay Staff App.
class SupabaseService {
  final SupabaseClient _client;

  SupabaseService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Requests a one-time password (OTP) for the given [identifier].
  Future<void> requestOtp(String identifier) async {
    final cleanIdentifier = identifier.trim();
    final cleanEmail = cleanIdentifier.toLowerCase();
    if (kDebugMode) {
      print('🚀 Requesting OTP for identifier: "$cleanIdentifier"');
    }

    // 1. Try RPC request_staff_otp first
    try {
      await _client.rpc(
        'request_staff_otp',
        params: {'p_identifier': cleanIdentifier},
      );
      if (kDebugMode) {
        print('✅ request_staff_otp RPC succeeded for: $cleanIdentifier');
      }
      return;
    } catch (rpcErr) {
      if (kDebugMode) {
        print('⚠️ RPC request_staff_otp unavailable or failed ($rpcErr). Using direct table flow...');
      }
    }

    // 2. Direct DB flow: Validate staff in staff_members table
    Map<String, dynamic>? staffRow;
    try {
      final rows = await _client
          .from('staff_members')
          .select()
          .or('email.ilike.$cleanEmail,staff_id.eq.$cleanIdentifier,id.eq.$cleanIdentifier')
          .limit(1);

      if (rows.isNotEmpty) {
        staffRow = Map<String, dynamic>.from(rows.first);
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Query staff_members error: $e');
    }

    if (staffRow == null) {
      try {
        final rows = await _client
            .from('staff_members')
            .select()
            .ilike('email', cleanEmail)
            .limit(1);
        if (rows.isNotEmpty) staffRow = Map<String, dynamic>.from(rows.first);
      } catch (_) {}
    }

    if (staffRow == null) {
      throw Exception('No staff account found for "$cleanIdentifier". Please check and try again.');
    }

    final isActive = staffRow['is_active'] as bool? ?? true;
    if (!isActive) {
      throw Exception('This account has been deactivated. Please contact your Branch Manager.');
    }

    final staffId = (staffRow['staff_id'] ?? staffRow['id'] ?? '').toString();
    final email = (staffRow['email'] ?? cleanEmail).toString();
    final otp = (Random.secure().nextInt(900000) + 100000).toString();
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 15));

    // Insert OTP into staff_auth_otps
    try {
      await _client.from('staff_auth_otps').insert({
        'staff_id': staffId,
        'email': email,
        'otp': otp,
        'expires_at': expiresAt.toIso8601String(),
      });
      if (kDebugMode) {
        print('✅ OTP generated and stored in staff_auth_otps: $otp for $email (staff_id: $staffId)');
      }
    } catch (insertErr) {
      if (kDebugMode) print('❌ Failed inserting into staff_auth_otps: $insertErr');
      throw Exception('Failed to generate OTP: $insertErr');
    }
  }

  /// Verifies the OTP entered by the staff member against RPC or staff_auth_otps table.
  Future<StaffMember> verifyOtp(String identifier, String otpCode) async {
    final cleanIdentifier = identifier.trim();
    final cleanEmail = cleanIdentifier.toLowerCase();
    final cleanOtp = otpCode.trim();

    if (kDebugMode) {
      print('🚀 Verifying OTP for "$cleanIdentifier" (entered code: $cleanOtp)');
    }

    // 1. Try RPC verify_staff_otp first
    try {
      final response = await _client.rpc(
        'verify_staff_otp',
        params: {
          'p_identifier': cleanIdentifier,
          'p_otp_code': cleanOtp,
        },
      );

      if (response != null) {
        final data = Map<String, dynamic>.from(response as Map);
        final staffJson = data.containsKey('staff') && data['staff'] is Map
            ? Map<String, dynamic>.from(data['staff'] as Map)
            : data;
        return StaffMember.fromJson(staffJson);
      }
    } catch (rpcErr) {
      if (kDebugMode) {
        print('⚠️ RPC verify_staff_otp unavailable or failed ($rpcErr). Using direct table verification...');
      }
    }

    // 2. Direct DB verification against staff_auth_otps table
    List<Map<String, dynamic>> otpRows = [];
    try {
      final res = await _client
          .from('staff_auth_otps')
          .select()
          .or('email.ilike.$cleanEmail,staff_id.eq.$cleanIdentifier')
          .order('expires_at', ascending: false)
          .limit(10);
      otpRows = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      if (kDebugMode) print('⚠️ Query staff_auth_otps with .or failed ($e). Trying email query...');
      try {
        final res = await _client
            .from('staff_auth_otps')
            .select()
            .ilike('email', cleanEmail)
            .order('expires_at', ascending: false)
            .limit(10);
        otpRows = List<Map<String, dynamic>>.from(res);
      } catch (e2) {
        if (kDebugMode) print('⚠️ Query staff_auth_otps by email failed: $e2');
      }
    }

    if (otpRows.isEmpty) {
      try {
        final res = await _client
            .from('staff_auth_otps')
            .select()
            .eq('staff_id', cleanIdentifier)
            .order('expires_at', ascending: false)
            .limit(10);
        otpRows = List<Map<String, dynamic>>.from(res);
      } catch (_) {}
    }

    if (otpRows.isEmpty) {
      throw Exception('No OTP request found for this account. Please request a new code.');
    }

    final now = DateTime.now().toUtc();
    Map<String, dynamic>? matchingOtpRow;

    for (final row in otpRows) {
      final storedOtp = (row['otp'] ?? '').toString().trim();
      final expiresAtStr = row['expires_at']?.toString();
      DateTime? expiresAt;
      if (expiresAtStr != null) {
        expiresAt = DateTime.tryParse(expiresAtStr)?.toUtc();
      }

      if (storedOtp == cleanOtp) {
        // Allow up to 10 minutes grace for server/device clock drift
        if (expiresAt == null || expiresAt.add(const Duration(minutes: 10)).isAfter(now)) {
          matchingOtpRow = row;
          break;
        } else {
          throw Exception('This OTP has expired. Please request a new code.');
        }
      }
    }

    if (matchingOtpRow == null) {
      throw Exception('The verification code you entered is incorrect. Please try again.');
    }

    // 3. Fetch staff profile from staff_members
    final matchedStaffId = (matchingOtpRow['staff_id'] ?? '').toString();
    final matchedEmail = (matchingOtpRow['email'] ?? cleanEmail).toString();

    Map<String, dynamic>? staffRow;
    try {
      final rows = await _client
          .from('staff_members')
          .select()
          .or('email.ilike.$matchedEmail,staff_id.eq.$matchedStaffId,id.eq.$matchedStaffId')
          .limit(1);
      if (rows.isNotEmpty) staffRow = Map<String, dynamic>.from(rows.first);
    } catch (_) {
      try {
        final rows = await _client
            .from('staff_members')
            .select()
            .ilike('email', matchedEmail)
            .limit(1);
        if (rows.isNotEmpty) staffRow = Map<String, dynamic>.from(rows.first);
      } catch (_) {}
    }

    if (staffRow == null) {
      throw Exception('Staff member profile not found. Please contact your manager.');
    }

    final staff = StaffMember.fromJson(staffRow);
    if (!staff.isActive) {
      throw Exception('Your account has been deactivated. Contact your Branch Manager.');
    }

    if (kDebugMode) {
      print('✅ Staff authenticated successfully: ${staff.name} (${staff.email})');
    }

    return staff;
  }

  // ---------------------------------------------------------------------------
  // Live Permission Checks
  // ---------------------------------------------------------------------------

  /// Performs a real-time permission check against the database.
  Future<PermissionCheckResult> checkPermission({
    required String staffId,
    required String requiredPermission,
  }) async {
    try {
      final response = await _client.rpc(
        'check_staff_permission',
        params: {
          'p_staff_id': staffId,
          'p_required_permission': requiredPermission,
        },
      );

      if (response == null) {
        return PermissionCheckResult.fromJson({
          'is_permitted': false,
          'is_active': false,
        });
      }

      final data = Map<String, dynamic>.from(response as Map);
      return PermissionCheckResult.fromJson(data);
    } catch (e) {
      if (kDebugMode) {
        print('❌ PERMISSION CHECK FAILED ($requiredPermission): $e');
      }
      // Fail closed by default if network or database error occurs
      return PermissionCheckResult.fromJson({
        'is_permitted': false,
        'is_active': false,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Session Management
  // ---------------------------------------------------------------------------

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ---------------------------------------------------------------------------
  // Device Change Requests
  // ---------------------------------------------------------------------------

  /// Inserts a new device change request into `device_change_requests`.
  /// The admin team reviews pending requests to approve device unbinding.
  Future<void> requestDeviceChange({
    required String staffId,
    required String reason,
  }) async {
    try {
      await _client.from('device_change_requests').insert({
        'staff_id': staffId,
        'reason': reason.trim(),
        'status': 'pending',
        'requested_at': DateTime.now().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('❌ POSTGREST ERROR in requestDeviceChange: ${e.message}');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('❌ ERROR in requestDeviceChange: $e');
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Reward Redemptions
  // ---------------------------------------------------------------------------

  /// Inserts a new reward redemption row and returns the generated row ID.
  /// The ID is encoded into the QR code displayed to the customer.
  Future<String> insertRewardRedemption({
    required String rewardId,
    required String staffId,
    required String customerId,
  }) async {
    try {
      final response = await _client
          .from('reward_redemptions')
          .insert({
            'reward_id': rewardId,
            'staff_id': staffId,
            'customer_id': customerId,
            'redeemed_at': DateTime.now().toIso8601String(),
            'status': 'pending_scan',
          })
          .select('id')
          .single();

      return response['id'] as String;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('❌ POSTGREST ERROR in insertRewardRedemption: ${e.message}');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('❌ ERROR in insertRewardRedemption: $e');
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Catalog / Rewards Management  (table: dishes / rewards)
  // ---------------------------------------------------------------------------

  // ── Dishes ──────────────────────────────────────────────────────────────────

  /// Fetches all rows from the `dishes` table ordered by name.
  Future<List<Map<String, dynamic>>> getDishes() async {
    final response =
        await _client.from('dishes').select().order('name');
    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Inserts a new row into `dishes` and returns the created row.
  Future<Map<String, dynamic>> insertDish({
    required String name,
    required double price,
    required String description,
    String? imageUrl,
  }) async {
    final response = await _client
        .from('dishes')
        .insert({
          'name': name,
          'price': price,
          'description': description,
          if (imageUrl != null) 'image_url': imageUrl,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(response as Map);
  }

  /// Updates an existing `dishes` row by its bigint [id].
  Future<void> updateDish({
    required int id,
    required String name,
    required double price,
    required String description,
    String? imageUrl,
  }) async {
    await _client.from('dishes').update({
      'name': name,
      'price': price,
      'description': description,
      'image_url': imageUrl,
    }).eq('id', id);
  }

  /// Deletes a `dishes` row by its bigint [id].
  Future<void> deleteDish(int id) async {
    await _client.from('dishes').delete().eq('id', id);
  }

  // ── Rewards ─────────────────────────────────────────────────────────────────

  /// Fetches all rows from the `rewards` table ordered by points_required.
  Future<List<Map<String, dynamic>>> getRewards() async {
    final response = await _client
        .from('rewards')
        .select()
        .order('points_required');
    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Inserts a new row into `rewards` and returns the created row.
  Future<Map<String, dynamic>> insertReward({
    required String title,
    required int pointsRequired,
    required String description,
    String? imageUrl,
  }) async {
    final response = await _client
        .from('rewards')
        .insert({
          'title': title,
          'points_required': pointsRequired,
          'description': description,
          if (imageUrl != null) 'image_url': imageUrl,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(response as Map);
  }

  /// Updates an existing `rewards` row by its bigint [id].
  Future<void> updateReward({
    required int id,
    required String title,
    required int pointsRequired,
    required String description,
    String? imageUrl,
  }) async {
    await _client.from('rewards').update({
      'title': title,
      'points_required': pointsRequired,
      'description': description,
      'image_url': imageUrl,
    }).eq('id', id);
  }

  /// Deletes a `rewards` row by its bigint [id].
  Future<void> deleteReward(int id) async {
    await _client.from('rewards').delete().eq('id', id);
  }

  // ── Storage ─────────────────────────────────────────────────────────────────

  /// Uploads [bytes] to [bucket]/[path] and returns the public URL.
  /// Bucket `MENU`    → dishes images.
  /// Bucket `Rewards` → reward images.
  Future<String> uploadCatalogImage({
    required String bucket,
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final data = Uint8List.fromList(bytes);
    await _client.storage.from(bucket).uploadBinary(
          path,
          data,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }
}

