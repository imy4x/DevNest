class Project {
  final String id;
  String name;
  String? description;
  final String? hubId;
  
  // --- تعديل: تم حذف الحقول الإضافية ---
  String? githubUrl;
  String? apkDownloadUrl;

  Project({
    required this.id,
    required this.name,
    this.description,
    this.hubId,
    this.githubUrl,
    this.apkDownloadUrl,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      hubId: json['hub_id'],
      // --- تعديل: تم حذف الحقول الإضافية ---
      githubUrl: json['github_url'],
      apkDownloadUrl: json['apk_download_url'],
    );
  }
  
  Map<String, dynamic> toJsonForUpdate() {
    return {
      'name': name,
      'description': description,
      // --- تعديل: تم حذف الحقول الإضافية ---
      'github_url': githubUrl,
      'apk_download_url': apkDownloadUrl,
    };
  }
}
