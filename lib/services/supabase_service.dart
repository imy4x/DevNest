import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../models/project.dart';
import '../models/bug.dart';
import '../models/ai_chat_message.dart';
import '../models/hub.dart';
import '../models/hub_member.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  GoTrueClient get auth => _client.auth;
  String? get currentUserId => auth.currentUser?.id;

  bool isUserAnonymous() {
    return auth.currentUser?.isAnonymous ?? true;
  }

  Future<void> linkAnonymousUser({required String email, required String password}) async {
    if (!isUserAnonymous()) throw Exception("User is not anonymous.");
    await auth.updateUser(
      UserAttributes(
        email: email,
        password: password,
      ),
    );
  }

  Future<void> signOut() async {
    await auth.signOut();
    await auth.signInAnonymously();
  }
  
  void _callNotifyFunction(
    String functionName, Map<String, dynamic> params) {
    try {
      debugPrint('📤 Firing notification: $functionName with params: $params');
      _client.functions.invoke(
        'notify',
        body: {
          'function_name': functionName,
          'params': params,
        },
      ).then((response) {
        debugPrint('✅ Notify function completed: ${response.data}');
      }).catchError((e, st) {
        debugPrint('❌ Background notification failed for $functionName: $e');
        debugPrintStack(stackTrace: st);
      });
    } catch (e) {
      debugPrint('❌ Failed to invoke notification function for $functionName: $e');
    }
  }

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
      await _client.from('hub_members').delete().eq('user_id', currentUserId!);
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
            'can_use_ai_audit': true,
            'can_send_broadcasts': true,
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
    final normalizedCode = secretCode.trim();
    final hubRes = await _client.from('hubs').select('id').ilike('secret_code', normalizedCode).maybeSingle();
    if (hubRes == null) throw Exception('Hub not found with this secret code.');
    final hubId = hubRes['id'];
    if (hubId == null) throw Exception('Unexpected error: Hub ID not found.');
    final memberRes = await _client.from('hub_members').select('id').eq('hub_id', hubId).eq('user_id', currentUserId!).maybeSingle();
    if (memberRes != null) throw Exception('You are already a member of this hub.');
    await _client.from('hub_members').delete().eq('user_id', currentUserId!);
    await _client.from('hub_members').insert({
      'hub_id': hubId,
      'user_id': currentUserId,
      'role': 'member',
      'display_name': displayName.trim(),
      'can_add_bugs': true,
      'can_edit_bugs': false,
      'can_use_chat': true,
      'can_manage_projects': false,
      'can_use_ai_audit': false,
      'can_send_broadcasts': false,
    });
  }

  Future<Hub?> getHubForUser() async {
    if (currentUserId == null) return null;
    try {
      final memberResponse = await _client.from('hub_members').select('hub_id').eq('user_id', currentUserId!).maybeSingle();
      if (memberResponse == null || memberResponse['hub_id'] == null) return null;
      final hubId = memberResponse['hub_id'];
      final hubResponse = await _client.from('hubs').select().eq('id', hubId).single();
      return Hub.fromJson(hubResponse);
    } catch (e) {
      debugPrint('Error getting user hub info manually: $e');
      return null;
    }
  }

  Future<HubMember?> getMemberInfo(String hubId) async {
    if (currentUserId == null) return null;
    final response = await _client.from('hub_members').select().eq('hub_id', hubId).eq('user_id', currentUserId!).maybeSingle();
    return response != null ? HubMember.fromJson(response) : null;
  }

  Future<List<HubMember>> getHubMembers(String hubId) async {
    final response = await _client.from('hub_members').select().eq('hub_id', hubId);
    return response.map((json) => HubMember.fromJson(json)).toList();
  }

  Stream<List<Map<String, dynamic>>> getHubMembersStream(String hubId) {
    return _client.from('hub_members').stream(primaryKey: ['id']).eq('hub_id', hubId);
  }

  Stream<Hub?> getHubStream(String hubId) {
    return _client.from('hubs').stream(primaryKey: ['id']).eq('id', hubId).map((listOfHubMaps) {
      if (listOfHubMaps.isEmpty) return null;
      return Hub.fromJson(listOfHubMaps.first);
    });
  }

  Future<void> updateMemberPermissions({
    required int memberId,
    required bool canAddBugs,
    required bool canEditBugs,
    required bool canUseChat,
    required bool canManageProjects,
    required bool canUseAiAudit,
    required bool canSendBroadcasts,
  }) async {
    await _client.from('hub_members').update({
          'can_add_bugs': canAddBugs,
          'can_edit_bugs': canEditBugs,
          'can_use_chat': canUseChat,
          'can_manage_projects': canManageProjects,
          'can_use_ai_audit': canUseAiAudit,
          'can_send_broadcasts': canSendBroadcasts,
        }).eq('id', memberId);
    _callNotifyFunction('notify_permissions_update', {'member_id': memberId});
  }

  Future<void> updateMemberDisplayName({required int memberId, required String newName}) async {
    await _client.from('hub_members').update({'display_name': newName}).eq('id', memberId);
  }

  Future<void> removeMember(int memberId) async {
    final memberData = await _client.from('hub_members').select('hub_id, display_name').eq('id', memberId).single();
    if (memberData == null) throw Exception('Member not found');
    
    _callNotifyFunction('notify_member_kicked', {
        'hub_id': memberData['hub_id'],
        'kicked_member_name': memberData['display_name'] ?? 'عضو غير مسمى'
    });

    await _client.from('hub_members').delete().eq('id', memberId);
    
    final hubId = memberData['hub_id'];
    final newSecretCode = _generateSecretCode();
    await _client.from('hubs').update({'secret_code': newSecretCode}).eq('id', hubId);
  }
  
  Future<void> leaveHub(int memberId) async {
    final memberData = await _client.from('hub_members').select('hub_id, display_name').eq('id', memberId).single();
    final hubId = memberData['hub_id'];
    final senderName = memberData['display_name'];
    _callNotifyFunction('notify_member_left', {'hub_id': hubId, 'sender_name': senderName});
    await _client.from('hub_members').delete().eq('id', memberId);
  }

  Future<void> deleteHub(String hubId) async {
    await _client.rpc('delete_hub', params: {'hub_id_to_delete': hubId});
  }
  
  Future<List<Project>> getProjects() async {
    final hub = await getHubForUser();
    if (hub == null) return [];
    final response = await _client.from('projects').select().eq('hub_id', hub.id).order('created_at', ascending: false);
    return response.map<Project>((json) => Project.fromJson(json)).toList();
  }

  Future<Project> addProject(Map<String, dynamic> projectData) async {
    final hub = await getHubForUser();
    if (hub == null) throw Exception('User must be in a Hub to create projects.');
    projectData['hub_id'] = hub.id;
    final response = await _client.from('projects').insert(projectData).select().single();
    _callNotifyFunction('notify_new_project', {'project_id': response['id']});
    return Project.fromJson(response);
  }

  Future<void> deleteProject(String projectId) async {
    final projectData = await _client.from('projects').select('name').eq('id', projectId).maybeSingle();
    final projectName = projectData?['name'] ?? 'غير مسمى';
    await _client.from('projects').delete().eq('id', projectId);
    _callNotifyFunction('notify_project_deleted', {'project_name': projectName});
  }

  Future<Project> updateProject(Map<String, dynamic> projectData) async {
    final projectId = projectData['id'];
    projectData.remove('id');
    final response = await _client.from('projects').update(projectData).eq('id', projectId).select().single();
    _callNotifyFunction('notify_project_update', {'project_id': projectId});
    return Project.fromJson(response);
  }

  Future<List<Bug>> getBugsForProject(String projectId) async {
    if (currentUserId == null) return [];
    final bugsResponse = await _client.from('bugs').select().eq('project_id', projectId).order('created_at', ascending: false);
    final prioritiesResponse = await _client.from('user_bug_priorities').select('bug_id, priority').eq('user_id', currentUserId!);
    final prioritiesMap = { for (var item in prioritiesResponse) item['bug_id']: item['priority'] };
    return bugsResponse.map<Bug>((json) {
      final bug = Bug.fromJson(json);
      bug.userPriority = prioritiesMap[bug.id];
      return bug;
    }).toList();
  }

  Future<void> setBugPriority(String bugId, int priority) async {
    if (currentUserId == null) return;
    await _client.from('user_bug_priorities').upsert({
      'user_id': currentUserId!,
      'bug_id': bugId,
      'priority': priority,
    }, onConflict: 'user_id, bug_id');
  }

  Future<void> clearBugPriority(String bugId) async {
     if (currentUserId == null) return;
     await _client.from('user_bug_priorities').delete().eq('user_id', currentUserId!).eq('bug_id', bugId);
  }

  Future<void> addBug(Map<String, dynamic> bugData) async {
    bugData['user_id'] = currentUserId;
    if (bugData['source'] == null) bugData['source'] = 'manual';
    final response = await _client.from('bugs').insert(bugData).select().single();
    _callNotifyFunction('notify_new_bug', {'bug_id': response['id']});
  }

  Future<void> updateBug(String bugId, Map<String, dynamic> bugData) async {
    await _client.from('bugs').update(bugData).eq('id', bugId);
    _callNotifyFunction('notify_bug_update', {'bug_id': bugId});
  }

  Future<void> updateBugStatus(String bugId, String status) async {
    await _client.from('bugs').update({'status': status}).eq('id', bugId);
    _callNotifyFunction('notify_bug_update', {'bug_id': bugId});
  }
  
  Future<void> deleteBug(String bugId) async {
    final bugData = await _client.from('bugs').select('title, projects(name)').eq('id', bugId).maybeSingle();
    final bugTitle = bugData?['title'] ?? 'غير مسمى';
    final projectName = bugData?['projects']?['name'] ?? 'مشروع غير معروف';
    await _client.from('bugs').delete().eq('id', bugId);
    _callNotifyFunction('notify_bug_deleted', {'bug_title': bugTitle, 'project_name': projectName});
  }

   Future<void> addChatMessage({required String projectId, required String role, required String content}) async {
    if (currentUserId == null) throw Exception('User not signed in');
    await _client.from('ai_chat_messages').insert({'project_id': projectId, 'user_id': currentUserId, 'role': role, 'content': content});
    if (role == 'user') {
      _callNotifyFunction('notify_new_chat_message', {'project_id': projectId, 'message': content});
    }
  }

  Stream<List<AiChatMessage>> getChatHistoryStream(String projectId) {
    return _client.from('ai_chat_messages').stream(primaryKey: ['id']).eq('project_id', projectId).order('created_at', ascending: true).map((maps) => maps.map((map) => AiChatMessage.fromJson(map)).toList());
  }

  Future<List<AiChatMessage>> getRecentChatHistory(String projectId, {int limit = 15}) async {
    final response = await _client.from('ai_chat_messages').select().eq('project_id', projectId).order('created_at', ascending: false).limit(limit);
    return response.map((map) => AiChatMessage.fromJson(map)).toList().reversed.toList();
  }

  Future<void> clearChatHistory(String projectId) async {
    await _client.from('ai_chat_messages').delete().eq('project_id', projectId);
  }

  Future<void> saveDeviceToken(String token) async {
    if (currentUserId == null) return;
    await _client.from('user_devices').upsert({'user_id': currentUserId, 'device_token': token}, onConflict: 'user_id, device_token');
  }

  Future<void> sendBroadcastNotification(String message, {String? title, bool fromLeader = true}) async {
    final functionName = fromLeader ? 'notify_broadcast' : 'notify_broadcast_from_member';
    _callNotifyFunction(functionName, {'title': title, 'message': message});
  }

  // --- ✅ إصلاح: تم تعديل هذه الدالة بالكامل ---
  // الآن تقوم بالبحث عن السجل أولاً لتحديثه أو إنشائه بشكل صحيح.
  Future<void> saveNotificationPreferences(Map<String, bool> preferences) async {
    if (currentUserId == null) return;

    for (var entry in preferences.entries) {
      final key = entry.key;
      final value = entry.value;

      String type;
      String? projectId;

      if (key.startsWith('project_')) {
        type = 'project_specific';
        projectId = key.replaceFirst('project_', '');
      } else {
        type = key;
        projectId = null;
      }

      // 1. البحث عن إعداد موجود بنفس المعايير.
      var query = _client
          .from('notification_preferences')
          .select('id')
          .eq('user_id', currentUserId!)
          .eq('notification_type', type);

      if (projectId != null) {
        query = query.eq('project_id', projectId);
      } else {
        // التأكد من البحث عن الحالات التي يكون فيها project_id فارغاً (NULL).
        query = query.isFilter('project_id', null);
      }

      final existing = await query.maybeSingle();

      if (existing != null) {
        // 2. إذا وُجد سجل، يتم تحديثه.
        await _client
            .from('notification_preferences')
            .update({'is_enabled': value})
            .eq('id', existing['id']);
      } else {
        // 3. إذا لم يوجد سجل، يتم إنشاء واحد جديد.
        await _client.from('notification_preferences').insert({
          'user_id': currentUserId!,
          'notification_type': type,
          'project_id': projectId,
          'is_enabled': value,
        });
      }
    }
  }

  Future<Map<String, bool>> getNotificationPreferences() async {
    if (currentUserId == null) return {};
    final response = await _client.from('notification_preferences').select().eq('user_id', currentUserId!);
    
    final Map<String, bool> prefs = {};
    for (var record in response) {
      final type = record['notification_type'];
      final projectId = record['project_id'];
      final isEnabled = record['is_enabled'];
      
      if (type == 'project_specific' && projectId != null) {
        prefs['project_$projectId'] = isEnabled;
      } else {
        prefs[type] = isEnabled;
      }
    }
    return prefs;
  }
}

