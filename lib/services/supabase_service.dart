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
  // Authentication RPCs
  // ---------------------------------------------------------------------------

  /// Requests a one-time password (OTP) for the given [identifier].
  Future<void> requestOtp(String identifier) async {
    final cleanIdentifier = identifier.trim();
    if (kDebugMode) {
      print(
          '🚀 Calling RPC request_staff_otp with p_identifier: "$cleanIdentifier"');
    }

    try {
      await _client.rpc(
        'request_staff_otp',
        params: {'p_identifier': cleanIdentifier},
      );
      if (kDebugMode) {
        print('✅ request_staff_otp succeeded for: $cleanIdentifier');
      }
    } on PostgrestException catch (e, stack) {
      if (kDebugMode) {
        print('❌ POSTGREST ERROR in requestOtp:');
        print('   Message: ${e.message}');
        print('   Code:    ${e.code}');
        print('   Details: ${e.details}');
        print('   Hint:    ${e.hint}');
        print(stack);
      }
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        print('❌ UNEXPECTED ERROR in requestOtp: $e');
        print(stack);
      }
      rethrow;
    }
  }

  /// Verifies the OTP entered by the staff member.
  Future<StaffMember> verifyOtp(String identifier, String otpCode) async {
    final cleanIdentifier = identifier.trim();
    final cleanOtp = otpCode.trim();

    if (kDebugMode) {
      print('🚀 Calling RPC verify_staff_otp for: $cleanIdentifier');
    }

    try {
      final response = await _client.rpc(
        'verify_staff_otp',
        params: {
          'p_identifier': cleanIdentifier,
          'p_otp_code': cleanOtp,
        },
      );

      if (response == null) {
        throw const PostgrestException(
          message: 'Received null response from verify_staff_otp',
        );
      }

      final data = Map<String, dynamic>.from(response as Map);

      // The RPC may return the staff record directly or nested under "staff".
      final staffJson = data.containsKey('staff') && data['staff'] is Map
          ? Map<String, dynamic>.from(data['staff'] as Map)
          : data;

      return StaffMember.fromJson(staffJson);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('❌ POSTGREST ERROR in verifyOtp: ${e.message} (Code: ${e.code})');
      }
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        print('❌ UNEXPECTED ERROR in verifyOtp: $e');
        print(stack);
      }
      rethrow;
    }
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

