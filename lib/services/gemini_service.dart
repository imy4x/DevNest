import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/ai_chat_message.dart';
import '../models/project.dart';
import '../models/bug.dart';

class GeminiService {
  // --- START: NEW CHANGES FOR MODEL FALLBACK ---
  final String _proModel = 'gemini-2.5-pro';
  final String _flashModel = 'gemini-2.5-flash';
  String _currentModel = 'gemini-2.5-pro';
  Timer? _fallbackTimer;

  String _getApiUrl(String model) =>
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiApiKey';
  // --- END: NEW CHANGES FOR MODEL FALLBACK ---

  /// Handles a general chat conversation with fallback logic.
  /// Returns a tuple containing the response message and a boolean indicating if a model switch occurred.
  Future<(String, bool)> generalChat({
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
      systemContext +=
          'فيما يلي محتويات الملفات الرئيسية في المشروع للمساعدة في التحليل:\n\n';
      systemContext += codeContext;
      systemContext += '\n--- نهاية كود المشروع ---\n';
    }

    final List<Map<String, dynamic>> contents = [];
    for (var msg in history) {
      contents.add({
        'role': msg.role,
        'parts': [
          {'text': msg.content}
        ]
      });
    }
    contents.add({
      'role': 'user',
      'parts': [
        {'text': userMessage}
      ]
    });

    final body = {
      'contents': contents,
      'systemInstruction': {
        'parts': [
          {'text': systemContext}
        ]
      }
    };

    try {
      final response = await http.post(
        Uri.parse(_getApiUrl(_currentModel)),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // --- FIX: Explicitly cast dynamic type to String ---
        return (
          data['candidates'][0]['content']['parts'][0]['text'] as String,
          false
        );
      } else {
        throw HttpException('API Error: ${response.statusCode}');
      }
    } catch (e) {
      if (_currentModel == _proModel) {
        print('Error with Pro model, falling back to Flash. Error: $e');
        _currentModel = _flashModel;

        _fallbackTimer?.cancel();
        _fallbackTimer = Timer(const Duration(seconds: 25), () {
          print('Fallback timer expired. Reverting to Pro model.');
          _currentModel = _proModel;
        });

        try {
          final fallbackResponse = await http.post(
            Uri.parse(_getApiUrl(_currentModel)),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          );

          if (fallbackResponse.statusCode == 200) {
            final data = jsonDecode(fallbackResponse.body);
            // --- FIX: Explicitly cast dynamic type to String ---
            final content =
                data['candidates'][0]['content']['parts'][0]['text'] as String;
            return (content, true); // Success with fallback
          } else {
            return (
              "عذراً، حدث خطأ أثناء التواصل مع المساعد الذكي. رمز الحالة: ${fallbackResponse.statusCode}",
              false
            );
          }
        } catch (fallbackError) {
          return ("عذراً، حدث استثناء بعد التبديل: $fallbackError", false);
        }
      } else {
        return ("عذراً، حدث استثناء: $e", false);
      }
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
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
      }
    };

    try {
      final response = await http.post(
        Uri.parse(_getApiUrl(_currentModel)),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // --- FIX: Explicitly cast dynamic type to String ---
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      } else {
        throw HttpException('API Error: ${response.statusCode}');
      }
    } catch (e) {
      if (_currentModel == _proModel) {
        print(
            'Error with Pro model for bug analysis, falling back to Flash. Error: $e');
        _currentModel = _flashModel;

        _fallbackTimer?.cancel();
        _fallbackTimer = Timer(const Duration(seconds: 25), () {
          print('Fallback timer expired. Reverting to Pro model.');
          _currentModel = _proModel;
        });

        try {
          final fallbackResponse = await http.post(
            Uri.parse(_getApiUrl(_currentModel)),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          );
          if (fallbackResponse.statusCode == 200) {
            final data = jsonDecode(fallbackResponse.body);
            // --- FIX: Explicitly cast dynamic type to String ---
            return data['candidates'][0]['content']['parts'][0]['text']
                as String;
          } else {
            throw HttpException(
                'Fallback API Error: ${fallbackResponse.statusCode}');
          }
        } catch (fallbackError) {
          return jsonEncode({
            "verbalAnalysis":
                "عذراً، حدث استثناء مزدوج أثناء محاولة تحليل الخطأ.",
            "codeSuggestions": "Exception: ${fallbackError.toString()}",
            "professionalPrompt":
                "الرجاء المساعدة في حل مشكلة نتج عنها الاستثناء التالي بعد محاولة التبديل: ${fallbackError.toString()}"
          });
        }
      } else {
        return jsonEncode({
          "verbalAnalysis": "عذراً، حدث استثناء أثناء محاولة تحليل الخطأ.",
          "codeSuggestions": "Exception: ${e.toString()}",
          "professionalPrompt":
              "الرجاء المساعدة في حل مشكلة نتج عنها الاستثناء التالي: ${e.toString()}"
        });
      }
    }
  }
}

