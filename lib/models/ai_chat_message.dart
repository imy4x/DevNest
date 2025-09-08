class AiChatMessage {
  final String id;
  final String projectId;
  final String userId;
  final String role; // 'user' or 'model'
  final String content;
  final DateTime createdAt;

  AiChatMessage({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory AiChatMessage.fromJson(Map<String, dynamic> json) {
    return AiChatMessage(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
