class Project {
  final String id;
  String name;
  String? description;
  final String? hubId;
  String? githubUrl;

  Project({
    required this.id,
    required this.name,
    this.description,
    this.hubId,
    this.githubUrl,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      hubId: json['hub_id'],
      githubUrl: json['github_url'],
    );
  }
  
  Map<String, dynamic> toJsonForUpdate() {
    return {
      'name': name,
      'description': description,
      'github_url': githubUrl,
    };
  }
}
