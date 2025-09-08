import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubService {
  final String _githubApiBaseUrl = 'https://api.github.com';

  Map<String, String>? _parseGithubUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host == 'github.com' && uri.pathSegments.length >= 2) {
      final owner = uri.pathSegments[0];
      final repo = uri.pathSegments[1].replaceAll(RegExp(r'\.git$'), '');
      return {'owner': owner, 'repo': repo};
    }
    return null;
  }

  Future<String?> fetchLatestApkUrl(String githubUrl) async {
    final parts = _parseGithubUrl(githubUrl);
    if (parts == null) {
      // --- تعديل: ترجمة رسالة الخطأ ---
      throw Exception('صيغة رابط GitHub غير صالحة.');
    }
    final owner = parts['owner'];
    final repo = parts['repo'];

    final url = Uri.parse('$_githubApiBaseUrl/repos/$owner/$repo/releases/latest');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> assets = data['assets'] ?? [];
        
        for (final asset in assets) {
          final String assetName = asset['name'] ?? '';
          if (assetName.toLowerCase().endsWith('.apk')) {
            return asset['browser_download_url'];
          }
        }
        return null; 
      } else {
        print('GitHub API Error (Releases): ${response.statusCode} - ${response.body}');
        if (response.statusCode == 404) {
          // --- تعديل: ترجمة رسالة الخطأ ---
          throw Exception('لم يتم العثور على آخر إصدار. تأكد من وجود إصدار عام.');
        }
        return null;
      }
    } catch (e) {
      print('Error fetching latest release: $e');
      // --- تعديل: ترجمة رسالة الخطأ ---
      throw Exception('فشل الاتصال بـ GitHub للحصول على الإصدارات.');
    }
  }

  Future<String> fetchRepositoryCodeAsString(String githubUrl) async {
    final parts = _parseGithubUrl(githubUrl);
    // --- تعديل: ترجمة رسالة الخطأ ---
    if (parts == null) throw Exception('صيغة رابط GitHub غير صالحة.');
    
    final owner = parts['owner']!;
    final repo = parts['repo']!;
    final codeBuilder = StringBuffer();

    try {
      final pubspecContent = await _fetchFileContent(owner, repo, 'pubspec.yaml');
      codeBuilder.writeln('--- FILE: pubspec.yaml ---\n');
      codeBuilder.writeln(pubspecContent);
      codeBuilder.writeln('\n--- END OF FILE ---\n');
    } catch (e) {
      print('Could not fetch pubspec.yaml: $e');
    }

    await _fetchDirectoryContents(owner, repo, 'lib', codeBuilder);

    return codeBuilder.toString();
  }

  Future<void> _fetchDirectoryContents(String owner, String repo, String path, StringBuffer builder) async {
    final url = Uri.parse('$_githubApiBaseUrl/repos/$owner/$repo/contents/$path');
    try {
      final response = await http.get(url);
      if (response.statusCode != 200) return;

      final List<dynamic> contents = jsonDecode(response.body);
      for (final item in contents) {
        final String itemType = item['type'];
        final String itemPath = item['path'];
        if (itemType == 'file') {
          try {
             final fileContent = await _fetchFileContent(owner, repo, itemPath);
             builder.writeln('--- FILE: $itemPath ---\n');
             builder.writeln(fileContent);
             builder.writeln('\n--- END OF FILE ---\n');
          } catch(e) {
             print('Could not fetch content for file $itemPath: $e');
          }
        } else if (itemType == 'dir') {
          await _fetchDirectoryContents(owner, repo, itemPath, builder);
        }
      }
    } catch (e) {
      print('Error fetching directory contents for $path: $e');
    }
  }

  Future<String> _fetchFileContent(String owner, String repo, String path) async {
     final url = Uri.parse('$_githubApiBaseUrl/repos/$owner/$repo/contents/$path');
     final response = await http.get(url, headers: {'Accept': 'application/vnd.github.raw'});
     if (response.statusCode == 200) {
       return response.body;
     } else {
       // --- تعديل: ترجمة رسالة الخطأ ---
       throw Exception('فشل تحميل محتوى الملف (رمز الحالة: ${response.statusCode})');
     }
  }
}
