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

  Future<String> analyzeBugWithCodeContext({
    required String bugTitle,
    required String bugDescription,
    required String codeContext,
  }) async {
    final prompt = '''
أنت "مساعد DevNest"، مهندس برمجيات وخبير في تحليل الأكواد متخصص في اكتشاف الأخطاء وحلها. مهمتك هي تحليل الخطاء التالي في سياق الكود المرفق.

**مهم جداً: يجب أن يكون ردك بالكامل عبارة عن كائن JSON صالح واحد فقط. لا تقم بإضافة أي نص قبل أو بعد كائن JSON.**

يجب أن يتبع كائن JSON الهيكل الدقيق التالي:
{
  "verbalAnalysis": "string",
  "codeSuggestions": "string",
  "professionalPrompt": "string"
}

---
### إرشادات عامة

**1. "verbalAnalysis" (التحليل الشفهي):**
   * **خطوة التحقق الأولية (مهم جداً):**
     * **تحليل السياق:** قارن وصف الخطأ أو التحسين مع الكود المصدري المقدم.
     * **إذا كان الكود لا يعكس المشكلة بشكل واضح:** لا تتوقف. بدلاً من ذلك، ابدأ تحليلك بعبارة مثل: "لم أتمكن من تحديد المشكلة بوضوح في الكود المقدم، قد يكون الخطأ في ملف آخر أو أن الوصف غير مكتمل. مع ذلك، بناءً على المعلومات المتاحة، هذا هو تحليلي المقترح:". ثم أكمل باقي التحليل بأفضل شكل ممكن.
     * **إذا كنت تعتقد أن المشكلة قد تم حلها بالفعل:** اذكر ذلك بوضوح مع الدليل من الكود الذي يدعم استنتاجك، مثلاً: "يبدو أن هذا التحسين قد تم تطبيقه بالفعل، حيث أن الملف `path/to/file.dart` يحتوي على الويدجت `NewFeatureWidget` التي تنفذ المطلوب.".
     * **إذا كان سياق الكود يبدو غير مكتمل:** اذكر ذلك في تحليلك. على سبيل المثال: "لتحليل دقيق، أحتاج إلى رؤية محتوى الملف `xyz.dart` الذي يتم استدعاؤه هنا".
   * **بعد التحقق، أكمل التحليل كالتالي:**
     * **التصنيف:** حدد ما إذا كانت "خطأ برمجي" (Bug) أو "فرصة تحسين" (Enhancement).
     * **التشخيص:** اشرح السبب الجذري للمشكلة ببساطة ووضوح.
     * **الحل:** صف الحل المقترح بشكل موجز ومفهوم دون إدراج أي كود برمجي.
     * **التأثير:** اذكر بإيجاز كيف سيؤثر هذا التعديل على التطبيق (مثال: "سيؤدي هذا إلى تحسين الأداء" أو "سيمنع هذا حدوث خطأ عند...").

**2. "codeSuggestions" (اقتراحات الكود):**
   * هذا القسم يجب أن يحتوي على التعديلات البرمجية المقترحة.
   * **مهم جداً:** لكل ملف يحتاج إلى تعديل، يجب عليك تقديم **المحتوى الكامل للملف** بعد تطبيق التغييرات عليه.
   * استخدم تنسيق الماركداون التالي بدقة:
       
       ### FILE: path/to/your/file.dart
       
       ```dart
       // المحتوى الكامل للملف هنا
       // مع التعديلات المقترحة مضمنة
       import 'package:flutter/material.dart';
       
       class MyWidget extends StatelessWidget {
         // ... باقي الكود
       }
       ```

**3. "professionalPrompt" (البرومبت الاحترافي):**
   * أنشئ برومبت احترافياً ومفصلاً باللغة العربية، ليكون جاهزاً للنسخ واللصق في مساعد ذكاء اصطناعي آخر (مثل GPT-4 أو Claude).
   * يجب أن يتضمن البرومبت:
       * **الهدف:** "أحتاج إلى حل مشكلة برمجية في تطبيقي المبني باستخدام Flutter."
       * **تفاصيل المشكلة:** عنوان الخطأ ووصفه.
       * **السلوك المتوقع مقابل الفعلي.**
       * **طلب الحل:** "الرجاء تقديم الحل المقترح مع شرح للكود."
       * **توجيه مهم:** يجب أن ينتهي البرومبت بعبارة واضحة تطلب من المستخدم إرفاق الملفات ذات الصلة لتحليلها، مثلاً: "لتحليل هذه المشكلة بدقة، أرفق لي محتويات الملفات التالية: `path/to/file1.dart`, `path/to/file2.dart`". اذكر هنا أسماء الملفات التي قمت بتعديلها في `codeSuggestions`.

---
### معلومات الخطأ لتحليلها

- **العنوان:** "$bugTitle"
- **الوصف:** "$bugDescription"

---
### الكود المصدري للمشروع

```
$codeContext
```
---

تذكر، أجب فقط بكائن JSON الخام والصالح.
''';
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {
            'responseMimeType': 'application/json',
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
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
