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
    // ✨ --- Define permissions for easier access --- ✨
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
            child: FutureBuilder<List<Bug>>(
              future: _bugsFuture,
              builder: (context, snapshot) {
                 if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('حدث خطأ: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'لا توجد أخطاء في هذا المشروع حاليًا. عظيم!',
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
          // ✨ --- Add Bug button with permission check --- ✨
          if(canAddBugs)
            SpeedDialChild(
              child: const Icon(Icons.bug_report),
              label: 'إضافة خطأ جديد',
              onTap: () {
                  showDialog(
                  context: context,
                  builder: (context) => AddBugDialog(
                    projectId: widget.project.id,
                    onBugAdded: refreshBugs,
                  ),
                );
              }
            ),
          // ✨ --- Edit Project button with permission check --- ✨
          if (canManageProjects)
            SpeedDialChild(
              child: const Icon(Icons.edit),
              label: 'تعديل تفاصيل المشروع',
              onTap: widget.onEditProject,
            ),
          if (widget.project.apkDownloadUrl != null)
            SpeedDialChild(
              child: const Icon(Icons.download_for_offline),
              label: 'تحميل آخر نسخة (APK)',
              backgroundColor: Colors.teal,
              onTap: () => _launchUrl(widget.project.apkDownloadUrl),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

   Widget _buildBugList(List<Bug> bugs, String emptyListMessage) {
    if (bugs.isEmpty) {
      return Center(
        child: Text('لا توجد $emptyListMessage'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: bugs.length,
      itemBuilder: (context, index) {
        return BugCard(
          bug: bugs[index],
          onStatusChanged: refreshBugs,
          onDeleted: refreshBugs,
          myMembership: widget.myMembership,
        );
      },
    );
  }
}
