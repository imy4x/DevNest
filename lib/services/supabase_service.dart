import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/project.dart';
import '../models/bug.dart';
import '../models/ai_chat_message.dart';
import '../models/hub.dart';
import '../models/hub_member.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  GoTrueClient get auth => _client.auth;
  String? get currentUserId => auth.currentUser?.id;

  // --- Hub Functions ---

  String _generateSecretCode() {
    final random = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(Iterable.generate(
      8, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  // ✨ --- Modified to accept display name --- ✨
  Future<String> createHub(String name, String displayName) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final secretCode = _generateSecretCode();

    try {
      await _client.rpc('create_hub_and_add_leader', params: {
        'hub_name': name,
        'secret_code': secretCode,
      });

      // After the RPC creates the member, update their display name
      await _client
          .from('hub_members')
          .update({'display_name': displayName})
          .eq('user_id', currentUserId!);
      
      return secretCode;
    } catch (e) {
      debugPrint('Error creating hub: $e');
      throw Exception('Failed to create hub. There might be a server error.');
    }
  }

  // ✨ --- Modified to accept display name --- ✨
  Future<void> joinHub(String secretCode, String displayName) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final upperCaseSecretCode = secretCode.toUpperCase();

    final hubResponse = await _client
        .from('hubs')
        .select('id')
        .eq('secret_code', upperCaseSecretCode)
        .maybeSingle();

    if (hubResponse == null) {
      throw Exception('Hub not found with this secret code.');
    }
    final hubId = hubResponse['id'];

    // Check if user is already a member
     final existingMembership = await _client
        .from('hub_members')
        .select('id')
        .eq('hub_id', hubId)
        .eq('user_id', currentUserId!)
        .maybeSingle();

    if (existingMembership != null) {
      throw Exception('You are already a member of this hub.');
    }

    await _client.from('hub_members').insert({
      'hub_id': hubId,
      'user_id': currentUserId,
      'role': 'member',
      'display_name': displayName, // Add display name on join
    });
  }

  Future<Hub?> getHubForUser() async {
    if (currentUserId == null) return null;
    try {
      final response = await _client.rpc('get_user_hub');
      if (response is List && response.isNotEmpty) {
        return Hub.fromJson(response[0]);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting user hub: $e');
      return null;
    }
  }
  
  // ✨ --- New function to get a single member's info --- ✨
  Future<HubMember?> getMemberInfo(String hubId) async {
    if (currentUserId == null) return null;
    final response = await _client
        .from('hub_members')
        .select()
        .eq('hub_id', hubId)
        .eq('user_id', currentUserId!)
        .maybeSingle();
    
    return response != null ? HubMember.fromJson(response) : null;
  }

   Future<List<HubMember>> getHubMembers(String hubId) async {
    final response = await _client
      .from('hub_members')
      .select()
      .eq('hub_id', hubId);
    return response.map((json) => HubMember.fromJson(json)).toList();
  }

  // ✨ --- Real-time stream for the current user's membership --- ✨
  // NOTE: This function relies on Row Level Security (RLS) being enabled on the `hub_members` table.
  // The RLS policy should ensure that users can only SELECT their own membership row.
  Stream<HubMember?> getMyMembershipStream(String hubId) {
    return _client
        .from('hub_members')
        .stream(primaryKey: ['id'])
        // RLS handles filtering by the current user_id on the database side.
        // We only need to filter by the hub_id on the client stream.
        .eq('hub_id', hubId)
        .map((maps) {
          if (maps.isEmpty) {
            return null; // The user has been removed (kicked)
          }
          // Because of RLS, maps will contain at most one item: the user's own membership.
          return HubMember.fromJson(maps.first); // Return the member object
        });
  }

  Future<void> updateMemberPermissions({
    required int memberId, 
    required bool canAddBugs, 
    required bool canEditBugs,
    required bool canUseChat,
    required bool canManageProjects,
  }) async {
    await _client
      .from('hub_members')
      .update({
        'can_add_bugs': canAddBugs,
        'can_edit_bugs': canEditBugs,
        'can_use_chat': canUseChat,
        'can_manage_projects': canManageProjects,
      })
      .eq('id', memberId);
  }

  Future<void> updateMemberDisplayName({required int memberId, required String newName}) async {
    await _client
      .from('hub_members')
      .update({'display_name': newName})
      .eq('id', memberId);
  }

  Future<void> removeMember(int memberId) async {
    await _client
      .from('hub_members')
      .delete()
      .eq('id', memberId);
  }
  
  Future<void> deleteHub(String hubId) async {
     await _client.rpc('delete_hub', params: {
        'hub_id_to_delete': hubId,
      });
  }


  // --- Project and Bug Functions ---

  Future<List<Project>> getProjects() async {
    final hub = await getHubForUser();
    if (hub == null) return [];

    final response = await _client
      .from('projects')
      .select()
      .eq('hub_id', hub.id)
      .order('created_at', ascending: false);
      
    return response.map<Project>((json) => Project.fromJson(json)).toList();
  }
  
  Future<Project> addProject(Map<String, dynamic> projectData) async {
    final hub = await getHubForUser();
    if (hub == null) throw Exception('User must be in a Hub to create projects.');
    projectData['hub_id'] = hub.id;

    final response = await _client.from('projects').insert(projectData).select().single();
    return Project.fromJson(response);
  }

  Future<void> deleteProject(String projectId) async {
    await _client.from('projects').delete().eq('id', projectId);
  }

  Future<Project> updateProject(Map<String, dynamic> projectData) async {
    final projectId = projectData['id'];
    projectData.remove('id'); 

    final response = await _client
        .from('projects')
        .update(projectData)
        .eq('id', projectId)
        .select()
        .single();
        
    return Project.fromJson(response);
  }

  Future<List<Bug>> getBugsForProject(String projectId) async {
    final response = await _client
        .from('bugs')
        .select()
        .eq('project_id', projectId)
        .order('created_at', ascending: false);
    return response.map<Bug>((json) => Bug.fromJson(json)).toList();
  }

  Future<void> addBug(Map<String, dynamic> bugData) async {
    bugData['user_id'] = currentUserId;
    await _client.from('bugs').insert(bugData);
  }
  
  Future<void> updateBugStatus(String bugId, String status) async {
    await _client.from('bugs').update({'status': status}).eq('id', bugId);
  }
  
  Future<void> deleteBug(String bugId) async {
    await _client.from('bugs').delete().eq('id', bugId);
  }

  // --- AI Chat Functions ---

  Future<void> addChatMessage({ required String projectId, required String role, required String content }) async {
    if (currentUserId == null) throw Exception('User not signed in');
    await _client.from('ai_chat_messages').insert({
      'project_id': projectId, 'user_id': currentUserId, 'role': role, 'content': content,
    });
  }

  Stream<List<AiChatMessage>> getChatHistoryStream(String projectId) {
    return _client
        .from('ai_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('created_at', ascending: true)
        .map((maps) => maps.map((map) => AiChatMessage.fromJson(map)).toList());
  }
  
  Future<List<AiChatMessage>> getRecentChatHistory(String projectId, {int limit = 10}) async {
     final response = await _client
        .from('ai_chat_messages')
        .select()
        .eq('project_id', projectId)
        .order('created_at', ascending: false)
        .limit(limit);
      return response.map((map) => AiChatMessage.fromJson(map)).toList().reversed.toList();
  }

  // ✨ --- New function to clear chat history --- ✨
  Future<void> clearChatHistory(String projectId) async {
    await _client
      .from('ai_chat_messages')
      .delete()
      .eq('project_id', projectId);
  }
}

