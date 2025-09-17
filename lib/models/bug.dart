

class Bug {
  final String id;
  final String title;
  final String description;
  final String type; // Critical, Minor, Enhancement
  final String status; // Open, In Progress, Resolved
  final String projectId;
  final DateTime createdAt;
  final String? source; 

  Bug({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    required this.projectId,
    required this.createdAt,
    this.source,
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
    );
  }

  Bug copyWith({String? status}) {
    return Bug(
      id: id,
      title: title,
      description: description,
      type: type,
      status: status ?? this.status,
      projectId: projectId,
      createdAt: createdAt,
      source: source,
    );
  }
}
