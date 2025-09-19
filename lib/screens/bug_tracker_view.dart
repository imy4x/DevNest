import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:io';
import '../models/bug.dart';
import '../models/project.dart';
import '../models/hub_member.dart';
import '../services/supabase_service.dart';
import '../services/github_service.dart';
import '../widgets/bug_card.dart';
import '../add_bug_dialog.dart';
import '../ai_audit_dialog.dart';
import '../widgets/app_dialogs.dart';

class BugTrackerView extends StatefulWidget {
  final Project project;
  final VoidCallback onEditProject;
  final HubMember? myMembership;

  const BugTrackerView({
    super.key,
    required this.project,
    required this.onEditProject,
    required this.myMembership,
  });

  @override
  State<BugTrackerView> createState() => BugTrackerViewState();
}

class BugTrackerViewState extends State<BugTrackerView> {
  final SupabaseService _supabaseService = SupabaseService();
  final GitHubService _githubService = GitHubService();
  late Future<List<Bug>> _bugsFuture;

  @override
  void initState() {
    super.initState();
    refreshBugs();
  }

  void refreshBugs() {
    if (mounted) {
      setState(() {
        _bugsFuture = _supabaseService.getBugsForProject(widget.project.id);
      });
    }
  }

  @override
  void didUpdateWidget(covariant BugTrackerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.project.id != oldWidget.project.id) {
      refreshBugs();
    }
  }

  void _showAiAudit() {
    final canAudit = widget.myMembership?.canUseAiAudit ?? false;
    if (!canAudit) {
      showPermissionDeniedDialog(context);
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AiAuditDialog(project: widget.project, onBugsAdded: refreshBugs),
    );
  }

  Future<void> _downloadAndInstallFromGitHub() async {
    if (widget.project.githubUrl == null || widget.project.githubUrl!.isEmpty) {
      showErrorDialog(context, 'لم يتم ربط المشروع بمستودع GitHub.');
      return;
    }
    final status = await Permission.requestInstallPackages.request();
    if (status.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('الإذن مطلوب'),
            content: const Text('تم رفض إذن تثبيت التطبيقات بشكل دائم. الرجاء تفعيله يدوياً من إعدادات التطبيق للمتابعة.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              TextButton(onPressed: () { openAppSettings(); Navigator.pop(context); }, child: const Text('فتح الإعدادات')),
            ],
          ),
        );
      }
      return;
    }
    if (!status.isGranted) {
      if (mounted) showErrorDialog(context, 'يجب الموافقة على إذن تثبيت التطبيقات لإكمال العملية.');
      return;
    }

    final downloadNotifier = ValueNotifier<double?>(null);
    final statusNotifier = ValueNotifier<String>('جاري جلب معلومات الإصدار...');
    final releaseInfoNotifier = ValueNotifier<Map<String, String>>({});
    final cancelToken = CancelToken();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('تنزيل آخر إصدار'),
        content: AnimatedBuilder(
          animation: Listenable.merge([downloadNotifier, statusNotifier, releaseInfoNotifier]),
          builder: (context, child) {
            final progress = downloadNotifier.value;
            final statusText = statusNotifier.value;
            final releaseInfo = releaseInfoNotifier.value;
            return Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (releaseInfo['releaseTag'] != null) Chip(label: Text(releaseInfo['releaseTag']!, style: const TextStyle(fontWeight: FontWeight.bold))),
                const SizedBox(height: 8), Text(statusText), const SizedBox(height: 16),
                LinearProgressIndicator(value: progress),
                if (progress != null && progress > 0) Center(child: Text('${(progress * 100).toStringAsFixed(0)}%')),
                if (releaseInfo['releaseBody'] != null && releaseInfo['releaseBody']!.isNotEmpty) ...[
                  const Divider(height: 24), const Text('ملاحظات الإصدار:', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.2),
                    child: SingleChildScrollView(child: Text(releaseInfo['releaseBody']!)),
                  ),
                ]
              ],
            );
          },
        ),
        actions: [TextButton(onPressed: () { cancelToken.cancel('Download cancelled by user.'); Navigator.of(context).pop(); }, child: const Text('إلغاء'))],
      ),
    );

    String? savePath;
    try {
      final info = await _githubService.getLatestReleaseAssetInfo(widget.project.githubUrl!);
      final downloadUrl = info['downloadUrl']!;
      final fileName = info['fileName']!;
      releaseInfoNotifier.value = info;
      statusNotifier.value = 'جاري تنزيل: $fileName';
      downloadNotifier.value = 0.0;
      final dir = await getApplicationDocumentsDirectory();
      savePath = '${dir.path}/$fileName';
      await Dio().download(downloadUrl, savePath, onReceiveProgress: (received, total) {
        if (total != -1) downloadNotifier.value = received / total;
      }, cancelToken: cancelToken);
      if (mounted) Navigator.of(context).pop();
      if (savePath != null) await OpenFilex.open(savePath);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint("Download cancelled by user.");
        if (savePath != null) {
          final partialFile = File(savePath);
          if (await partialFile.exists()) await partialFile.delete();
        }
      } else {
        if (mounted) { Navigator.of(context).pop(); showErrorDialog(context, 'فشل تحميل التطبيق: ${e.message}'); }
      }
    } catch (e) {
      if (mounted) { Navigator.of(context).pop(); showErrorDialog(context, 'فشل تحميل التطبيق: ${e.toString().replaceFirst("Exception: ", "")}'); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canAddBugs = widget.myMembership?.canAddBugs ?? false;
    final bool canManageProjects = widget.myMembership?.canManageProjects ?? false;
    final bool canUseAiAudit = widget.myMembership?.canUseAiAudit ?? false;
    final bool hasGithubUrl = widget.project.githubUrl != null && widget.project.githubUrl!.isNotEmpty;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(widget.project.description ?? 'لا يوجد وصف لهذا المشروع.', style: Theme.of(context).textTheme.bodyMedium)],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Bug>>(
              future: _bugsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('حدث خطأ: ${snapshot.error}'));
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('لا توجد أخطاء في هذا المشروع حاليًا. عظيم!', textAlign: TextAlign.center)));
                
                final allBugs = snapshot.data!;
                final inProgressBugs = allBugs.where((b) => b.status == 'جاري').toList();
                final resolvedBugs = allBugs.where((b) => b.status == 'تم الحل').toList();
                final groupedInProgress = groupBy<Bug, String>(inProgressBugs, (bug) => bug.type);
                final criticalBugs = groupedInProgress['حرج'] ?? [];
                final simpleBugs = groupedInProgress['بسيط'] ?? [];
                final enhancementBugs = groupedInProgress['تحسين'] ?? [];

                return _buildBugList(
                  critical: criticalBugs,
                  simple: simpleBugs,
                  enhancements: enhancementBugs,
                  resolved: resolvedBugs,
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: SpeedDial(
        icon: Icons.add, activeIcon: Icons.close,
        backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white,
        children: [
          if (canUseAiAudit) SpeedDialChild(child: const Icon(Icons.auto_fix_high), label: 'فحص ذكي للكود', backgroundColor: Colors.deepPurple, onTap: _showAiAudit),
          if (canAddBugs) SpeedDialChild(child: const Icon(Icons.bug_report), label: 'إضافة خطأ/تحسين يدوي', onTap: () => showDialog(context: context, barrierDismissible: false, builder: (context) => AddBugDialog(projectId: widget.project.id, onBugAdded: refreshBugs))),
          if (canManageProjects) SpeedDialChild(child: const Icon(Icons.edit), label: 'تعديل تفاصيل المشروع', onTap: widget.onEditProject),
          if (hasGithubUrl) SpeedDialChild(child: const Icon(Icons.download_for_offline), label: 'تنزيل آخر إصدار من GitHub', backgroundColor: Colors.teal, onTap: _downloadAndInstallFromGitHub),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

  Widget _buildBugList({
    required List<Bug> critical,
    required List<Bug> simple,
    required List<Bug> enhancements,
    required List<Bug> resolved,
  }) {
    if (critical.isEmpty && simple.isEmpty && enhancements.isEmpty && resolved.isEmpty) {
      return const Center(child: Text('لا توجد عناصر هنا'));
    }
    
    // --- تعديل: منطق الترتيب الجديد ---
    // 1. ترتيب حسب الأولوية الشخصية (الأقل هو الأعلى)
    // 2. ثم ترتيب حسب تاريخ الإنشاء (الأحدث أولاً)
    final comparator = (Bug a, Bug b) {
      final priorityComparison = a.priorityOrder.compareTo(b.priorityOrder);
      if (priorityComparison != 0) return priorityComparison;
      return b.createdAt.compareTo(a.createdAt);
    };

    critical.sort(comparator);
    simple.sort(comparator);
    enhancements.sort(comparator);
    resolved.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // المحلولة لا تحتاج لأولوية

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        if (critical.isNotEmpty) _buildExpansionTile('أخطاء حرجة (${critical.length})', critical, Icons.error, Colors.red.shade300),
        if (simple.isNotEmpty) _buildExpansionTile('أخطاء بسيطة (${simple.length})', simple, Icons.bug_report, Colors.orange.shade300),
        if (enhancements.isNotEmpty) _buildExpansionTile('تحسينات (${enhancements.length})', enhancements, Icons.auto_awesome, Colors.blue.shade300),
        if (resolved.isNotEmpty) _buildExpansionTile('تم الحل (${resolved.length})', resolved, Icons.check_circle, Colors.green.shade300, initiallyExpanded: false),
      ],
    );
  }

  Widget _buildExpansionTile(String title, List<Bug> bugs, IconData icon, Color color, {bool initiallyExpanded = true}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(title),
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        children: bugs.map((bug) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: BugCard(
                project: widget.project,
                bug: bug,
                onStatusChanged: refreshBugs,
                onDeleted: refreshBugs,
                myMembership: widget.myMembership,
              ),
            )).toList(),
      ),
    );
  }
}
