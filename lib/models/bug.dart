class Bug {
  final String id;
  final String title;
  final String description;
  final String type; // Critical, Minor, Enhancement
  final String status; // Open, In Progress, Resolved
  final String projectId;
  final DateTime createdAt;
  final String? source;
  // --- إضافة: حقل لتخزين أولوية المستخدم الشخصية ---
  int? userPriority;

  Bug({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    required this.projectId,
    required this.createdAt,
    this.source,
    this.userPriority, // تعيينه في المُنشئ
  });

  factory Bug.fromJson(Map<String, dynamic> json) {
    return Bug(
      id: json['id'],
      title: json['title'],
      description: json['description'] ?? '',
      type: json['type'],
      status: json['status'],
      projectId: json['project_id'],
      createdAt: DateTime.parse(json['created_at']),
      source: json['source'],
      // --- إضافة: قراءة الأولوية من البيانات الإضافية عند جلبها ---
      userPriority: json['user_priority'],
    );
  }

  Bug copyWith({String? status, int? userPriority}) {
    return Bug(
      id: id,
      title: title,
      description: description,
      type: type,
      status: status ?? this.status,
      projectId: projectId,
      createdAt: createdAt,
      source: source,
      userPriority: userPriority ?? this.userPriority,
    );
  }

  // --- إضافة: دالة مساعدة للترتيب. الأرقام الأقل هي الأعلى أولوية. ---
  // العناصر بدون أولوية (null) تأتي في النهاية.
  int get priorityOrder => userPriority ?? 999;
}
