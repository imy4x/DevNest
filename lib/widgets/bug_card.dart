import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'edit_bug_dialog.dart';
import '../models/bug.dart';
import '../models/hub_member.dart';
import '../models/project.dart';
import '../services/gemini_service.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import './app_dialogs.dart';

class BugCard extends StatelessWidget {
  final Project project;
  final Bug bug;
  final VoidCallback onStatusChanged;
  final VoidCallback onDeleted;
  final HubMember? myMembership;

  const BugCard({
    super.key,
    required this.project,
    required this.bug,
    required this.onStatusChanged,
    required this.onDeleted,
    required this.myMembership,
  });

  Color? _getPriorityColor(int? priority) {
    if (priority == null) return null;
    switch (priority) {
      case 1:
        return Colors.red.shade400;
      case 2:
        return Colors.orange.shade400;
      case 3:
        return Colors.yellow.shade600;
      case 4:
        return Colors.blue.shade300;
      case 5:
        return Colors.grey.shade400;
      default:
        return null;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'جاري':
        return Colors.blue.shade400;
      case 'تم الحل':
        return Colors.green.shade400;
      default:
        return Colors.grey.shade400;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'حرج':
        return Icons.error;
      case 'بسيط':
        return Icons.bug_report;
      case 'تحسين':
        return Icons.auto_awesome;
      default:
        return Icons.help_outline;
    }
  }

  String _formatDateManually(DateTime date) {
    const Map<int, String> arabicMonths = {
      1: 'يناير',
      2: 'فبراير',
      3: 'مارس',
      4: 'أبريل',
      5: 'مايو',
      6: 'يونيو',
      7: 'يوليو',
      8: 'أغسطس',
      9: 'سبتمبر',
      10: 'أكتوبر',
      11: 'نوفمبر',
      12: 'ديسمبر'
    };
    return '${date.day} ${arabicMonths[date.month] ?? ''} ${date.year}';
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [
          Icon(_getTypeIcon(bug.type), color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(child: Text(bug.title))
        ]),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              const Text('الوصف الكامل:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(bug.description),
              const Divider(height: 24),
              _buildDetailRow(
                  context,
                  'الحالة:',
                  Chip(
                      label: Text(bug.status,
                          style: TextStyle(
                              color: _getStatusColor(bug.status),
                              fontWeight: FontWeight.bold)),
                      backgroundColor:
                          _getStatusColor(bug.status).withOpacity(0.2),
                      side: BorderSide.none)),
              _buildDetailRow(context, 'النوع:',
                  Chip(label: Text(bug.type), backgroundColor: Theme.of(context).cardColor, side: BorderSide.none)),
              if (bug.source != null)
                _buildDetailRow(
                    context,
                    'المصدر:',
                    Chip(
                        avatar: Icon(
                            bug.source == 'ai'
                                ? Icons.auto_awesome
                                : Icons.person,
                            size: 16),
                        label:
                            Text(bug.source == 'ai' ? 'مقترح AI' : 'يدوي'),
                        backgroundColor: Theme.of(context).cardColor,
                        side: BorderSide.none)),
              _buildDetailRow(
                  context,
                  'تاريخ الإنشاء:',
                  Text(_formatDateManually(bug.createdAt),
                      style: TextStyle(color: Colors.grey.shade400))),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
              child: const Text('إغلاق'),
              onPressed: () => Navigator.of(context).pop())
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String title, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(color: Colors.grey.shade300)),
            value
          ]),
    );
  }

  void _showAiSuggestion(BuildContext context) {
    if (project.githubUrl == null || project.githubUrl!.isEmpty) {
      showErrorDialog(context,
          'لا يمكن تحليل الخطأ. لم يتم ربط هذا المشروع بمستودع GitHub.');
      return;
    }
    final githubService = GitHubService();
    final geminiService = GeminiService();
    String analysisResult = '';
    String analysisState = 'loading';
    String statusMessage = 'جاري التحضير...';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> startAnalysis() async {
              try {
                setState(
                    () => statusMessage = 'جاري تحميل كل ملفات المشروع...');
                final codeContext = await githubService
                    .fetchRepositoryCodeAsString(project.githubUrl!);
                final result =
                    await geminiService.analyzeBugAndSuggestSnippetsFromAllFiles(
                  bug: bug,
                  project: project,
                  codeContext: codeContext,
                  onStatusUpdate: (message) {
                    if (context.mounted) setState(() => statusMessage = message);
                  },
                );
                setState(() {
                  analysisResult = result;
                  analysisState = 'done';
                });
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  if (e is AllApiKeysFailedException)
                    showServiceUnavailableDialog(context, e.message);
                  else
                    showTryAgainLaterDialog(context);
                }
              }
            }

            if (analysisState == 'loading' &&
                statusMessage == 'جاري التحضير...')
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => startAnalysis());
            if (analysisState == 'done')
              return _AiSolutionDialog(rawContent: analysisResult);
            return AlertDialog(
              title: const Text('فحص بالذكاء الاصطناعي'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(statusMessage, textAlign: TextAlign.center)
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'))
              ],
            );
          },
        );
      },
    );
  }

  void _verifyFix(BuildContext context) {
    if (project.githubUrl == null || project.githubUrl!.isEmpty) {
      showErrorDialog(context,
          'لا يمكن التحقق من الحل. لم يتم ربط هذا المشروع بمستودع GitHub.');
      return;
    }
    final githubService = GitHubService();
    final geminiService = GeminiService();
    String statusMessage = 'جاري التحضير...';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> startVerification() async {
              try {
                setState(
                    () => statusMessage = 'جاري تحميل كل ملفات المشروع...');
                final codeContext = await githubService
                    .fetchRepositoryCodeAsString(project.githubUrl!);
                final resultJson = await geminiService.verifyFixInCode(
                  bug: bug,
                  codeContext: codeContext,
                  onStatusUpdate: (message) {
                    if (context.mounted) setState(() => statusMessage = message);
                  },
                );
                if (!context.mounted) return;
                Navigator.of(context).pop();
                final resultData = jsonDecode(resultJson);
                final bool isResolved = resultData['resolved'] ?? false;
                final String reasoning =
                    resultData['reasoning'] ?? 'لم يتم تقديم سبب.';
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Row(children: [
                      Icon(
                          isResolved
                              ? Icons.check_circle_outline
                              : Icons.highlight_off,
                          color: isResolved
                              ? Colors.green.shade400
                              : Colors.red.shade400),
                      const SizedBox(width: 8),
                      Text(isResolved ? 'يبدو أنه تم الحل' : 'لم يتم الحل بعد')
                    ]),
                    content: Text(reasoning),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('حسناً'))
                    ],
                  ),
                );
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  if (e is AllApiKeysFailedException)
                    showServiceUnavailableDialog(context, e.message);
                  else
                    showErrorDialog(context, 'حدث خطأ أثناء التحقق: $e');
                }
              }
            }

            if (statusMessage == 'جاري التحضير...')
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => startVerification());
            return AlertDialog(
              title: const Text('التحقق من الحل'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(statusMessage, textAlign: TextAlign.center)
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'))
              ],
            );
          },
        );
      },
    );
  }

  void _setPriority(BuildContext context) async {
    final newPriority = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const Text('حدد أولويتك الشخصية'),
              children: [
                ...List.generate(
                    5,
                    (index) => SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, index + 1),
                          child: Text('أولوية ${index + 1}'),
                        )),
                const Divider(),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, 0), // 0 يعني إزالة
                  child: const Text('إزالة الأولوية',
                      style: TextStyle(color: Colors.orange)),
                ),
              ],
            ));

    if (newPriority != null) {
      try {
        if (newPriority == 0) {
          await SupabaseService().clearBugPriority(bug.id);
        } else {
          await SupabaseService().setBugPriority(bug.id, newPriority);
        }
        onStatusChanged();
      } catch (e) {
        if (context.mounted) {
          showErrorDialog(context, 'فشل تحديد الأولوية: $e');
        }
      }
    }
  }

  void _changeStatus(BuildContext context) async {
    if (!(myMembership?.canEditBugs ?? false)) {
      showPermissionDeniedDialog(context);
      return;
    }
    final List<String> statuses = ['جاري', 'تم الحل'];
    statuses.remove(bug.status);
    final newStatus = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
          title: const Text('اختر الحالة الجديدة'),
          children: statuses
              .map((status) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, status),
                  child: Text(status)))
              .toList()),
    );
    if (newStatus != null) {
      try {
        await SupabaseService().updateBugStatus(bug.id, newStatus);
        onStatusChanged();
      } catch (e) {
        if (context.mounted)
          showErrorDialog(context, 'فشل تحديث الحالة: $e');
      }
    }
  }

  void _editBug(BuildContext context) {
    if (!(myMembership?.canEditBugs ?? false)) {
      showPermissionDeniedDialog(context);
      return;
    }
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            EditBugDialog(bug: bug, onBugEdited: onStatusChanged));
  }

  void _deleteBug(BuildContext context) async {
    if (!(myMembership?.canEditBugs ?? false)) {
      showPermissionDeniedDialog(context);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('حذف'),
        content: const Text('هل أنت متأكد من رغبتك في حذف هذا العنصر؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await SupabaseService().deleteBug(bug.id);
        onDeleted();
      } catch (e) {
        if (context.mounted) showErrorDialog(context, 'فشل الحذف: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(bug.status);
    final canEdit = myMembership?.canEditBugs ?? false;
    final isResolved = bug.status == 'تم الحل';
    // --- تعديل: لا يتم حساب لون الأولوية إذا تم الحل ---
    final priorityColor = isResolved ? null : _getPriorityColor(bug.userPriority);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: priorityColor ?? statusColor.withOpacity(0.5),
            width: priorityColor != null ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showDetailsDialog(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- تعديل: إخفاء الأولوية إذا تم الحل ---
                  if (bug.userPriority != null && !isResolved)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Tooltip(
                          message: 'أولويتك الشخصية: ${bug.userPriority}',
                          child: Icon(Icons.bookmark,
                              color: priorityColor, size: 20)),
                    ),
                  Expanded(
                      child: Text(bug.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18))),
                  if (canEdit)
                    SizedBox(
                      height: 36,
                      width: 36,
                      child: PopupMenuButton<String>(
                        tooltip: 'خيارات',
                        onSelected: (value) {
                          if (value == 'edit') _editBug(context);
                          if (value == 'status') _changeStatus(context);
                          if (value == 'delete') _deleteBug(context);
                          if (value == 'priority') _setPriority(context);
                        },
                        itemBuilder: (context) {
                          List<PopupMenuEntry<String>> items = [];
                          // --- تعديل: لا تعرض خيار الأولوية إذا تم الحل ---
                          if (!isResolved) {
                            items.add(const PopupMenuItem(
                                value: 'priority',
                                child: Text('تحديد الأولوية')));
                            items.add(const PopupMenuDivider());
                            items.add(const PopupMenuItem(
                                value: 'edit', child: Text('تعديل')));
                            items.add(const PopupMenuItem(
                                value: 'status',
                                child: Text('تغيير الحالة')));
                            items.add(const PopupMenuDivider());
                          }
                          items.add(const PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف',
                                  style: TextStyle(color: Colors.red))));
                          return items;
                        },
                      ),
                    )
                ],
              ),
              const SizedBox(height: 8),
              Text(bug.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[400])),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(_getTypeIcon(bug.type), size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(bug.type, style: TextStyle(color: Colors.grey[400])),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(bug.status,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  if (bug.source != null)
                    Tooltip(
                        message: bug.source == 'ai'
                            ? 'تمت إضافته بواسطة الذكاء الاصطناعي'
                            : 'تمت إضافته يدويًا',
                        child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Icon(
                                bug.source == 'ai'
                                    ? Icons.auto_awesome
                                    : Icons.person,
                                size: 16,
                                color: Colors.grey[400]))),
                  Text(_formatDateManually(bug.createdAt),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
              if (!isResolved) ...[
                const SizedBox(height: 12),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                        icon: const Icon(Icons.auto_fix_high_outlined,
                            size: 18),
                        label: const Text('فحص بالذكاء الاصطناعي'),
                        onPressed: () => _showAiSuggestion(context),
                        style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Theme.of(context)
                                    .primaryColor
                                    .withOpacity(0.5))))),
                const SizedBox(height: 8),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                        icon: const Icon(Icons.task_alt_outlined, size: 18),
                        label: const Text('التحقق من الحل آلياً'),
                        onPressed: () => _verifyFix(context),
                        style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.cyan.withOpacity(0.5))))),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class _AiSolutionDialog extends StatelessWidget {
  final String rawContent;
  const _AiSolutionDialog({required this.rawContent});

  Map<String, dynamic> _parseSolution() {
    const startDelimiter = '--- CODE CHANGES START ---';
    const endDelimiter = '--- CODE CHANGES END ---';
    final startIndex = rawContent.indexOf(startDelimiter);
    final endIndex = rawContent.indexOf(endDelimiter, startIndex);
    if (startIndex == -1 || endIndex == -1)
      return {'explanation': rawContent, 'changes': [], 'error': null};
    final explanation = rawContent.substring(0, startIndex).trim();
    final jsonString =
        rawContent.substring(startIndex + startDelimiter.length, endIndex).trim();
    try {
      final changes = jsonDecode(jsonString);
      return {'explanation': explanation, 'changes': changes, 'error': null};
    } catch (e) {
      return {
        'explanation': explanation,
        'changes': [],
        'error': jsonString
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final solution = _parseSolution();
    final String explanation = solution['explanation'];
    final List<dynamic> changes = solution['changes'];
    final String? errorJson = solution['error'];

    return AlertDialog(
      title: const Text('اقتراح الحل'),
      contentPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height * 0.75,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(tabs: [
                Tab(icon: Icon(Icons.description_outlined), text: 'الشرح'),
                Tab(icon: Icon(Icons.code_outlined), text: 'الأكواد المقترحة')
              ]),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: MarkdownBody(
                            data: explanation.isEmpty
                                ? 'لم يتم تقديم شرح.'
                                : explanation,
                            selectable: true)),
                    errorJson != null
                        ? _buildErrorView(errorJson)
                        : (changes.isEmpty
                            ? const Center(
                                child: Text('لا توجد تعديلات كود مقترحة.'))
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: changes.length,
                                itemBuilder: (context, index) {
                                  final change = changes[index];
                                  return _CodeModificationCard(
                                      filePath: change['file_path'] ?? 'N/A',
                                      description:
                                          change['description'] ?? 'N/A',
                                      codeSnippet:
                                          change['code_snippet'] ?? 'N/A');
                                },
                              )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'))
      ],
    );
  }

  Widget _buildErrorView(String errorJson) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('فشل تحليل مقترحات الكود',
              style: TextStyle(
                  color: Colors.red.shade300,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
              'لم يتمكن التطبيق من فهم تنسيق الكود الذي أرسله الذكاء الاصطناعي. هذا هو النص الخام الذي تم استلامه:'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade700)),
            child: SelectableText(
                errorJson.isEmpty ? '(تم استلام نص فارغ)' : errorJson,
                style: const TextStyle(
                    fontFamily: 'monospace', color: Colors.yellow)),
          ),
        ],
      ),
    );
  }
}

class _CodeModificationCard extends StatelessWidget {
  final String filePath, description, codeSnippet;
  const _CodeModificationCard(
      {required this.filePath,
      required this.description,
      required this.codeSnippet});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 1,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.withOpacity(0.2))),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade800
                : Colors.grey.shade200,
            child: Text(filePath,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade300, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(description))
                ]),
                const Divider(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withOpacity(0.3))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Directionality(
                          textDirection: TextDirection.ltr,
                          child: SelectableText(codeSnippet,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 13))),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.copy_all_outlined, size: 16),
                          label: const Text('نسخ الكود'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: codeSnippet));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('تم نسخ مقتطف الكود بنجاح!'),
                                    duration: Duration(seconds: 2)));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
