import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../models/bug.dart';
import '../models/hub_member.dart'; // ✨ --- استيراد موديل العضو --- ✨
import '../services/gemini_service.dart';
import '../services/supabase_service.dart';
import './app_dialogs.dart'; // ✨ --- استيراد ملف نوافذ الحوار --- ✨

class BugCard extends StatelessWidget {
  final Bug bug;
  final VoidCallback onStatusChanged;
  final VoidCallback onDeleted;
  final HubMember? myMembership; // ✨ --- استقبال صلاحيات المستخدم --- ✨
  
  const BugCard({
    super.key, 
    required this.bug,
    required this.onStatusChanged,
    required this.onDeleted,
    required this.myMembership, // ✨ --- استقبال صلاحيات المستخدم --- ✨
  });

  // --- تعديل: استخدام الحالات المترجمة لتحديد اللون ---
  Color _getStatusColor(String status) {
    switch (status) {
      case 'مفتوح': return Colors.orange.shade400;
      case 'قيد التنفيذ': return Colors.blue.shade400;
      case 'تم الحل': return Colors.green.shade400;
      default: return Colors.grey.shade400;
    }
  }

  // --- تعديل: استخدام الأنواع المترجمة لتحديد الأيقونة ---
  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'حرج': return Icons.error;
      case 'بسيط': return Icons.bug_report;
      case 'تحسين': return Icons.auto_awesome;
      default: return Icons.help_outline;
    }
  }
  
  void _showAiSuggestion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<String>(
          future: GeminiService().getBugSolution(bug.title, bug.description),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AlertDialog(
                title: Text('تحليل الخطأ...'),
                content: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('خطأ'),
                content: Text('فشل الحصول على اقتراح: ${snapshot.error}'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
              );
            }
            return AlertDialog(
              title: const Text('اقتراح من المساعد الذكي'),
              content: SingleChildScrollView(
                child: MarkdownBody(data: snapshot.data ?? 'لا يوجد اقتراح متاح.'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
              ],
            );
          },
        );
      },
    );
  }

  // --- تعديل: إضافة دالة تغيير الحالة ---
  void _changeStatus(BuildContext context) async {
    // ✨ --- التحقق من صلاحية تعديل الأخطاء --- ✨
    if (!(myMembership?.canEditBugs ?? false)) {
      showPermissionDeniedDialog(context);
      return;
    }

    final List<String> statuses = ['مفتوح', 'قيد التنفيذ', 'تم الحل'];
    // إزالة الحالة الحالية من الخيارات
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

  // --- تعديل: إضافة دالة حذف الخطأ ---
  void _deleteBug(BuildContext context) async {
    // ✨ --- التحقق من صلاحية تعديل الأخطاء --- ✨
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
                // عرض النوع والحالة باللغة العربية
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
                  DateFormat.yMMMd('ar').format(bug.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
