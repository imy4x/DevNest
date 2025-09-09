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

  Future<String> createHub(String name, String displayName) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final secretCode = _generateSecretCode();

    try {
      await _client
        .from('hub_members')
        .delete()
        .eq('user_id', currentUserId!);

      await _client.rpc('create_hub_and_add_leader', params: {
        'hub_name': name,
        'secret_code': secretCode,
        'leader_display_name': displayName,
      });

      await _client
        .from('hub_members')
        .update({
          'can_add_bugs': true,
          'can_edit_bugs': true,
          'can_use_chat': true,
          'can_manage_projects': true,
        })
        .eq('user_id', currentUserId!)
        .eq('role', 'leader'); 
      
      return secretCode;
    } catch (e) {
      debugPrint('Error creating hub: $e');
      throw Exception('Failed to create hub. A server error occurred.');
    }
  }
  
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

     final existingMembership = await _client
        .from('hub_members')
        .select('id')
        .eq('hub_id', hubId)
        .eq('user_id', currentUserId!)
        .maybeSingle();

    if (existingMembership != null) {
      throw Exception('You are already a member of this hub.');
    }

    await _client
        .from('hub_members')
        .delete()
        .eq('user_id', currentUserId!);

    await _client.from('hub_members').insert({
      'hub_id': hubId,
      'user_id': currentUserId,
      'role': 'member',
      'display_name': displayName,
    });
  }

  Future<Hub?> getHubForUser() async {
    if (currentUserId == null) return null;
    try {
      final memberResponse = await _client
          .from('hub_members')
          .select('hub_id')
          .eq('user_id', currentUserId!)
          .maybeSingle();

      if (memberResponse == null || memberResponse['hub_id'] == null) {
        return null;
      }

      final hubId = memberResponse['hub_id'];

      final hubResponse = await _client
          .from('hubs')
          .select()
          .eq('id', hubId)
          .single(); 

      return Hub.fromJson(hubResponse);

    } catch (e) {
      debugPrint('Error getting user hub info manually: $e');
      return null;
    }
  }
  
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
  
  Stream<List<Map<String, dynamic>>> getHubMembersStream(String hubId) {
    return _client
        .from('hub_members')
        .stream(primaryKey: ['id'])
        .eq('hub_id', hubId);
  }

  Stream<Hub?> getHubStream(String hubId) {
    return _client
        .from('hubs')
        .stream(primaryKey: ['id'])
        .eq('id', hubId)
        .map((listOfHubMaps) {
      if (listOfHubMaps.isEmpty) {
        return null; 
      }
      return Hub.fromJson(listOfHubMaps.first);
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
    final memberData = await _client
        .from('hub_members')
        .select('hub_id')
        .eq('id', memberId)
        .maybeSingle();

    if (memberData == null) {
      throw Exception('Member not found.');
    }
    final hubId = memberData['hub_id'];

    await _client
      .from('hub_members')
      .delete()
      .eq('id', memberId);

    final newSecretCode = _generateSecretCode();
    await _client
      .from('hubs')
      .update({'secret_code': newSecretCode})
      .eq('id', hubId);
  }
  
  // --- تعديل (2): إضافة دالة مغادرة الـ Hub ---
  Future<void> leaveHub(int memberId) async {
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

  Future<void> clearChatHistory(String projectId) async {
    await _client
      .from('ai_chat_messages')
      .delete()
      .eq('project_id', projectId);
  }
}
