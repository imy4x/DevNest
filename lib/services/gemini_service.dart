import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/ai_chat_message.dart'; // قم بتعديل 'package_name' لاسم الحزمة الصحيح
import '../models/project.dart'; // قم بتعديل 'package_name' لاسم الحزمة الصحيح
import '../models/bug.dart'; // قم بتعديل 'package_name' لاسم الحزمة الصحيح
import 'package:http/http.dart' as http;
import 'dart:math';
import '../config.dart'; // استيراد قائمة المفاتيح

/// A custom exception to hold HTTP status codes for the retry logic.
class HttpExceptionWithStatusCode implements Exception {
  final String message;
  final int statusCode;

  HttpExceptionWithStatusCode(this.message, this.statusCode);

  @override
  String toString() => 'HttpException: $message, StatusCode: $statusCode';
}

/// Retries an operation with exponential backoff.
Future<T> _retry<T>(Future<T> Function() operation) async {
  const maxRetries = 3; // تقليل عدد المحاولات لكل مفتاح
  int attempt = 0;
  while (attempt < maxRetries) {
    try {
      return await operation();
    } on HttpExceptionWithStatusCode {
      rethrow; // إعادة رمي أخطاء HTTP مباشرة لمعالجتها في منطق تبديل المفاتيح
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
    }
  }
  throw Exception('Failed after multiple retries');
}

class GeminiService {
  // --- إضافة جديدة: متغير لتتبع المفتاح المستخدم حالياً ---
  int _currentApiKeyIndex = 0;

  // --- دالة مساعدة لإنشاء عنوان URL ديناميكياً ---
  String _getApiUrl(String model, String apiKey) {
    return 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';
  }
  
  // --- تعديل جوهري: دالة مركزية لتنفيذ الطلبات مع تبديل المفاتيح ---
  Future<http.Response> _executeRequestWithKeyRotation(
      String model, Map<String, dynamic> body) async {
    while (_currentApiKeyIndex < geminiApiKeys.length) {
      final apiKey = geminiApiKeys[_currentApiKeyIndex];
      final apiUrl = _getApiUrl(model, apiKey);
      
      try {
        print('Attempting API call with key index: $_currentApiKeyIndex');
        final response = await _retry(() async {
          final res = await http.post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          ).timeout(const Duration(seconds: 90));

          if (res.statusCode != 200) {
            final errorBody = jsonDecode(res.body);
            final errorMessage = errorBody['error']?['message'] ?? res.body;
            throw HttpExceptionWithStatusCode(errorMessage, res.statusCode);
          }
          return res;
        });
        // إذا نجح الطلب، أرجع الاستجابة فوراً
        return response;
      } on HttpExceptionWithStatusCode catch (e) {
        // إذا كان الخطأ بسبب الحصة، انتقل للمفتاح التالي
        if (e.statusCode == 429) {
          print('API key at index $_currentApiKeyIndex failed (rate limit). Switching to next key.');
          _currentApiKeyIndex++;
          // استمر في الحلقة لتجربة المفتاح التالي
        } else {
          // لأخطاء HTTP الأخرى، أوقف التنفيذ وأظهر الخطأ
          rethrow;
        }
      }
      // أي أخطاء أخرى (شبكة، تايم أوت) سيتم رميها من _retry
    }

    // إذا انتهت الحلقة، فهذا يعني أن جميع المفاتيح قد فشلت
    print('All API keys have been exhausted.');
    throw HttpExceptionWithStatusCode(
      "All API keys have reached their rate limit.", 
      429
    );
  }

  Future<String> generalChat({
    required String userMessage,
    required Project? project,
    required List<Bug> bugs,
    required List<AiChatMessage> history,
    String? codeContext,
  }) async {
    // ... (نفس كود بناء systemContext)
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
    if (codeContext != null && codeContext.isNotEmpty) {
      systemContext += '\n--- كود المشروع الكامل للتحليل ---\n';
      systemContext += codeContext;
      systemContext += '\n--- نهاية كود المشروع ---\n';
    }
    
    final List<Map<String, dynamic>> contents = history.map((msg) => {
        'role': msg.role,
        'parts': [{'text': msg.content}]
    }).toList();
    contents.add({'role': 'user', 'parts': [{'text': userMessage}]});

    final body = {
      'contents': contents,
      'systemInstruction': {'parts': [{'text': systemContext}]},
      'generationConfig': {'temperature': 0.8, 'maxOutputTokens': 1024},
    };

    try {
      final response = await _executeRequestWithKeyRotation('gemini-2.5-flash', body);
      final data = jsonDecode(response.body);
      if (data['candidates'] != null && data['candidates'].isNotEmpty) {
        return data['candidates'][0]['content']['parts'][0]['text'];
      }
      return "عذراً، لم يتمكن المساعد من إنشاء رد. قد تكون المشكلة متعلقة بسياسات السلامة.";
    } on HttpExceptionWithStatusCode catch (e) {
      if (e.statusCode == 429) {
        throw Exception("الذكاء الاصطناعي أُرهق قليلاً. يرجى الانتظار والمحاولة مرة أخرى بعد فترة.");
      }
      throw Exception("عذراً، حدث خطأ أثناء التواصل مع المساعد الذكي.\n${e.message}");
    } catch (e) {
      print('Gemini Service Exception: $e');
      throw Exception("عذراً، فشل الاتصال بخدمة الذكاء الاصطناعي: $e");
    }
  }

  Future<String> analyzeBugWithCodeContext({
    required Bug bug,
    required Project project,
    required String codeContext,
  }) async {
    // ... (نفس كود بناء systemPrompt و userPrompt)
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
    
    final body = {
      'contents': [{'parts': [{'text': userPrompt}]}],
      'systemInstruction': {'parts': [{'text': systemPrompt}]},
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 8192},
    };
    
    try {
      final response = await _executeRequestWithKeyRotation('gemini-2.5-pro', body);
      final data = jsonDecode(response.body);
      if (data['candidates'] != null && data['candidates'].isNotEmpty) {
        return data['candidates'][0]['content']['parts'][0]['text'];
      }
      throw Exception("عذراً، لم يتمكن المساعد من إنشاء رد.");
    } on HttpExceptionWithStatusCode catch (e) {
      if (e.statusCode == 429) {
        throw Exception("الذكاء الاصطناعي أُرهق قليلاً. يرجى الانتظار والمحاولة مرة أخرى بعد فترة.");
      }
      throw Exception("فشل الحصول على اقتراح بعد عدة محاولات: ${e.message}");
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
    // ... (نفس كود بناء auditDescription, allowedTypes, systemPrompt, userPrompt)
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

    final body = {
      'contents': [{'parts': [{'text': userPrompt}]}],
      'systemInstruction': {'parts': [{'text': systemPrompt}]},
      'generationConfig': {
        'temperature': 0.5,
        'maxOutputTokens': 8192,
        'responseMimeType': 'application/json',
      },
    };
    
    try {
      final response = await _executeRequestWithKeyRotation('gemini-2.5-pro', body);
      final data = jsonDecode(response.body);
      if (data['candidates'] != null && data['candidates'].isNotEmpty) {
        return data['candidates'][0]['content']['parts'][0]['text'];
      }
      throw Exception("لم يتمكن المساعد من إنشاء رد JSON.");
    } on HttpExceptionWithStatusCode catch (e) {
      if (e.statusCode == 429) {
        throw Exception("الذكاء الاصطناعي أُرهق قليلاً. يرجى الانتظار والمحاولة مرة أخرى بعد فترة.");
      }
      throw Exception("فشل الفحص الذكي بعد عدة محاولات: ${e.message}");
    } catch (e) {
      print('Gemini Service Exception (performAudit): $e');
      throw Exception("فشل الاتصال بالخدمة لإجراء الفحص: $e");
    }
  }
}

