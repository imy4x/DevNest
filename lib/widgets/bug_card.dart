import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../widgets/edit_bug_dialog.dart';
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
      1: 'يناير', 2: 'فبراير', 3: 'مارس', 4: 'أبريل', 5: 'مايو', 6: 'يونيو',
      7: 'يوليو', 8: 'أغسطس', 9: 'سبتمبر', 10: 'أكتوبر', 11: 'نوفمبر', 12: 'ديسمبر',
    };
    final day = date.day;
    final month = arabicMonths[date.month] ?? '';
    final year = date.year;
    return '$day $month $year';
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getTypeIcon(bug.type), color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Expanded(child: Text(bug.title)),
          ],
        ),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              const Text(
                'الوصف الكامل:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(bug.description),
              const Divider(height: 24),
              _buildDetailRow(context, 'الحالة:', 
                Chip(
                  label: Text(bug.status, style: TextStyle(color: _getStatusColor(bug.status), fontWeight: FontWeight.bold)),
                  backgroundColor: _getStatusColor(bug.status).withOpacity(0.2),
                  side: BorderSide.none,
                )
              ),
              _buildDetailRow(context, 'النوع:', 
                Chip(
                  label: Text(bug.type),
                  backgroundColor: Theme.of(context).cardColor,
                  side: BorderSide.none,
                ),
              ),
               // ✅ --- (إضافة مصدر الخطأ في نافذة التفاصيل) ---
              if (bug.source != null)
                _buildDetailRow(context, 'المصدر:', 
                  Chip(
                    avatar: Icon(bug.source == 'ai' ? Icons.auto_awesome : Icons.person, size: 16),
                    label: Text(bug.source == 'ai' ? 'مقترح AI' : 'يدوي'),
                    backgroundColor: Theme.of(context).cardColor,
                    side: BorderSide.none,
                  ),
                ),
              _buildDetailRow(context, 'تاريخ الإنشاء:', 
                Text(_formatDateManually(bug.createdAt), style: TextStyle(color: Colors.grey.shade400)),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('إغلاق'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
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
          value,
        ],
      ),
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
    String analysisState = 'idle'; // idle, fetching, analyzing, done, error
    String? errorMessage;
    int retryCount = 0;
    const maxRetries = 2;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> startAnalysis() async {
              if (analysisState == 'analyzing' || analysisState == 'fetching') return;
              
              try {
                if (retryCount == 0) {
                  setState(() => analysisState = 'fetching');
                } else {
                  setState(() {
                    analysisState = 'fetching'; 
                    errorMessage = 'فشل الطلب. جاري إعادة المحاولة ($retryCount/$maxRetries)...';
                  });
                }
                
                final codeContext = await githubService
                    .fetchRepositoryCodeAsString(project.githubUrl!);

                setState(() {
                  analysisState = 'analyzing';
                  errorMessage = null; 
                });

                final result = await geminiService.analyzeBugWithCodeContext(
                  bug: bug,
                  project: project,
                  codeContext: codeContext,
                );

                setState(() {
                  analysisResult = result;
                  analysisState = 'done';
                });

              } catch (e) {
                if (retryCount < maxRetries) {
                  retryCount++;
                  await Future.delayed(const Duration(seconds: 4));
                  if (context.mounted) {
                    startAnalysis();
                  }
                } else {
                  if(context.mounted) {
                      Navigator.of(context).pop();
                      showTryAgainLaterDialog(context);
                  }
                }
              }
            }

            if (analysisState == 'idle') {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => startAnalysis());
            }
            
            if (analysisState == 'done') {
               return _AiSolutionDialog(content: analysisResult);
            }

            return AlertDialog(
              title: const Text('فحص بالذكاء الاصطناعي'),
              content: _buildLoadingContent(context, analysisState, errorMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingContent(BuildContext context, String state, String? error) {
     switch (state) {
      case 'fetching':
      case 'idle':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(error ?? 'جاري تحميل الكود من GitHub...'),
            if (error == null)
              const Text('قد تستغرق هذه العملية لحظات.', style: TextStyle(fontSize: 12)),
          ],
        );
      case 'analyzing':
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('الذكاء الاصطناعي يقوم بالتحليل الآن...'),
          ],
        );
      default:
        return const SizedBox.shrink();
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

  void _editBug(BuildContext context) {
    if (!(myMembership?.canEditBugs ?? false)) {
      showPermissionDeniedDialog(context);
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditBugDialog(
        bug: bug,
        onBugEdited: onStatusChanged,
      ),
    );
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
          showErrorDialog(context, 'فشل الحذف: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(bug.status);
    final canEdit = myMembership?.canEditBugs ?? false;
    final isResolved = bug.status == 'تم الحل';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: statusColor.withOpacity(0.5), width: 1),
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
                  Expanded(
                    child: Text(
                      bug.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
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
                        },
                        itemBuilder: (context) {
                          List<PopupMenuEntry<String>> items = [];
                          if (!isResolved) {
                            items.add(const PopupMenuItem(value: 'edit', child: Text('تعديل')));
                            items.add(const PopupMenuItem(value: 'status', child: Text('تغيير الحالة')));
                             items.add(const PopupMenuDivider());
                          }
                          
                          items.add(const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('حذف', style: TextStyle(color: Colors.red))));

                          return items;
                        },
                      ),
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
                  // ✅ --- (إضافة أيقونة لتوضيح مصدر الخطأ) ---
                  if (bug.source != null)
                    Tooltip(
                      message: bug.source == 'ai' 
                          ? 'تمت إضافته بواسطة الذكاء الاصطناعي' 
                          : 'تمت إضافته يدويًا',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(
                          bug.source == 'ai' ? Icons.auto_awesome : Icons.person,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                  Text(
                    _formatDateManually(bug.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              if (!isResolved) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('فحص بالذكاء الاصطناعي'),
                    onPressed: () => _showAiSuggestion(context),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.5))),
                  ),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class _AiSolutionDialog extends StatelessWidget {
  final String content;

  const _AiSolutionDialog({required this.content});

  @override
  Widget build(BuildContext context) {
    final String explanation;
    final Map<String, String> files = {};

    final fileRegex = RegExp(r'--- START FILE: (.*?) ---\s*(.*?)\s*--- END FILE ---', dotAll: true);
    final firstMatch = fileRegex.firstMatch(content);

    if (firstMatch == null) {
      explanation = content.trim();
    } else {
      explanation = content.substring(0, firstMatch.start).trim();
      final matches = fileRegex.allMatches(content);
      for (final match in matches) {
        final path = match.group(1)?.trim();
        final code = match.group(2)?.trim();
        if (path != null && code != null && path.isNotEmpty) {
          files[path] = code;
        }
      }
    }

    final List<Tab> tabs = [const Tab(icon: Icon(Icons.description_outlined), text: 'الشرح')];
    final List<Widget> tabViews = [
      SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: MarkdownBody(data: explanation.isEmpty ? 'لم يتم تقديم شرح.' : explanation, selectable: true),
      ),
    ];

    files.forEach((path, code) {
      tabs.add(Tab(text: path));
      tabViews.add(_SingleFileView(filePath: path, codeContent: code));
    });

    return AlertDialog(
      title: const Text('اقتراح الحل'),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.75,
        child: DefaultTabController(
          length: tabs.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabs: tabs,
              ),
              Expanded(
                child: TabBarView(
                  children: tabViews,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}

class _SingleFileView extends StatelessWidget {
  final String filePath;
  final String codeContent;

  const _SingleFileView({required this.filePath, required this.codeContent});

  Future<void> _shareFile(BuildContext context) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${filePath.split('/').last}.txt');
      await file.writeAsString(codeContent);
      await Share.shareXFiles([XFile(file.path)], subject: 'مشاركة ملف: $filePath');
    } catch (e) {
      if(context.mounted) showErrorDialog(context, 'فشل مشاركة الملف: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: Theme.of(context).cardColor,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  filePath,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                tooltip: 'نسخ الكود',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: codeContent));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الكود بنجاح!')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 18),
                tooltip: 'مشاركة الملف',
                onPressed: () => _shareFile(context),
              )
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: '```dart\n$codeContent\n```',
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    code: const TextStyle(fontFamily: 'monospace', fontSize: 14.0),
                    codeblockDecoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
      ],
    );
  }
}

