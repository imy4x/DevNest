import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/bug.dart';
import '../models/project.dart';
import '../models/hub_member.dart'; 
import '../services/supabase_service.dart';
import '../widgets/bug_card.dart';
import '../add_bug_dialog.dart';
import '../widgets/app_dialogs.dart'; 
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

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

class BugTrackerViewState extends State<BugTrackerView> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  late Future<List<Bug>> _bugsFuture;
  late TabController _tabController;
  
  final List<String> _statuses = ['مفتوح', 'قيد التنفيذ', 'تم الحل'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length, vsync: this);
    refreshBugs();
  }
  
  Future<void> refreshBugs() async {
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Bug> _filterBugs(List<Bug> bugs, String status) {
    return bugs.where((bug) => bug.status == status).toList();
  }

  Future<void> _launchUrl(String? urlString) async {
    if (urlString != null) {
      final uri = Uri.parse(urlString);
      if (!await launchUrl(uri)) {
        if(mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الرابط: $urlString')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canAddBugs = widget.myMembership?.canAddBugs ?? false;
    final bool canManageProjects = widget.myMembership?.canManageProjects ?? false;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.project.description ?? 'لا يوجد وصف لهذا المشروع.', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: _statuses.map((status) => Tab(text: status)).toList(),
          ),
          Expanded(
            // --- ✨ تعديل (1): تم حذف RefreshIndicator --- ✨
            child: FutureBuilder<List<Bug>>(
              future: _bugsFuture,
              builder: (context, snapshot) {
                 if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  // --- ✨ تعديل (2): تبسيط واجهة الخطأ --- ✨
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('حدث خطأ: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: refreshBugs,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  // --- ✨ تعديل (3): تبسيط واجهة القائمة الفارغة --- ✨
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'لا توجد أخطاء في هذا المشروع حاليًا.',
                         textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final allBugs = snapshot.data!;
                return TabBarView(
                  controller: _tabController,
                  children: _statuses.map((status) {
                    final filteredBugs = _filterBugs(allBugs, status);
                    return _buildBugList(filteredBugs, 'أخطاء بالحالة "$status"');
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.bug_report),
            label: 'إضافة خطأ جديد',
            onTap: () {
              if (canAddBugs) {
                showDialog(
                  context: context,
                  builder: (context) => AddBugDialog(
                    projectId: widget.project.id,
                    onBugAdded: refreshBugs,
                  ),
                );
              } else {
                showPermissionDeniedDialog(context);
              }
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.edit),
            label: 'تعديل تفاصيل المشروع',
            onTap: () {
              if (canManageProjects) {
                widget.onEditProject();
              } else {
                showPermissionDeniedDialog(context);
              }
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.download_for_offline),
            label: 'تحميل آخر نسخة (APK)',
            backgroundColor: Colors.teal,
            onTap: () {
              if (widget.project.apkDownloadUrl != null) {
                _launchUrl(widget.project.apkDownloadUrl);
              } else {
                showInfoDialog(context, 'ملف غير موجود', 'لم يتم العثور على ملف APK في آخر إصدار للمشروع على GitHub.');
              }
            },
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

   Widget _buildBugList(List<Bug> bugs, String emptyListMessage) {
    if (bugs.isEmpty) {
      // --- ✨ تعديل (4): تبسيط واجهة القائمة الفارغة داخل التاب --- ✨
      return Center(child: Text('لا توجد $emptyListMessage'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: bugs.length,
      itemBuilder: (context, index) {
        return BugCard(
          bug: bugs[index],
          project: widget.project,
          onStatusChanged: refreshBugs,
          onDeleted: refreshBugs,
          myMembership: widget.myMembership,
        );
      },
    );
  }
}

