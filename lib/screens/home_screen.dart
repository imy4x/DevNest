import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import '../models/hub.dart';
import '../models/hub_member.dart';
import '../services/supabase_service.dart';
import 'bug_tracker_view.dart';
import '../widgets/ai_assistant_panel.dart';
import '../widgets/project_sidebar.dart';
import '../widgets/add_edit_project_dialog.dart';
import 'hub_management_screen.dart';
import 'initial_hub_screen.dart';
import 'dart:async';

enum HubLoadState { loading, loaded, error }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  Project? _selectedProject;
  Hub? _currentHub;
  HubMember? _myMembership;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<BugTrackerViewState> _bugTrackerKey = GlobalKey<BugTrackerViewState>();

  HubLoadState _hubLoadState = HubLoadState.loading;

  StreamSubscription? _hubMembersSubscription;
  StreamSubscription? _hubSubscription;
  Timer? _kickCheckTimer;

  bool get _isLeader => _myMembership?.role == 'leader';

  @override
  void initState() {
    super.initState();
    _loadHubInfoWithRetry();
  }

  @override
  void dispose() {
    _hubMembersSubscription?.cancel();
    _hubSubscription?.cancel();
    _kickCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHubInfoWithRetry({int retries = 3}) async {
    if (!mounted) return;

    setState(() {
      _hubLoadState = HubLoadState.loading;
    });

    for (int i = 0; i < retries; i++) {
      try {
        final hub = await _supabaseService.getHubForUser();
        if (hub != null && mounted) {
          final member = await _supabaseService.getMemberInfo(hub.id);
          if (member != null) {
            setState(() {
              _currentHub = hub;
              _myMembership = member;
              _hubLoadState = HubLoadState.loaded;
            });
            _setupRealtimeListeners(hub.id);
            return;
          }
        }
      } catch (e) {
        debugPrint('Error loading hub info (attempt ${i + 1}): $e');
      }

      if (i < retries - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (mounted) {
      setState(() {
        _hubLoadState = HubLoadState.error;
      });
      _handleHubDeleted();
    }
  }

  void _handleMemberKicked() {
    _cleanupAndNavigate(
      title: 'تم طردك',
      content:
          'لقد تم إزالتك من الـ Hub. يجب عليك الانضمام إلى hub جديد أو إنشاء واحد.',
    );
  }

  void _handleHubDeleted() {
    _cleanupAndNavigate(
      title: 'Hub لم يعد موجوداً',
      content:
          'يبدو أن الـ Hub الذي كنت فيه قد تم حذفه. يجب عليك الانضمام أو إنشاء hub جديد.',
    );
  }

  void _cleanupAndNavigate(
      {required String title, required String content}) async {
    if (!mounted) return;

    _hubMembersSubscription?.cancel();
    _hubSubscription?.cancel();
    _kickCheckTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hub_setup_complete', false);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const InitialHubScreen()),
                (route) => false,
              );
            },
            child: const Text('موافق'),
          )
        ],
      ),
    );
  }

  Future<void> _checkIfKicked() async {
    if (_currentHub == null || !mounted) return;

    try {
      final member = await _supabaseService.getMemberInfo(_currentHub!.id);
      if (member == null && mounted) {
        _handleMemberKicked();
      }
    } catch (e) {
      debugPrint("Error during periodic kick check: $e");
    }
  }

  void _setupRealtimeListeners(String hubId) {
    _hubMembersSubscription?.cancel();
    _hubSubscription?.cancel();
    _kickCheckTimer?.cancel();

    _hubMembersSubscription =
        _supabaseService.getHubMembersStream(hubId).listen((membersList) {
      if (!mounted) return;

      final currentUserStillAMember = membersList
          .any((m) => m['user_id'] == _supabaseService.currentUserId);

      if (currentUserStillAMember) {
        final myData = membersList
            .firstWhere((m) => m['user_id'] == _supabaseService.currentUserId);
        if (mounted) {
          setState(() {
            _myMembership = HubMember.fromJson(myData);
          });
        }
      } else {
        _handleMemberKicked();
      }
    });

    _hubSubscription = _supabaseService.getHubStream(hubId).listen((hub) {
      if (!mounted) return;
      if (hub == null) {
        _handleHubDeleted();
      } else {
        if (mounted) {
          setState(() {
            _currentHub = hub;
          });
        }
      }
    });

    _kickCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkIfKicked();
    });
  }

  void _onProjectSelected(Project? project) {
    setState(() {
      _selectedProject = project;
    });
  }

  void _editProject(Project project) {
    showDialog(
      context: context,
      builder: (context) => AddEditProjectDialog(
        project: project,
        onProjectSaved: (isNew) async {
          final projects = await _supabaseService.getProjects();
          setState(() {
            _selectedProject = projects.firstWhere((p) => p.id == project.id,
                orElse: () => project);
          });
        },
      ),
    );
  }

  Future<void> _confirmAndLeaveHub() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد المغادرة'),
        content: const Text(
            'هل أنت متأكد من رغبتك في مغادرة هذا الـ Hub؟ ستحتاج إلى رمز سري جديد للانضمام مرة أخرى.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('مغادرة', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && _myMembership != null) {
      try {
        await _supabaseService.leaveHub(_myMembership!.id);
        _cleanupAndNavigate(
            title: 'لقد غادرت', content: 'لقد غادرت الـ Hub بنجاح.');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('فشل في المغادرة: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }
  
  void _showHubInfo() {
    if (_currentHub == null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('معلومات Hub: ${_currentHub!.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الرمز السري لمشاركة الفريق:'),
            const SizedBox(height: 8),
            SelectableText(
              _currentHub!.secretCode,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          if (_isLeader)
            TextButton.icon(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('إدارة الأعضاء'),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            HubManagementScreen(hub: _currentHub!)));
              },
            ),
          if (!_isLeader)
            TextButton.icon(
              icon: Icon(Icons.exit_to_app, color: Colors.red.shade400),
              label: Text('مغادرة الـ Hub', style: TextStyle(color: Colors.red.shade400)),
              onPressed: () {
                Navigator.pop(context); 
                _confirmAndLeaveHub();
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hubLoadState == HubLoadState.loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('جاري تحميل بيانات الفريق...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_selectedProject?.name ?? _currentHub?.name ?? 'DevNest'),
        actions: [
          // --- ✨ تعديل (1): إضافة زر تحديث يظهر عند اختيار مشروع --- ✨
          if (_selectedProject != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _bugTrackerKey.currentState?.refreshBugs();
              },
              tooltip: 'تحديث قائمة الأخطاء',
            ),
          if (_currentHub != null)
            IconButton(
              icon: const Icon(Icons.hub_outlined),
              onPressed: _showHubInfo,
              tooltip: 'معلومات الـ Hub',
            ),
          IconButton(
            icon: const Icon(Icons.psychology_alt),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'فتح المساعد الذكي',
          ),
        ],
      ),
      drawer: ProjectSidebar(
        onProjectSelected: _onProjectSelected,
        selectedProject: _selectedProject,
        myMembership: _myMembership,
      ),
      endDrawer: AiAssistantPanel(
        projectContext: _selectedProject,
        myMembership: _myMembership,
      ),
      body: _selectedProject == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.rule_folder_outlined,
                        size: 100, color: Colors.grey[700]),
                    const SizedBox(height: 24),
                    Text(
                      'الرجاء اختيار مشروع من القائمة للبدء',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أو قم بإنشاء مشروع جديد',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : BugTrackerView(
              key: _bugTrackerKey,
              project: _selectedProject!,
              onEditProject: () => _editProject(_selectedProject!),
              myMembership: _myMembership,
            ),
    );
  }
}
