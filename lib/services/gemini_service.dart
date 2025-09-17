import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/ai_chat_message.dart';
import '../models/project.dart';
import '../models/bug.dart';
import 'dart:math';

Future<T> _retry<T>(Future<T> Function() operation) async {
  const maxRetries = 3;
  int attempt = 0;
  while (attempt < maxRetries) {
    try {
      return await operation();
    } on SocketException catch (e) {
      attempt++;
      print('Network error (attempt $attempt): $e');
      if (attempt >= maxRetries) rethrow;
      await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
    } on TimeoutException catch (e) {
      attempt++;
      print('Request timeout (attempt $attempt): $e');
      if (attempt >= maxRetries) rethrow;
      await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
    } on http.ClientException catch (e) {
       attempt++;
      print('Client exception (attempt $attempt): $e');
      if (attempt >= maxRetries) rethrow;
      await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
    }
  }
  throw Exception('Failed after multiple retries');
}

class GeminiService {
  final String _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiApiKey';
  
  final String _proApiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=$geminiApiKey';


  Future<String> generalChat({
    required String userMessage,
    required Project? project,
    required List<Bug> bugs,
    required List<AiChatMessage> history,
    String? codeContext,
  }) async {
    // --- MODIFIED: Updated system prompt with new rules ---
    String systemContext = '''
أنت "مساعد DevNest"، خبير برمجي متخصص في Flutter. مهمتك هي تحليل المشاكل وتقديم اقتراحات وحلول نصية فقط.
تحدث باللغة العربية بأسلوب احترافي ومباشر.

**قواعد صارمة جداً يجب اتباعها:**
1.  **ممنوع الأكواد نهائياً:** لا تقم أبداً بإدراج أي كود برمجي، أو مقتطفات، أو أسماء ملفات بتنسيق الكود. يجب أن يكون ردك نصاً شرحياً فقط.
2.  **الإيجاز:** اجعل ردك موجزاً ومختصراً قدر الإمكان، وحافظ على أن يكون في حدود 250 كلمة.
3.  **التشخيص:** اشرح السبب الجذري للمشكلة أو الاستفسار بوضوح.
4.  **الاقتراح:** صف الحل المقترح شفهياً. يمكنك الإشارة إلى المفاهيم العامة أو الوظائف التي يجب تعديلها دون كتابة الكود الفعلي. مثلاً: "لتنفيذ ذلك، ستحتاج إلى تعديل الدالة المسؤولة عن الحفظ في قاعدة البيانات لتشمل حقل التاريخ."
''';

    if (project != null) {
      systemContext += '\n--- سياق المشروع الحالي ---\n';
      systemContext += 'الاسم: ${project.name}\n';
      systemContext += 'الوصف: ${project.description ?? "لا يوجد"}\n';
      
      if (bugs.isNotEmpty) {
        systemContext += '\nآخر الأخطاء المسجلة:\n';
        for (var bug in bugs.take(3)) {
          systemContext += '- "${bug.title}" (الحالة: ${bug.status})\n';
        }
      } else {
        systemContext += '\nلا توجد أخطاء مسجلة حالياً.\n';
      }
    }

    // Code context is sent for analysis, but the AI is instructed not to return it.
    if (codeContext != null && codeContext.isNotEmpty) {
      systemContext += '\n--- كود المشروع الكامل للتحليل ---\n';
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
      final response = await _retry(() => http.post(
            Uri.parse(_apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': contents,
              'systemInstruction': {
                'parts': [{'text': systemContext}]
              },
              'generationConfig': {
                'temperature': 0.8,
                // --- MODIFIED: Reduced max tokens to encourage shorter responses ---
                'maxOutputTokens': 1024,
              },
            }),
          ).timeout(const Duration(seconds: 90)));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          return data['candidates'][0]['content']['parts'][0]['text'];
        }
        return "عذراً، لم يتمكن المساعد من إنشاء رد. قد تكون المشكلة متعلقة بسياسات السلامة.";
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? response.body;
        print('Gemini Error: $errorMessage');
        throw Exception("عذراً، حدث خطأ أثناء التواصل مع المساعد الذكي.\n$errorMessage");
      }
    } catch (e) {
      print('Gemini Service Exception: $e');
      throw Exception("عذراً، فشل الاتصال بخدمة الذكاء الاصطناعي: $e");
    }
  }

  // The rest of the file remains unchanged as it's for other features.
  Future<String> analyzeBugWithCodeContext({
    required Bug bug,
    required Project project,
    required String codeContext,
  }) async {
    const systemPrompt = '''
أنت "مساعد DevNest"، مبرمج خبير ومساعد ذكاء اصطناعي متخصص في Flutter و Dart.
مهمتك هي تحليل مشكلة برمجية محددة ضمن سياق مشروع كامل وتقديم حل متكامل.
**قواعد صارمة جداً يجب اتباعها:**
1.  **الشرح أولاً:** ابدأ دائماً بشرح نصي واضح للمشكلة وسببها الجذري والحل المقترح.
2.  **الحل الكامل:** بعد الشرح، قدم الحل الكامل على شكل ملفات كاملة جاهزة للنسخ والاستبدال. لا تستخدم أبداً مقتطفات أو تعليقات مثل `// ... existing code`.
3.  **تنسيق الملفات الإلزامي (الأكثر أهمية):**
    * يجب أن يأتي الشرح **قبل** أي كتلة كود.
    * يجب وضع كل ملف معدل داخل المحددات التالية بشكل صارم:
        --- START FILE: path/to/your/file.dart ---
        [CODE HERE]
        --- END FILE ---
    * **ممنوع منعاً باتاً** وضع أي نص أو رموز أو مسافات بيضاء قبل `--- START FILE:` أو بعد `--- END FILE ---`.
''';

    final userPrompt = '''
--- تفاصيل الخطأ/التحسين المطلوب تحليله ---
النوع: ${bug.type}
العنوان: "${bug.title}"
الوصف: "${bug.description}"

--- كود المشروع ---
$codeContext
--- نهاية كود المشروع ---

الرجاء تحليل هذا الخطأ بناءً على الكود المقدم واتباع القواعد المحددة في تعليمات النظام بأقصى درجات الدقة. ابدأ بالشرح ثم ضع الملفات المعدلة.
''';

    try {
      final response = await _retry(() => http.post(
            Uri.parse(_proApiUrl), // Using Pro for analysis
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {'parts': [{'text': userPrompt}]}
              ],
              'systemInstruction': {
                'parts': [{'text': systemPrompt}]
              },
              'generationConfig': {
                'temperature': 0.7,
                'maxOutputTokens': 8192,
              },
            }),
          ).timeout(const Duration(seconds: 90)));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          return data['candidates'][0]['content']['parts'][0]['text'];
        }
        throw Exception("عذراً، لم يتمكن المساعد من إنشاء رد.");
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? response.body;
        throw Exception("فشل الحصول على اقتراح: $errorMessage");
      }
    } catch (e) {
      print('Gemini Service Exception (analyzeBug): $e');
      throw Exception("فشل الاتصال بالخدمة لتحليل الخطأ: $e");
    }
  }
  
  Future<String> performCodeAudit({
    required String codeContext,
    required String auditType,
    required List<Bug> existingBugs,
  }) async {
    final auditDescription = auditType == 'bugs'
        ? 'ابحث عن الأخطاء المحتملة والمشاكل المنطقية فقط. يجب أن تكون أنواع النتائج "حرج" أو "بسيط" حصراً.'
        : 'اقترح تحسينات على الكود، إعادة هيكلة، أو ميزات جديدة. يجب أن يكون نوع كل النتائج "تحسين" حصراً.';

    final allowedTypes = auditType == 'bugs'
        ? '"حرج", "بسيط"'
        : '"تحسين"';

    final systemPrompt = '''
أنت "Code Auditor"، خبير دقيق جداً في تحليل شيفرة Flutter.
مهمتك هي فحص الكود المقدم، ومقارنته بقائمة المشاكل المسجلة حالياً، وتقديم قائمة بالمشاكل **الجديدة كلياً** فقط، على هيئة JSON.
**قواعد صارمة جداً للإخراج:**
1.  **JSON فقط:** يجب أن يكون ردك عبارة عن سلسلة JSON صالحة وقابلة للتحليل **فقط**. لا تضف أي نص توضيحي أو علامات ```json```.
2.  **الدقة المطلقة:** تحقق من كل خطأ تقترحه بعناية فائقة. يجب أن تكون الأخطاء حقيقية ومنطقية وموجودة في الكود. لا تخمن أبداً.
3.  **تجنب التكرار (الأهم):**
    * **اقرأ "قائمة المشاكل الحالية" جيداً.**
    * **لا تقترح أي مشكلة لها نفس المعنى أو المفهوم لمشكلة موجودة بالفعل**، حتى لو كانت بصياغة مختلفة.
    * مهمتك هي إيجاد مشاكل **مختلفة وجديدة تماماً**.
4.  **الرد الفارغ:** إذا لم تجد أي أخطاء أو تحسينات **جديدة ومهمة** بعد تحليلك الدقيق، قم بإرجاع مصفوفة JSON فارغة: `[]`. هذا رد مقبول ومطلوب عند عدم وجود جديد.
5.  **هيكل الـ JSON:** يجب أن يكون الـ JSON عبارة عن مصفوفة (array) من الكائنات (objects). كل كائن يجب أن يحتوي على الحقول الثلاثة التالية: `title` (String), `description` (String), `type` (String must be one of [$allowedTypes]).
''';

    String existingBugsString = 'لا توجد مشاكل مسجلة حالياً.';
    if (existingBugs.isNotEmpty) {
      existingBugsString = existingBugs.map((b) => '- العنوان: ${b.title}\n  الوصف: ${b.description}').join('\n');
    }

    final userPrompt = '''
--- كود المشروع ---
$codeContext
--- نهاية كود المشروع ---

--- قائمة المشاكل الحالية (لا تقم بتكرار أي شيء منها أو ما يشبهها في المعنى) ---
$existingBugsString
--- نهاية القائمة ---

المهمة: $auditDescription
الرجاء تحليل الكود وإرجاع النتائج بصيغة JSON حسب القواعد الصارمة المحددة في تعليمات النظام.
''';

    try {
      final response = await _retry(() => http.post(
            Uri.parse(_proApiUrl), // Using Pro for analysis
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {'parts': [{'text': userPrompt}]}
              ],
              'systemInstruction': {
                'parts': [{'text': systemPrompt}]
              },
              'generationConfig': {
                'temperature': 0.5,
                'maxOutputTokens': 8192,
                'responseMimeType': 'application/json',
              },
            }),
          ).timeout(const Duration(seconds: 90)));


      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          return data['candidates'][0]['content']['parts'][0]['text'];
        }
        throw Exception("لم يتمكن المساعد من إنشاء رد JSON.");
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? response.body;
        throw Exception("فشل الفحص الذكي: $errorMessage");
      }
    } catch (e) {
      print('Gemini Service Exception (performAudit): $e');
      throw Exception("فشل الاتصال بالخدمة لإجراء الفحص: $e");
    }
  }
}

