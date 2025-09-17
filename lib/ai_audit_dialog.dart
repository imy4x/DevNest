import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/bug.dart';
import '../models/project.dart';
import '../services/gemini_service.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_dialogs.dart';

// نموذج بسيط لتخزين نتائج الفحص
class AuditResult {
  final String title;
  final String description;
  final String type;
  bool isAdded = false;

  AuditResult(
      {required this.title, required this.description, required this.type});

  factory AuditResult.fromJson(Map<String, dynamic> json) {
    return AuditResult(
      title: json['title'] ?? 'بدون عنوان',
      description: json['description'] ?? 'لا يوجد وصف',
      type: json['type'] ?? 'بسيط',
    );
  }
}

class AiAuditDialog extends StatefulWidget {
  final Project project;
  final VoidCallback onBugsAdded;

  const AiAuditDialog(
      {super.key, required this.project, required this.onBugsAdded});

  @override
  State<AiAuditDialog> createState() => _AiAuditDialogState();
}

class _AiAuditDialogState extends State<AiAuditDialog> {
  String _auditType = 'bugs'; // 'bugs' or 'enhancements'
  String _state = 'idle'; // idle, loading_code, auditing, results, error
  String? _errorMessage;
  List<AuditResult> _results = [];

  final GeminiService _geminiService = GeminiService();
  final GitHubService _githubService = GitHubService();
  final SupabaseService _supabaseService = SupabaseService();

  Future<void> _startAudit() async {
    if (widget.project.githubUrl == null ||
        widget.project.githubUrl!.isEmpty) {
      setState(() {
        _state = 'error';
        _errorMessage = 'لا يمكن فحص المشروع. لم يتم ربطه بمستودع GitHub.';
      });
      return;
    }

    setState(() => _state = 'loading_code');
    try {
      final codeContext =
          await _githubService.fetchRepositoryCodeAsString(widget.project.githubUrl!);

      setState(() => _state = 'auditing');
      
      final List<Bug> existingBugs = 
          await _supabaseService.getBugsForProject(widget.project.id);

      final jsonResponse = await _geminiService.performCodeAudit(
        codeContext: codeContext,
        auditType: _auditType,
        existingBugs: existingBugs,
      );

      final List<dynamic> decodedJson = jsonDecode(jsonResponse);
      setState(() {
        _results =
            decodedJson.map((item) => AuditResult.fromJson(item)).toList();
        _state = 'results';
      });
    } catch (e) {
      if (mounted) {
        showTryAgainLaterDialog(context);
        setState(() {
           _state = 'idle';
        });
      }
    }
  }

  // ✅ --- (تعديل: إضافة مصدر الخطأ عند الإضافة) ---
  Future<void> _addResultToBugs(AuditResult result) async {
    try {
      final bugData = {
        'title': result.title,
        'description': result.description,
        'type': result.type,
        'project_id': widget.project.id,
        'status': 'جاري',
        'source': 'ai', // تحديد المصدر هنا
      };
      await _supabaseService.addBug(bugData);
      setState(() {
        result.isAdded = true;
      });
      widget.onBugsAdded(); // لتحديث القائمة الرئيسية
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, 'فشل إضافة العنصر: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('فحص ذكي للكود'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        child: _buildContent(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case 'idle':
        return _buildIdleView();
      case 'loading_code':
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('جاري تحميل الكود من GitHub...'),
            ],
          ),
        );
      case 'auditing':
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('الذكاء الاصطناعي يقوم بتحليل الكود الآن...'),
            ],
          ),
        );
      case 'error':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'حدث خطأ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_errorMessage ?? 'خطأ غير معروف', textAlign: TextAlign.center),
            ],
          ),
        );
      case 'results':
        return _buildResultsView();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildIdleView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'اختر نوع الفحص الذي تريد إجراءه على الكود:',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'bugs', label: Text('بحث عن أخطاء')),
            ButtonSegment(value: 'enhancements', label: Text('اقتراح تحسينات')),
          ],
          selected: {_auditType},
          onSelectionChanged: (newSelection) {
            setState(() {
              _auditType = newSelection.first;
            });
          },
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('ابدأ الفحص'),
          onPressed: _startAudit,
        ),
      ],
    );
  }

  Widget _buildResultsView() {
    if (_results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
             SizedBox(height: 16),
             Text('رائع! لم يتم العثور على أي مشاكل جديدة.'),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'تم العثور على ${_results.length} نتيجة جديدة:',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final result = _results[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(result.description),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          icon: Icon(result.isAdded
                              ? Icons.check
                              : Icons.add_circle_outline),
                          label: Text(result.isAdded ? 'تمت الإضافة' : 'إضافة للمشروع'),
                          onPressed: result.isAdded
                              ? null
                              : () => _addResultToBugs(result),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: result.isAdded
                                ? Colors.green
                                : Theme.of(context).primaryColor,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
