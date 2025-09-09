import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/bug.dart';
import '../models/hub_member.dart';
import '../models/project.dart';
import '../services/gemini_service.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import './app_dialogs.dart';

class BugCard extends StatelessWidget {
  final Bug bug;
  final Project project;
  final VoidCallback onStatusChanged;
  final VoidCallback onDeleted;
  final HubMember? myMembership;
  
  const BugCard({
    super.key, 
    required this.bug,
    required this.project,
    required this.onStatusChanged,
    required this.onDeleted,
    required this.myMembership,
  });

  Color _getStatusColor(String status) {
    switch (status) {
      case 'مفتوح': return Colors.orange.shade400;
      case 'قيد التنفيذ': return Colors.blue.shade400;
      case 'تم الحل': return Colors.green.shade400;
      default: return Colors.grey.shade400;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'حرج': return Icons.error;
      case 'بسيط': return Icons.bug_report;
      case 'تحسين': return Icons.auto_awesome;
      default: return Icons.help_outline;
    }
  }
  
  void _showAiSuggestion(BuildContext context) async {
    if (project.githubUrl == null || project.githubUrl!.isEmpty) {
      showInfoDialog(
        context,
        'تحليل الكود غير متاح',
        'لتحليل هذا الخطأ مع الكود، يجب إضافة رابط مستودع GitHub للمشروع.',
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('تحليل الخطأ مع الكود...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('يتم قراءة ملفات المشروع وتحليلها، قد تستغرق هذه العملية بعض الوقت...'),
          ],
        ),
      ),
    );

    try {
      final githubService = GitHubService();
      final geminiService = GeminiService();

      final codeContext = await githubService.fetchRepositoryCodeAsString(project.githubUrl!);
      
      final rawJsonResult = await geminiService.analyzeBugWithCodeContext(
        bugTitle: bug.title,
        bugDescription: bug.description,
        codeContext: codeContext,
      );

      if (context.mounted) Navigator.pop(context);

      final analysisData = jsonDecode(rawJsonResult) as Map<String, dynamic>;
      final verbalAnalysis = analysisData['verbalAnalysis'] as String? ?? 'لم يتم توفير تحليل.';
      final codeSuggestions = analysisData['codeSuggestions'] as String? ?? 'لم يتم توفير اقتراحات للكود.';
      final professionalPrompt = analysisData['professionalPrompt'] as String? ?? 'لم يتم إنشاء برومبت.';
      
      _showInteractiveAnalysisDialog(context, verbalAnalysis, codeSuggestions, professionalPrompt);

    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        showErrorDialog(context, 'فشل تحليل الخطأ: $e');
      }
    }
  }

  void _showInteractiveAnalysisDialog(BuildContext context, String verbalAnalysis, String codeSuggestions, String professionalPrompt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحليل المساعد الذكي'),
        content: SingleChildScrollView(
          child: MarkdownBody(
            data: verbalAnalysis,
            onTapLink: (text, href, title) {
              if(href != null) launchUrl(Uri.parse(href));
            },
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: <Widget>[
          TextButton.icon(
            icon: const Icon(Icons.code, size: 18),
            label: const Text('عرض تعديلات الكود'),
            onPressed: () {
              _showCodeSuggestionsDialog(context, codeSuggestions);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('استخدام البرومبت'),
            onPressed: () {
              _showProfessionalPromptDialog(context, professionalPrompt);
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showCodeSuggestionsDialog(BuildContext context, String codeSuggestions) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('التعديلات المقترحة على الكود'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: SingleChildScrollView(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MarkdownBody(
                data: codeSuggestions, 
                selectable: true,
                onTapLink: (text, href, title) {
                  if(href != null) launchUrl(Uri.parse(href));
                },
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
  
  void _showProfessionalPromptDialog(BuildContext context, String professionalPrompt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('البرومبت الاحترافي'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'يمكنك نسخ هذا النص وإرساله إلى مساعد ذكاء اصطناعي آخر مع الملفات المذكورة فيه للحصول على مساعدة إضافية.',
                style: TextStyle(fontSize: 14),
              ),
              const Divider(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade700)
                ),
                child: SelectableText(
                  professionalPrompt,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton.icon(
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('نسخ البرومبت'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: professionalPrompt));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ البرومبت إلى الحافظة')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }


  void _changeStatus(BuildContext context) async {
    if (!(myMembership?.canEditBugs ?? false)) {
      showPermissionDeniedDialog(context);
      return;
    }

    final List<String> statuses = ['مفتوح', 'قيد التنفيذ', 'تم الحل'];
    statuses.remove(bug.status);

    final newStatus = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('اختر الحالة الجديدة'),
          children: statuses.map((status) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, status),
              child: Text(status),
            );
          }).toList(),
        );
      },
    );

    if (newStatus != null) {
      try {
        await SupabaseService().updateBugStatus(bug.id, newStatus);
        onStatusChanged();
      } catch (e) {
        if (context.mounted) {
          showErrorDialog(context, 'فشل تحديث الحالة: $e');
        }
      }
    }
  }

  void _deleteBug(BuildContext context) async {
    if (!(myMembership?.canEditBugs ?? false)) {
      showPermissionDeniedDialog(context);
      return;
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الخطأ'),
        content: const Text('هل أنت متأكد من رغبتك في حذف هذا الخطأ؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService().deleteBug(bug.id);
        onDeleted();
      } catch (e) {
        if (context.mounted) {
          showErrorDialog(context, 'فشل حذف الخطأ: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(bug.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: statusColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    bug.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                PopupMenuButton<int>(
                   onSelected: (value) {
                    if (value == 0) _changeStatus(context);
                    if (value == 1) _deleteBug(context);
                   },
                   itemBuilder: (context) => [
                      const PopupMenuItem(value: 0, child: Text('تغيير الحالة')),
                      const PopupMenuItem(value: 1, child: Text('حذف الخطأ')),
                   ],
                )
              ],
            ),
            const SizedBox(height: 8),
            Text(
              bug.description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[400]),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(_getTypeIcon(bug.type), size: 16, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(bug.type, style: TextStyle(color: Colors.grey[400])),
                const SizedBox(width: 8),
                Container(
                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                   decoration: BoxDecoration(
                     color: statusColor.withOpacity(0.2),
                     borderRadius: BorderRadius.circular(8)
                   ),
                   child: Text(bug.status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(
                  // ✨ تعديل: عرض التاريخ بصيغة YYYY-MM-DD
                  '${bug.createdAt.year}-${bug.createdAt.month.toString().padLeft(2, '0')}-${bug.createdAt.day.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500], letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (bug.status != 'تم الحل')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.psychology_alt, size: 18),
                  label: const Text('فحص الخطأ بالذكاء الاصطناعي'),
                  onPressed: () => _showAiSuggestion(context),
                  style: OutlinedButton.styleFrom(
                     side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5))
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}

