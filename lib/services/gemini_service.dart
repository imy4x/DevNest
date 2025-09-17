import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/ai_chat_message.dart';
import '../models/project.dart';
import '../models/bug.dart';
import 'package:http/http.dart' as http;
import '../config.dart'; // استيراد قائمة المفاتيح

/// استثناء مخصص للاحتفاظ بحالة كود الخطأ HTTP.
class HttpExceptionWithStatusCode implements Exception {
  final String message;
  final int statusCode;

  HttpExceptionWithStatusCode(this.message, this.statusCode);

  @override
  String toString() => 'HttpException: $message, StatusCode: $statusCode';
}

/// استثناء مخصص لتجاوز حد الـ tokens.
class MaxTokensException implements Exception {
  final String message = "الطلب أو الرد تجاوز الحد الأقصى للـ tokens.";

  @override
  String toString() => message;
}

class GeminiService {
  // متغير لتتبع المفتاح المستخدم حالياً
  int _currentApiKeyIndex = 0;

  // دالة مساعدة لإنشاء عنوان URL ديناميكياً
  String _getApiUrl(String model, String apiKey) {
    return 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';
  }

  /// دالة مساعدة لاستخلاص النص بأمان من ردود Gemini.
  String _parseTextFromResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      final candidates = data?['candidates'];

      if (candidates is List && candidates.isNotEmpty) {
        final candidate = candidates.first;
        final parts = candidate?['content']?['parts'];
        if (parts is List && parts.isNotEmpty) {
          final text = parts.first?['text'];
          if (text is String && text.isNotEmpty) {
            return text; // حالة النجاح
          }
        }
        
        final finishReason = candidate?['finishReason'];
        if (finishReason == 'SAFETY') {
          return "عذراً، لم أتمكن من إكمال الطلب لأنه يخالف سياسات السلامة.";
        }
        if (finishReason == 'MAX_TOKENS') {
          // الآن نرمي استثناءً مخصصاً ليتم معالجته في منطق تبديل المفاتيح
          throw MaxTokensException();
        }
      }

      print("Could not parse valid text from Gemini response: ${response.body}");
      return "عذراً، لم يتمكن المساعد من إنشاء رد. قد يكون الرد فارغاً أو بتنسيق غير متوقع.";
    } catch (e) {
      if (e is MaxTokensException) {
        rethrow;
      }
      print("Error parsing Gemini response body: ${response.body}. Exception: $e");
      return "عذراً، حدث خطأ أثناء معالجة استجابة المساعد الذكي.";
    }
  }

  /// دالة مساعدة لاستخلاص JSON بأمان من ردود Gemini.
  String _parseJsonFromResponse(http.Response response) {
      try {
        final data = jsonDecode(response.body);
        final candidates = data?['candidates'];

        if (candidates is List && candidates.isNotEmpty) {
          final candidate = candidates.first;
          final parts = candidate?['content']?['parts'];
          if (parts is List && parts.isNotEmpty) {
            final text = parts.first?['text'];
            if (text is String && text.isNotEmpty) {
              if (text.trim().startsWith('[') || text.trim().startsWith('{')) {
                  return text;
              }
            }
          }
          
          final finishReason = candidate?['finishReason'];
          if (finishReason == 'SAFETY') {
            return '[]'; 
          }
          if (finishReason == 'MAX_TOKENS') {
            throw MaxTokensException();
          }
        }
        
        print("Could not parse valid JSON from Gemini response: ${response.body}");
        return '[]';
      } catch (e) {
        if (e is MaxTokensException) {
          rethrow;
        }
        print("Error parsing Gemini JSON response body: ${response.body}. Exception: $e");
        return '[]';
      }
  }

  
  /// (الحل الجذري) - دالة مركزية جديدة لتنفيذ الطلبات ومعالجتها مع تبديل المفاتيح عند أي خطأ.
  Future<String> _executeRequestAndParse({
    required String model,
    required Map<String, dynamic> body,
    required String Function(http.Response) parser,
  }) async {
    // إعادة تعيين مؤشر المفتاح مع كل عملية جديدة
    _currentApiKeyIndex = 0; 
    
    while (_currentApiKeyIndex < geminiApiKeys.length) {
      final apiKey = geminiApiKeys[_currentApiKeyIndex];
      final apiUrl = _getApiUrl(model, apiKey);

      try {
        print('محاولة الاتصال بالـ API باستخدام المفتاح رقم: $_currentApiKeyIndex');
        
        // 1. تنفيذ طلب HTTP
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 90));

        // 2. التحقق من أكواد حالة HTTP
        if (response.statusCode != 200) {
          // *** التعديل هنا ***
          // الآن سيتم تبديل المفتاح أيضاً عند خطأ 503 (ضغط على الخادم)
          if (response.statusCode == 429 || response.statusCode == 503) { 
            print('المفتاح رقم $_currentApiKeyIndex فشل (السبب: ${response.statusCode}). سيتم التبديل للمفتاح التالي.');
            // ستستمر الحلقة للمفتاح التالي
          } else {
            // لأخطاء HTTP الحرجة الأخرى، أوقف التنفيذ فوراً
            final errorBody = jsonDecode(response.body);
            final errorMessage = errorBody['error']?['message'] ?? response.body;
            throw HttpExceptionWithStatusCode(errorMessage, response.statusCode);
          }
        } else {
          // 3. إذا كان الاتصال ناجحاً، قم بمعالجة الرد
          // هذه الدالة قد ترمي MaxTokensException
          final parsedResult = parser(response);
          return parsedResult; // نجاح!
        }
      
      } on MaxTokensException {
        print('الطلب تجاوز الحد الأقصى للـ tokens مع المفتاح $_currentApiKeyIndex. سيتم التبديل للمفتاح التالي.');
        // ستستمر الحلقة للمفتاح التالي
      } on SocketException catch (e) {
        print('فشل الاتصال بالشبكة (SocketException) مع المفتاح $_currentApiKeyIndex: $e. سيتم التبديل للمفتاح التالي.');
        // ستستمر الحلقة للمفتاح التالي
      } on TimeoutException catch (e) {
        print('انتهت مهلة الطلب (Timeout) مع المفتاح $_currentApiKeyIndex: $e. سيتم التبديل للمفتاح التالي.');
        // ستستمر الحلقة للمفتاح التالي
      }
      
      // إذا وصلنا هنا، فهذا يعني أن المفتاح الحالي فشل. انتقل إلى التالي
      _currentApiKeyIndex++;
      await Future.delayed(const Duration(seconds: 1)); // تأخير بسيط قبل المحاولة التالية
    }

    // إذا انتهت الحلقة، فهذا يعني أن جميع المفاتيح قد فشلت
    print('فشلت جميع مفاتيح الـ API.');
    throw Exception(
      "فشل الاتصال بالمساعد الذكي. قد تكون هناك مشكلة في الشبكة أو أن الخدمة مضغوطة حالياً. يرجى المحاولة مرة أخرى."
    );
  }

  Future<String> generalChat({
    required String userMessage,
    required Project? project,
    required List<Bug> bugs,
    required List<AiChatMessage> history,
    String? codeContext,
  }) async {
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
    
    final List<Map<String, dynamic>> contents = history.map((msg) => {
        'role': msg.role,
        'parts': [{'text': msg.content}]
    }).toList();

    final body = {
      'contents': contents,
      'systemInstruction': {'parts': [{'text': systemContext}]},
      'generationConfig': {'temperature': 0.8, 'maxOutputTokens': 1024},
    };

    try {
      // استخدام الدالة المركزية الجديدة
      return await _executeRequestAndParse(
        model: 'gemini-1.5-flash', // استخدام موديل أسرع للمحادثة
        body: body,
        parser: _parseTextFromResponse,
      );
    } catch (e) {
      print('Gemini Service Exception (generalChat): $e');
      // الاستثناء القادم من الدالة المركزية جاهز للعرض للمستخدم
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

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
    
    final body = {
      'contents': [{'parts': [{'text': userPrompt}]}],
      'systemInstruction': {'parts': [{'text': systemPrompt}]},
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 8192},
    };
    
    try {
      // استخدام الدالة المركزية الجديدة
      return await _executeRequestAndParse(
        model: 'gemini-1.5-pro', // استخدام موديل قوي لتحليل الكود
        body: body,
        parser: _parseTextFromResponse,
      );
    } catch (e) {
      print('Gemini Service Exception (analyzeBug): $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
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
      // استخدام الدالة المركزية الجديدة
      return await _executeRequestAndParse(
        model: 'gemini-1.5-pro',
        body: body,
        parser: _parseJsonFromResponse,
      );
    } catch (e) {
      print('Gemini Service Exception (performAudit): $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }
}

