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

  // --- ✨ تعديل: البرومبت الآن يطلب من النموذج إعادة رد بصيغة JSON منظمة --- ✨
  Future<String> analyzeBugWithCodeContext({
    required String bugTitle,
    required String bugDescription,
    required String codeContext,
  }) async {
    final prompt = '''
أنت "مساعد DevNest"، مهندس برمجيات وخبير في تحليل الأكواد متخصص في اكتشاف الأخطاء وحلها. مهمتك هي تحليل الخطأ التالي في سياق الكود المرفق.

**مهم جداً: يجب أن يكون ردك بالكامل عبارة عن كائن JSON صالح واحد فقط. لا تقم بإضافة أي نص قبل أو بعد كائن JSON.**

يجب أن يتبع كائن JSON الهيكل الدقيق التالي:
{
  "verbalAnalysis": "string",
  "codeSuggestions": "string",
  "professionalPrompt": "string"
}

**إرشادات المحتوى:**

1.  **"verbalAnalysis"**:
    * قدم شرحاً ودياً وحوارياً وواضحاً للخطأ باللغة العربية.
    * ابدأ بتصنيف الخطأ (مثال: خطأ حرج، خطأ بسيط، تحسين).
    * اشرح السبب الجذري للمشكلة ببساطة.
    * اذكر الحل المقترح بإيجاز دون عرض أي كود برمجي.
    * اجعل النص موجزاً وسهل الفهم.

2.  **"codeSuggestions"**:
    * قدم تفصيلاً فنياً للتغييرات البرمجية المطلوبة باللغة العربية.
    * استخدم الماركداون للتنسيق.
    * لكل ملف يحتاج إلى تغيير، أنشئ قسماً باستخدام `## اسم الملف: path/to/file.dart`.
    * تحت كل ملف، حدد الموقع الدقيق للتغيير (مثال: `**الموقع:** داخل دالة `build`).
    * قدم مقتطف الكود الكامل والصحيح داخل قسم ماركداون للكود (```dart ... ```).

3.  **"professionalPrompt"**:
    * أنشئ برومبت احترافياً وشاملاً ومفصلاً باللغة العربية، جاهز للنسخ واللصق في مساعد ذكاء اصطناعي آخر (مثل GPT-4 أو Claude).
    * يجب أن يبدأ البرومبت بهدف واضح (مثال: "أحتاج إلى حل مشكلة برمجية في تطبيقي المبني بـ Flutter.").
    * يجب أن يتضمن:
        * عنوان الخطأ ووصفه التفصيلي.
        * السلوك المتوقع مقابل السلوك الفعلي.
        * أي رسائل خطأ ذات صلة.
        * توجيه نهائي، مثل "الرجاء تقديم الحل المقترح مع شرح للكود."
        * يجب أن يتضمن أيضاً ملاحظة لمطالبة المستخدم بإرفاق الملفات ذات الصلة في الشات لتسهيل التحليل.

---
**معلومات الخطأ:**
- **العنوان:** "$bugTitle"
- **الوصف:** "$bugDescription"

---
**الكود المصدري للمشروع:**
```
$codeContext
```
---

تذكر، أجب فقط بكائن JSON الخام.
''';
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
           // ✨ إضافة: ضبط إعدادات النموذج لضمان إخراج JSON
          'generationConfig': {
            'responseMimeType': 'application/json',
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // النص الآن موجود مباشرة داخل 'text'
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        return jsonEncode({
          "verbalAnalysis": "عذراً، لم أتمكن من الحصول على اقتراح. رمز الحالة: ${response.statusCode}",
          "codeSuggestions": "Error: ${response.statusCode}\n${response.body}",
          "professionalPrompt": "الرجاء المساعدة في حل مشكلة أدت إلى رمز الحالة ${response.statusCode} عند محاولة تحليل الخطأ."
        });
      }
    } catch (e) {
       return jsonEncode({
          "verbalAnalysis": "عذراً، حدث استثناء أثناء محاولة تحليل الخطأ.",
          "codeSuggestions": "Exception: ${e.toString()}",
          "professionalPrompt": "الرجاء المساعدة في حل مشكلة نتج عنها الاستثناء التالي: ${e.toString()}"
        });
    }
  }
}

