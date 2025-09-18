import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

/// An exception thrown when all available API keys have failed.
class AllApiKeysFailedException implements Exception {
  final String message;
  AllApiKeysFailedException(this.message);

  @override
  String toString() => message;
}

class GeminiService {
  int _currentApiKeyIndex = 0;
  final _random = Random();

  String _getApiUrl(String model, String apiKey) {
    return 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';
  }

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
            return text;
          }
        }
        
        final finishReason = candidate?['finishReason'];
        if (finishReason == 'SAFETY') {
          return "عذراً، لم أتمكن من إكمال الطلب لأنه يخالف سياسات السلامة.";
        }
        if (finishReason == 'MAX_TOKENS') {
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
  
  Future<String> _executeRequestAndParse({
    required String model,
    required Map<String, dynamic> body,
    required String Function(http.Response) parser,
  }) async {
    if (geminiApiKeys.isEmpty) {
      print('API keys list is empty.');
      throw Exception("فشل الاتصال: لا توجد مفاتيح API متاحة.");
    }

    final maxAttempts = geminiApiKeys.length;
    for (int i = 0; i < maxAttempts; i++) {
      int attemptIndex = (_currentApiKeyIndex + i) % maxAttempts;
      final apiKey = geminiApiKeys[attemptIndex];
      final apiUrl = _getApiUrl(model, apiKey);

      try {
        print('Using API Key index $attemptIndex');
        
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 180));

        if (response.statusCode == 200) {
          final parsedResult = parser(response);
          _currentApiKeyIndex = attemptIndex;
          return parsedResult;
        }

        if ([429, 500, 503].contains(response.statusCode)) {
          print('Key index $attemptIndex failed with status ${response.statusCode}. Switching to the next key.');
          throw HttpExceptionWithStatusCode('Server is busy or rate-limited', response.statusCode);
        } else {
          final errorBody = jsonDecode(response.body);
          final errorMessage = errorBody['error']?['message'] ?? response.body;
          throw HttpExceptionWithStatusCode(errorMessage, response.statusCode);
        }

      } catch (e) {
        if (e is SocketException || e is TimeoutException || e is MaxTokensException || e is HttpExceptionWithStatusCode) {
          print('Encountered a retriable error with key index $attemptIndex: ${e.runtimeType}.');
          
          if (i < maxAttempts - 1) {
            final backoffSeconds = pow(2, i + 1).toInt(); 
            final jitterMilliseconds = _random.nextInt(1000);
            final waitDuration = Duration(seconds: backoffSeconds, milliseconds: jitterMilliseconds);
            
            print('Waiting for ${waitDuration.inSeconds} seconds before next attempt...');
            await Future.delayed(waitDuration);
          }
        } else {
          print('Encountered a non-retriable error: $e');
          rethrow;
        }
      }
    }

    _currentApiKeyIndex = (_currentApiKeyIndex + 1) % maxAttempts;
    print('All API keys and retry attempts have failed.');
    throw AllApiKeysFailedException(
      "فشل الاتصال بالمساعد الذكي بعد تجربة كل المفاتيح المتاحة. قد تكون الخدمة مضغوطة حالياً (خطأ 429/503). يرجى المحاولة مرة أخرى لاحقاً."
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
تحدث باللغة العربية بأسلوب احترافي ومباشر، ويجب ان لا يتخطى الرد 500 كلمة فقط مهما كان.
**قواعد صارمة جداً يجب اتباعها:**
1.  **ممنوع الأكواد نهائياً:** لا تقم أبداً بإدراج أي كود برمجي، أو مقتطفات، أو أسماء ملفات بتنسيق الكود. يجب أن يكون ردك نصاً شرحياً فقط.
2.  **التشخيص:** اشرح السبب الجذري للمشكلة أو الاستفسار بوضوح.
3.  **الاقتراح:** صف الحل المقترح شفهياً. يمكنك الإشارة إلى المفاهيم العامة أو الوظائف التي يجب تعديلها دون كتابة الكود الفعلي. مثلاً: "لتنفيذ ذلك، ستحتاج إلى تعديل الدالة المسؤولة عن الحفظ في قاعدة البيانات لتشمل حقل التاريخ."
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
      'generationConfig': {'temperature': 0.8, 'maxOutputTokens': 8192},
    };

    try {
      return await _executeRequestAndParse(
        model: 'gemini-2.5-pro',
        body: body,
        parser: _parseTextFromResponse,
      );
    } catch (e) {
      print('Gemini Service Exception (generalChat): $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  List<String> _splitTextIntoChunks(String text, {int chunkSize = 700000, int overlap = 20000}) {
    if (text.length <= chunkSize) {
      return [text];
    }
    final chunks = <String>[];
    int start = 0;
    while (start < text.length) {
      final end = start + chunkSize;
      final chunk = text.substring(start, end > text.length ? text.length : end);
      chunks.add(chunk);
      start += (chunkSize - overlap);
    }
    return chunks;
  }
  
  /// ✅ --- (دالة مساعدة جديدة) لتجميع نتائج المقتطفات من الأجزاء المختلفة ---
  String _synthesizeSnippetResults(List<String> partialAnalyses) {
    if (partialAnalyses.isEmpty) {
      return "لم يتم إنشاء أي رد.";
    }
    if (partialAnalyses.length == 1) {
      return partialAnalyses.first;
    }

    print("Synthesizing ${partialAnalyses.length} snippet chunks locally...");

    final fullExplanation = StringBuffer();
    final allChanges = <dynamic>[];
    const startDelimiter = '--- CODE CHANGES START ---';
    const endDelimiter = '--- CODE CHANGES END ---';

    final uniqueExplanations = <String>{};

    for (final analysis in partialAnalyses) {
      final startIndex = analysis.indexOf(startDelimiter);
      
      String explanation = (startIndex != -1) 
          ? analysis.substring(0, startIndex).trim()
          : analysis.trim();
      
      if (explanation.isNotEmpty) {
          final lines = explanation.split('\n');
          for(final line in lines) {
              if (line.trim().isNotEmpty && uniqueExplanations.add(line.trim())) {
                  fullExplanation.writeln(line);
              }
          }
      }

      if (startIndex != -1) {
          final endIndex = analysis.indexOf(endDelimiter, startIndex);
          if (endIndex != -1) {
              final jsonString = analysis
                  .substring(startIndex + startDelimiter.length, endIndex)
                  .trim();
              try {
                final List<dynamic> changes = jsonDecode(jsonString);
                allChanges.addAll(changes);
              } catch (e) {
                print('Error parsing JSON from chunk: $e');
              }
          }
      }
    }
    
    final finalResponse = StringBuffer();
    finalResponse.writeln(fullExplanation.toString().trim());
    finalResponse.writeln();
    finalResponse.writeln(startDelimiter);
    finalResponse.writeln(jsonEncode(allChanges));
    finalResponse.writeln(endDelimiter);

    return finalResponse.toString();
  }

  /// ✅ --- (مُعدَّل) الآن تحلل كل الملفات مباشرة دون خطوة اختيار ---
  Future<String> analyzeBugAndSuggestSnippetsFromAllFiles({
    required Bug bug,
    required Project project,
    required String codeContext, // تستقبل كل الكود كنص واحد
    required Function(String) onStatusUpdate,
  }) async {
    onStatusUpdate('الذكاء الاصطناعي يحلل كل ملفات المشروع...');
    
    const solutionSystemPrompt = '''
أنت "مساعد DevNest"، خبير برمجي في Flutter. مهمتك هي تحليل مشكلة وتقديم حل متكامل.
**قواعد صارمة جداً للإخراج:**
1.  **الشرح أولاً:** ابدأ دائماً بشرح نصي واضح للمشكلة والحل المقترح بتنسيق Markdown.
2.  **محدد الأكواد:** بعد الشرح، أضف محدداً واضحاً: `--- CODE CHANGES START ---`.
3.  **تنسيق JSON:** بعد المحدد، ضع مصفوفة JSON صالحة. كل عنصر في المصفوفة يجب أن يكون كائناً يحتوي على ثلاثة مفاتيح: `file_path` (string)، `description` (string)، و `code_snippet` (string).
4.  **المحدد النهائي:** اختتم بمحدد `--- CODE CHANGES END ---`.
5.  **ممنوع الإضافات:** لا تضع أي نص أو تعليقات قبل أو بعد محددات بداية ونهاية الأكواد.
''';

    final partialAnalyses = <String>[];
    final codeChunks = _splitTextIntoChunks(codeContext, chunkSize: 700000, overlap: 20000);

    for (int i = 0; i < codeChunks.length; i++) {
        onStatusUpdate('جاري تحليل الجزء ${i + 1} من ${codeChunks.length} من الكود...');
        final chunk = codeChunks[i];
        final solutionUserPrompt = '''
--- تفاصيل المشكلة ---
العنوان: "${bug.title}"
الوصف: "${bug.description}"
--- سياق الكود من المشروع الكامل (الجزء ${i + 1}/${codeChunks.length}) ---
$chunk
--- نهاية السياق ---
المهمة: قم بتحليل المشكلة واقتراح **مقتطفات كود** للحل حسب القواعد الصارمة المحددة. لا تقم بإرجاع ملفات كاملة.
''';
        final solutionBody = {
            'contents': [{'parts': [{'text': solutionUserPrompt}]}],
            'systemInstruction': {'parts': [{'text': solutionSystemPrompt}]},
            'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 8192},
        };
        try {
            final result = await _executeRequestAndParse(model: 'gemini-2.5-pro', body: solutionBody, parser: _parseTextFromResponse);
            partialAnalyses.add(result);
        } catch (e) {
            print('Gemini Service Exception during full context analysis: $e');
            partialAnalyses.add("--- فشل تحليل الجزء ${i+1}: ${e.toString().replaceAll('Exception: ', '')} ---");
        }
    }
    
    return _synthesizeSnippetResults(partialAnalyses);
  }

  Future<String> performCodeAudit({
    required String codeContext,
    required String auditType,
    required List<Bug> existingBugs,
    required Function(String) onStatusUpdate,
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

    final codeChunks = _splitTextIntoChunks(codeContext);
    if (codeChunks.isEmpty) {
       return "[]";
    }
    
    final allNewBugs = <Map<String, dynamic>>[];
    final uniqueTitles = <String>{};
    for (var bug in existingBugs) {
      uniqueTitles.add(bug.title);
    }

    for (int i = 0; i < codeChunks.length; i++) {
        final statusMsg = 'جاري فحص الجزء ${i + 1} من ${codeChunks.length}...';
        print(statusMsg);
        onStatusUpdate(statusMsg);

        final chunk = codeChunks[i];
        final currentBugsList = existingBugs.map((b) => '- العنوان: ${b.title}\n  الوصف: ${b.description}').toList()
          ..addAll(allNewBugs.map((b) => '- العنوان: ${b['title']}\n  الوصف: ${b['description']}'));
        
        final chunkUserPrompt = '''
--- كود المشروع (الجزء ${i + 1}/${codeChunks.length}) ---
$chunk
--- نهاية كود المشروع ---
--- قائمة المشاكل الحالية (لا تقم بتكرار أي شيء منها أو ما يشبهها في المعنى) ---
${currentBugsList.isEmpty ? 'لا توجد مشاكل مسجلة حالياً.' : currentBugsList.join('\n')}
--- نهاية القائمة ---
المهمة: $auditDescription
الرجاء تحليل هذا الجزء من الكود وإرجاع النتائج بصيغة JSON حسب القواعد الصارمة المحددة.
''';

        final chunkBody = {
          'contents': [{'parts': [{'text': chunkUserPrompt}]}],
          'systemInstruction': {'parts': [{'text': systemPrompt}]},
          'generationConfig': { 'temperature': 0.5, 'maxOutputTokens': 8192, 'responseMimeType': 'application/json' },
        };
        
        try {
            final jsonStringResult = await _executeRequestAndParse(model: 'gemini-2.5-pro', body: chunkBody, parser: _parseJsonFromResponse);
            final List<dynamic> parsedJson = jsonDecode(jsonStringResult);
            for (var item in parsedJson) {
                if (item is Map<String, dynamic> && item.containsKey('title')) {
                   final title = item['title'] as String;
                   if (uniqueTitles.add(title)) {
                      allNewBugs.add(item);
                   }
                }
            }
        } catch (e) {
            print('Gemini Service Exception during chunk ${i+1} audit: $e');
        }
    }
    
    return jsonEncode(allNewBugs);
  }

  /// ✅ --- (دالة جديدة) للتحقق مما إذا كان قد تم حل خطأ معين ---
  Future<String> verifyFixInCode({
    required Bug bug,
    required String codeContext,
    required Function(String) onStatusUpdate,
  }) async {
    onStatusUpdate('الذكاء الاصطناعي يقرأ الكود للتحقق من الحل...');
    
    final systemPrompt = '''
أنت "مدقق جودة برمجيات"، خبير دقيق في تحليل شيفرة Flutter للتحقق من إصلاح الأخطاء.
مهمتك هي قراءة وصف مشكلة، ثم فحص الكود المقدم لتحديد ما إذا كانت المشكلة قد تم حلها بشكل فعال.
**قواعد صارمة جداً للإخراج:**
1.  **JSON فقط:** يجب أن يكون ردك عبارة عن سلسلة JSON صالحة وقابلة للتحليل **فقط**. لا تضف أي نص توضيحي أو علامات ```json```.
2.  **الدقة المطلقة:** قرارك يجب أن يكون مبنياً على دليل واضح في الكود. لا تخمن أبداً.
3.  **هيكل الـ JSON:** يجب أن يكون الـ JSON عبارة عن كائن (object) يحتوي على حقلين بالضبط: `resolved` (boolean), `reasoning` (String، شرح مختصر ومباشر لقرارك، لا يتجاوز 50 كلمة).
4.  **مثال للرد الصحيح:** `{"resolved": true, "reasoning": "تمت إضافة معالج الحالة المفقود في ملف user_controller.dart مما يمنع حدوث العطل عند فشل الشبكة."}`
5.  **مثال لرد خاطئ:** `{"resolved": false, "reasoning": "الكود المسؤول عن المشكلة في ملف api_service.dart لم يتغير."}`
''';

    final codeChunks = _splitTextIntoChunks(codeContext, chunkSize: 700000, overlap: 20000);
    if (codeChunks.isEmpty) {
       return '{"resolved": false, "reasoning": "لم يتم العثور على كود لتحليله."}';
    }
    
    final partialAnalyses = <String>[];

    for (int i = 0; i < codeChunks.length; i++) {
        onStatusUpdate('جاري تحليل الجزء ${i + 1} من ${codeChunks.length} من الكود...');
        final chunk = codeChunks[i];
        
        final analysisPrompt = '''
--- تفاصيل المشكلة ---
العنوان: "${bug.title}"
الوصف: "${bug.description}"
--- سياق الكود من المشروع الكامل (الجزء ${i + 1}/${codeChunks.length}) ---
$chunk
--- نهاية السياق ---
المهمة: قم بتحليل هذا الجزء من الكود. هل تجد فيه دليلاً على حل المشكلة الموصوفة أعلاه؟ قدم ملخصاً من جملة واحدة فقط عن النتائج التي توصلت إليها في هذا الجزء تحديداً.
''';

        final analysisBody = {
            'contents': [{'parts': [{'text': analysisPrompt}]}],
            'systemInstruction': {'parts': [{'text': 'أنت محلل كود مساعد. مهمتك هي تقديم ملخصات قصيرة جداً.'}]},
            'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 2048},
        };
        try {
            final result = await _executeRequestAndParse(model: 'gemini-2.5-pro', body: analysisBody, parser: _parseTextFromResponse);
            partialAnalyses.add("ملخص الجزء ${i + 1}: " + result);
        } catch (e) {
            print('Gemini Service Exception during verification chunk analysis: $e');
        }
    }
    
    onStatusUpdate('تجميع النتائج وإصدار القرار النهائي...');
    final synthesisPrompt = '''
--- تفاصيل المشكلة ---
العنوان: "${bug.title}"
الوصف: "${bug.description}"
--- ملخصات تحليل أجزاء الكود ---
${partialAnalyses.join('\n---\n')}
--- نهاية الملخصات ---
المهمة: بناءً على ملخصات التحليل أعلاه، اتخذ قراراً نهائياً. هل تم حل المشكلة؟ أجب بصيغة JSON حسب القواعد الصارمة المحددة لك.
''';
    
    final finalBody = {
        'contents': [{'parts': [{'text': synthesisPrompt}]}],
        'systemInstruction': {'parts': [{'text': systemPrompt}]},
        'generationConfig': {'temperature': 0.5, 'maxOutputTokens': 2048, 'responseMimeType': 'application/json'},
    };
    
    try {
        final jsonStringResult = await _executeRequestAndParse(model: 'gemini-2.5-pro', body: finalBody, parser: _parseJsonFromResponse);
        // Basic validation
        jsonDecode(jsonStringResult);
        return jsonStringResult;
    } catch (e) {
        print('Gemini Service Exception during final verification: $e');
        return '{"resolved": false, "reasoning": "حدث خطأ أثناء محاولة التحقق من الحل. $e"}';
    }
  }
}
