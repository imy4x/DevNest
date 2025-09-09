import 'package:flutter/material.dart';
import '../models/hub_member.dart'; 
import '../models/project.dart';
import '../services/supabase_service.dart';
import 'add_edit_project_dialog.dart';
import 'app_dialogs.dart';

class ProjectSidebar extends StatefulWidget {
  final Function(Project?) onProjectSelected;
  final Project? selectedProject;
  final HubMember? myMembership;

  const ProjectSidebar({
    super.key,
    required this.onProjectSelected,
    required this.selectedProject,
    required this.myMembership,
  });

  @override
  State<ProjectSidebar> createState() => _ProjectSidebarState();
}

class _ProjectSidebarState extends State<ProjectSidebar> {
  final SupabaseService _supabaseService = SupabaseService();
  late Future<List<Project>> _projectsFuture;

  bool get _isLeader => widget.myMembership?.role == 'leader';

  @override
  void initState() {
    super.initState();
    _refreshProjects();
  }

  Future<void> _refreshProjects() async {
    if (mounted) {
      setState(() {
        _projectsFuture = _supabaseService.getProjects();
      });
    }
  }

  void _showAddProjectDialog() {
    final canAdd = widget.myMembership?.canManageProjects ?? false;
    if (_isLeader || canAdd) {
      showDialog(
        context: context,
        builder: (context) => AddEditProjectDialog(
          onProjectSaved: (isNew) {
            _refreshProjects();
          },
        ),
      );
    } else {
      showPermissionDeniedDialog(context);
    }
  }

  void _deleteProject(Project project) async {
    // --- تعديل (3): إضافة التحقق من الصلاحية قبل الحذف ---
    final canManage = widget.myMembership?.canManageProjects ?? false;
    if (!_isLeader && !canManage) {
      showPermissionDeniedDialog(context);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المشروع'),
        content: Text(
            'هل أنت متأكد من رغبتك في حذف مشروع "${project.name}"؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('حذف', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabaseService.deleteProject(project.id);
        
        if (widget.selectedProject?.id == project.id) {
          widget.onProjectSelected(null);
        }
        
        _refreshProjects();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('فشل حذف المشروع: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            AppBar(
              title: const Text('المشاريع'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshProjects,
                  tooltip: 'تحديث القائمة',
                ),
              ],
            ),
            // --- تعديل (3): إظهار زر الإضافة دائماً والتحقق من الصلاحية عند الضغط ---
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('إضافة مشروع جديد'),
              tileColor: Theme.of(context).primaryColor.withAlpha(50),
              onTap: _showAddProjectDialog,
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<Project>>(
                future: _projectsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('خطأ: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'لا توجد مشاريع بعد. ابدأ بإضافة مشروع جديد!',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final projects = snapshot.data!;
                  return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return ListTile(
                        title: Text(project.name),
                        selected: widget.selectedProject?.id == project.id,
                        selectedTileColor:
                            Theme.of(context).primaryColor.withOpacity(0.3),
                        onTap: () {
                          widget.onProjectSelected(project);
                          Navigator.of(context).pop();
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _deleteProject(project),
                          tooltip: 'حذف المشروع',
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
