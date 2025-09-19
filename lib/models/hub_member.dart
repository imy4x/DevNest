class HubMember {
  final int id;
  final String hubId;
  final String userId;
  final String role;
  String? displayName;
  final bool canAddBugs;
  final bool canEditBugs;
  final bool canUseChat;
  final bool canManageProjects;
  final bool canUseAiAudit;
  // --- إضافة: صلاحية جديدة لإرسال إشعارات عامة ---
  final bool canSendBroadcasts;

  HubMember({
    required this.id,
    required this.hubId,
    required this.userId,
    required this.role,
    this.displayName,
    required this.canAddBugs,
    required this.canEditBugs,
    required this.canUseChat,
    required this.canManageProjects,
    required this.canUseAiAudit,
    required this.canSendBroadcasts, // إضافة للمُنشئ
  });

  factory HubMember.fromJson(Map<String, dynamic> json) {
    return HubMember(
      id: json['id'],
      hubId: json['hub_id'],
      userId: json['user_id'],
      role: json['role'],
      displayName: json['display_name'],
      canAddBugs: json['can_add_bugs'] ?? false,
      canEditBugs: json['can_edit_bugs'] ?? false,
      canUseChat: json['can_use_chat'] ?? false,
      canManageProjects: json['can_manage_projects'] ?? false,
      canUseAiAudit: json['can_use_ai_audit'] ?? false,
      // --- إضافة: قراءة الصلاحية الجديدة من قاعدة البيانات ---
      canSendBroadcasts: json['can_send_broadcasts'] ?? false,
    );
  }
}
