import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/ai_chat_message.dart';
import '../models/project.dart';
import '../models/bug.dart';

class GeminiService {
  final String _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$geminiApiKey';

  Future<String> generalChat({
    required String userMessage,
    required Project? project,
    required List<Bug> bugs,
    required List<AiChatMessage> history,
    String? codeContext,
  }) async {
    
    String systemContext = '''
أنت "مساعد DevNest"، مساعد ذكاء اصطناعي خبير ومبرمج محترف تتحدث اللغة العربية بطلاقة.
مهمتك هي مساعدة المطورين في حل مشاكلهم البرمجية، وتقديم اقتراحات بناءة، وشرح المفاهيم المعقدة بوضوح.
كن دقيقاً، ومهذباً، وقدم إجابات عملية ومفيدة.
''';

    if (project != null) {
      systemContext += '\n--- سياق المشروع الحالي ---\n';
      systemContext += 'الاسم: ${project.name}\n';
      systemContext += 'الوصف: ${project.description ?? "لا يوجد"}\n';
      // --- تعديل: تم حذف الحقول الإضافية من سياق الذكاء الاصطناعي ---
      systemContext += 'رابط GitHub: ${project.githubUrl ?? "غير محدد"}\n';


      if (bugs.isNotEmpty) {
        systemContext += '\nآخر الأخطاء المسجلة:\n';
        for (var bug in bugs.take(5)) {
          systemContext += '- عنوان: "${bug.title}", الحالة: ${bug.status}\n';
        }
      } else {
        systemContext += '\nلا توجد أخطاء مسجلة حالياً في هذا المشروع.\n';
      }
      systemContext += '--- نهاية سياق المشروع ---\n';
    } else {
      systemContext += '\nالمستخدم لم يختر مشروعاً بعد.';
    }

    if (codeContext != null && codeContext.isNotEmpty) {
      systemContext += '\n--- كود المشروع من مستودع GitHub ---\n';
      systemContext += 'فيما يلي محتويات الملفات الرئيسية في المشروع للمساعدة في التحليل:\n\n';
      systemContext += codeContext;
      systemContext += '\n--- نهاية كود المشروع ---\n';
    }

    final List<Map<String, dynamic>> contents = [];
    
    for (var msg in history) {
      contents.add({
        'role': msg.role,
        'parts': [{'text': msg.content}]
      });
    }

    contents.add({
      'role': 'user',
      'parts': [{'text': userMessage}]
    });


    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': contents,
          'systemInstruction': {
            'parts': [{'text': systemContext}]
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        print('Gemini Error: ${response.body}');
        return "عذراً، حدث خطأ أثناء التواصل مع المساعد الذكي. رمز الحالة: ${response.statusCode}";
      }
    } catch (e) {
      return "عذراً، حدث استثناء: $e";
    }
  }

  Future<String> getBugSolution(String bugTitle, String bugDescription) async {
    final prompt = '''
أنت مطور برامج خبير ومتخصص في تصحيح الأخطاء.
بالنظر إلى وصف الخطأ التالي، قدم حلاً مفصلاً وواضحاً باللغة العربية.
اشرح الأسباب المحتملة للخطأ، وقدم خطوات عملية لإصلاحه، مع أمثلة برمجية إذا أمكن.
إذا كان هناك توثيق رسمي مفيد، قم بتضمين رابط إليه.

عنوان الخطأ: "$bugTitle"
وصف الخطأ: "$bugDescription"
''';
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        return "عذراً، لم أتمكن من الحصول على اقتراح. رمز الحالة: ${response.statusCode}";
      }
    } catch (e) {
      return "عذراً، حدث استثناء: $e";
    }
  }
}
