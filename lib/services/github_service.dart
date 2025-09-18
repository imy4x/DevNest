import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

// Helper function for retry logic with exponential backoff
Future<T> _retry<T>(Future<T> Function() operation) async {
  const maxRetries = 3;
  int attempt = 0;
  while (attempt < maxRetries) {
    try {
      return await operation();
    } on SocketException catch (e) {
      attempt++;
      debugPrint('Network error (attempt $attempt): $e');
      if (attempt >= maxRetries) rethrow;
      await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
    } on TimeoutException catch (e) {
      attempt++;
      debugPrint('Request timeout (attempt $attempt): $e');
      if (attempt >= maxRetries) rethrow;
      await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
    } on http.ClientException catch (e) {
       attempt++;
      debugPrint('Client exception (attempt $attempt): $e');
      if (attempt >= maxRetries) rethrow;
      await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
    }
  }
  throw Exception('Failed after multiple retries');
}

// --- START OF CHANGE ---

/// ✅ (دالة جديدة) تعمل في isolate لتحليل ملف ZIP وإرجاع الملفات على هيئة Map
Map<String, String> _parseZipAndExtractFilesToMap(List<int> zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final filesMap = <String, String>{};

  const allowedExtensions = {
    '.dart', '.yaml', '.json', '.md', '.txt', '.xml', '.gradle',
    '.properties', '.html', '.css', '.js', 'Dockerfile', '.gitignore',
  };

  for (final file in archive) {
    if (file.isFile &&
        allowedExtensions.any((ext) => file.name.endsWith(ext))) {
      final pathParts = file.name.split('/');
      if (pathParts.length < 2) continue;

      final cleanPath = pathParts.sublist(1).join('/');
      if (cleanPath.isEmpty) continue;

      try {
        final content = utf8.decode(file.content as List<int>, allowMalformed: true);
        filesMap[cleanPath] = content;
      } catch (e) {
        debugPrint('Could not decode file: $cleanPath');
      }
    }
  }

  return filesMap;
}

/// (الدالة الحالية) لتحليل ZIP وإرجاع الملفات كنص واحد
String _parseZipAndExtractCode(List<int> zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final codeBuffer = StringBuffer();

  const allowedExtensions = {
    '.dart', '.yaml', '.json', '.md', '.txt', '.xml', '.gradle', 
    '.properties', '.html', '.css', '.js', 'Dockerfile', '.gitignore',
  };

  for (final file in archive) {
    if (file.isFile &&
        allowedExtensions.any((ext) => file.name.endsWith(ext))) {
      final pathParts = file.name.split('/');
      if (pathParts.length < 2) continue;

      final cleanPath = pathParts.sublist(1).join('/');
      if (cleanPath.isEmpty) continue;

      try {
        final content = utf8.decode(file.content as List<int>, allowMalformed: true);
        codeBuffer.writeln('--- START FILE: $cleanPath ---');
        codeBuffer.writeln(content);
        codeBuffer.writeln('--- END FILE ---\n');
      } catch (e) {
        debugPrint('Could not decode file: $cleanPath');
      }
    }
  }

  if (codeBuffer.isEmpty) {
    return "لم يتم العثور على ملفات برمجية قابلة للقراءة في المستودع. تأكد من أن الملفات موجودة في الفرع الرئيسي (main/master).";
  }

  return codeBuffer.toString();
}

// --- END OF CHANGE ---


class GitHubService {
  
  // --- START OF CHANGE ---

  /// ✅ (دالة جديدة) تجلب ملفات المستودع وتعيدها على هيئة Map<String, String>
  /// مناسبة للتحليل الذكي الذي يتطلب معرفة مسارات الملفات.
  Future<Map<String, String>> fetchRepositoryFilesAsMap(String repoUrl) async {
    final uri = Uri.parse(repoUrl.replaceAll('.git', ''));
    if (uri.pathSegments.length < 2) {
      throw Exception(
          'رابط مستودع GitHub غير صالح. يجب أن يكون بالصيغة: https://github.com/user/repo');
    }
    final repoPath = uri.pathSegments.take(2).join('/');
    final zipballUrl = 'https://api.github.com/repos/$repoPath/zipball/main';

    try {
      final http.Response response = await _retry(() async {
        final mainResponse = await http.get(Uri.parse(zipballUrl));
        if (mainResponse.statusCode == 200) {
          return mainResponse;
        }
        
        debugPrint('Branch "main" not found, trying "master"...');
        final masterZipballUrl = 'https://api.github.com/repos/$repoPath/zipball/master';
        final masterResponse = await http.get(Uri.parse(masterZipballUrl));
        
        if (masterResponse.statusCode == 200) {
          return masterResponse;
        }

        throw http.ClientException(
          'فشل تحميل المستودع (رمز الخطأ: ${masterResponse.statusCode}). تأكد من أن المستودع عام وأن الفرع الرئيسي هو main أو master.',
          masterResponse.request?.url,
        );
      });

      // استخدام الدالة الجديدة التي تعيد Map في isolate
      return await compute(_parseZipAndExtractFilesToMap, response.bodyBytes);
    } catch (e) {
      throw Exception('حدث خطأ غير متوقع: $e');
    }
  }
  // --- END OF CHANGE ---

  Future<String> fetchRepositoryCodeAsString(String repoUrl) async {
    final uri = Uri.parse(repoUrl.replaceAll('.git', ''));
    if (uri.pathSegments.length < 2) {
      throw Exception(
          'رابط مستودع GitHub غير صالح. يجب أن يكون بالصيغة: https://github.com/user/repo');
    }
    final repoPath = uri.pathSegments.take(2).join('/');

    final zipballUrl = 'https://api.github.com/repos/$repoPath/zipball/main';

    try {
      final http.Response response = await _retry(() async {
        final mainResponse = await http.get(Uri.parse(zipballUrl));
        if (mainResponse.statusCode == 200) {
          return mainResponse;
        }
        
        final masterZipballUrl = 'https://api.github.com/repos/$repoPath/zipball/master';
        final masterResponse = await http.get(Uri.parse(masterZipballUrl));
        
        if (masterResponse.statusCode == 200) {
          return masterResponse;
        }

        throw http.ClientException(
          'فشل تحميل المستودع (رمز الخطأ: ${masterResponse.statusCode}). تأكد من أن المستودع عام وأن الفرع الرئيسي هو main أو master.',
          masterResponse.request?.url,
        );
      });

      return await compute(_parseZipAndExtractCode, response.bodyBytes);
    } catch (e) {
      throw Exception('حدث خطأ غير متوقع: $e');
    }
  }
  
  Future<Map<String, String>> getLatestReleaseAssetInfo(String repoUrl) async {
    final uri = Uri.parse(repoUrl.replaceAll('.git', ''));
     if (uri.pathSegments.length < 2) {
      throw Exception('رابط مستودع GitHub غير صالح.');
    }
    final repoPath = uri.pathSegments.take(2).join('/');
    final apiUrl = 'https://api.github.com/repos/$repoPath/releases/latest';

    try {
      final response = await _retry(() => http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 30)));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null && assets.isNotEmpty) {
          final apkAsset = assets.firstWhere(
            (asset) => (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
            orElse: () => null,
          );

          if (apkAsset != null) {
            return {
              'downloadUrl': apkAsset['browser_download_url'] as String,
              'fileName': apkAsset['name'] as String,
              'releaseTag': data['tag_name'] as String? ?? 'Latest',
              'releaseBody': data['body'] as String? ?? 'لا يوجد وصف لهذا الإصدار.',
            };
          }
        }
        throw Exception('لم يتم العثور على ملف APK في آخر إصدار.');
      } else {
        throw Exception('فشل العثور على الإصدار الأخير (رمز الخطأ: ${response.statusCode}).');
      }
    } catch (e) {
      throw Exception('فشل جلب معلومات الإصدار: $e');
    }
  }
}
