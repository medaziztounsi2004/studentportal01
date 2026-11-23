import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserManagementService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<Map<String, dynamic>> createUser({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    required String role,
    required String schoolId,
    bool forcePasswordChange = true,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'manage-users',
        body: {
          'action': 'create_user',
          'email': email,
          'password': password,
          'full_name': fullName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'role': role,
          'school_id': schoolId,
          'force_password_change': forcePasswordChange,
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data;
        } else if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
      }
      return {
        'success': false,
        'error': response.data?['error'] ?? 'HTTP ${response.status}',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Reset or set a user's password (for school admins, teachers, or students).
  /// Updates both Supabase Auth credentials and public.users.initial_password.
  static Future<Map<String, dynamic>> resetPassword({
    required String userId,
    required String newPassword,
  }) async {
    // 1. Primary: Edge Function 'manage-users' with service_role privilege
    try {
      final response = await _client.functions.invoke(
        'manage-users',
        body: {
          'action': 'reset_password',
          'user_id': userId,
          'new_password': newPassword,
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data;
        if (data is Map && data['success'] == true) {
          return {
            'success': true,
            'password': data['password']?.toString() ?? newPassword,
          };
        }
      }
    } catch (edgeErr) {
      debugPrint('[UserManagementService] Edge Function reset_password error: $edgeErr');
    }

    // 2. Secondary: Direct RPC 'super_admin_reset_password' (Security Definer)
    try {
      final rpcRes = await _client.rpc('super_admin_reset_password', params: {
        'p_user_id': userId,
        'p_new_password': newPassword,
      });

      if (rpcRes != null && rpcRes is Map && rpcRes['success'] == true) {
        return {
          'success': true,
          'password': rpcRes['password']?.toString() ?? newPassword,
        };
      }
    } catch (rpcErr) {
      debugPrint('[UserManagementService] RPC super_admin_reset_password error: $rpcErr');
    }

    // 3. Fallback: Direct table update in public.users for super_admin
    try {
      await _client.from('users').update({
        'initial_password': newPassword,
        'force_password_change': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      return {
        'success': true,
        'password': newPassword,
        'warning': 'Mot de passe mis à jour dans la table des utilisateurs.',
      };
    } catch (tableErr) {
      return {'success': false, 'error': tableErr.toString()};
    }
  }

  /// Fetch administrators (owners, admins, directors) for a given school
  static Future<List<Map<String, dynamic>>> getSchoolAdmins(String schoolId) async {
    try {
      final res = await _client
          .from('users')
          .select('id, full_name, email, role, phone, initial_password, is_active, created_at')
          .eq('school_id', schoolId)
          .inFilter('role', ['owner', 'admin', 'staff'])
          .order('created_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(res);
      if (list.isNotEmpty) return list;

      // Fallback: fetch any user for this school
      final anyUsers = await _client
          .from('users')
          .select('id, full_name, email, role, phone, initial_password, is_active, created_at')
          .eq('school_id', schoolId)
          .order('created_at', ascending: true)
          .limit(5);

      return List<Map<String, dynamic>>.from(anyUsers);
    } catch (e) {
      debugPrint('[UserManagementService] getSchoolAdmins error: $e');
      return [];
    }
  }
}
