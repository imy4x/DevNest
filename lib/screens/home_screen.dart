import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/project.dart';
import '../models/hub.dart';
import '../models/hub_member.dart';
import '../services/supabase_service.dart';
import '../screens/bug_tracker_view.dart';
import '../widgets/ai_assistant_panel.dart';
import '../widgets/project_sidebar.dart';
import '../widgets/add_edit_project_dialog.dart';
import '../widgets/app_dialogs.dart';
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
  final GlobalKey<ProjectSidebarState> _sidebarKey =
      GlobalKey<ProjectSidebarState>();
  final GlobalKey<BugTrackerViewState> _bugTrackerKey =
      GlobalKey<BugTrackerViewState>();

  HubLoadState _hubLoadState = HubLoadState.loading;

  StreamSubscription? _hubMembersSubscription;
  StreamSubscription? _hubSubscription;

  // ✅ --- (متغير جديد: لمنع مشكلة الـ Race Condition عند المغادرة) ---
  bool _isLeaving = false;

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
    super.dispose();
  }

  Future<void> _loadHubInfoWithRetry({int retries = 3}) async {
    if (!mounted) return;

    setState(() {
      _hubLoadState = HubLoadState.loading;
    });

    Exception? lastError;
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
            return; // Success, exit the function
          }
        }
      } catch (e) {
        lastError = e as Exception;
        debugPrint('Error loading hub info (attempt ${i + 1}): $e');
      }

      if (i < retries - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    // This block only runs if all retries have failed
    if (mounted && _hubLoadState != HubLoadState.loaded) {
      setState(() {
        _hubLoadState = HubLoadState.error;
      });

      // Check the type of the last error encountered
      if (lastError is ClientException) {
        _handleNetworkError();
      } else {
        // For other errors (Postgrest, data not found, etc.), assume the hub is gone.
        _handleHubDeleted();
      }
    }
  }

  void _handleNetworkError() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('خطأ في الاتصال'),
        content: const Text(
            'تعذر الاتصال بالخادم. الرجاء التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadHubInfoWithRetry(); // Call the retry logic again
            },
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  void _handleMemberKicked() {
    _cleanupAndNavigate(
      title: 'تم طردك',
      content:
          'لقد تم إزالتك من الفريق. يجب عليك الانضمام إلى فريق جديد أو إنشاء واحد.',
    );
  }

  void _handleHubDeleted() {
    _cleanupAndNavigate(
      title: 'الفريق لم يعد موجوداً',
      content:
          'يبدو أن الفريق الذي كنت فيه قد تم حذفه. يجب عليك الانضمام أو إنشاء فريق جديد.',
    );
  }

  void _cleanupAndNavigate(
      {required String title, required String content}) async {
    if (!mounted) return;

    _hubMembersSubscription?.cancel();
    _hubSubscription?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hub_setup_complete', false);

    if (!mounted) return;

    // Use a local navigator context if available, otherwise use the root.
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              navigator.pushAndRemoveUntil(
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

  // ✅ --- (تعديل: إضافة تحقق من متغير المغادرة) ---
  void _setupRealtimeListeners(String hubId) {
    _hubMembersSubscription?.cancel();
    _hubSubscription?.cancel();

    _hubMembersSubscription =
        _supabaseService.getHubMembersStream(hubId).listen((membersList) {
      if (!mounted || _isLeaving) return; // تجاهل التحديثات إذا كان المستخدم يغادر
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
      if (!mounted || _isLeaving) return; // تجاهل التحديثات
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
  }

  void _onProjectSelected(Project? project) {
    setState(() {
      _selectedProject = project;
    });
  }

  void _editProject(Project project) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddEditProjectDialog(
        project: project,
        onProjectSaved: (isNew) async {
          _sidebarKey.currentState?.refreshProjects();
          final projects = await _supabaseService.getProjects();
          if (mounted) {
            setState(() {
              _selectedProject = projects.firstWhere((p) => p.id == project.id,
                  orElse: () => project);
            });
          }
        },
      ),
    );
  }

  void _refreshAll() {
    _sidebarKey.currentState?.refreshProjects();
    _bugTrackerKey.currentState?.refreshBugs();
    showSuccessDialog(context, 'تم تحديث البيانات بنجاح!');
  }

  // ✅ --- (تعديل: إضافة متغير المغادرة وإعادة هيكلة) ---
  Future<void> _leaveHub() async {
    if (_myMembership == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد المغادرة'),
        content: const Text('هل أنت متأكد من رغبتك في مغادرة الفريق؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('مغادرة', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _isLeaving = true; // تفعيل متغير المغادرة لمنع الـ race condition
      });

      try {
        await _supabaseService.leaveHub(_myMembership!.id);

        // الانتقال بعد المغادرة الناجحة
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('hub_setup_complete', false);

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const InitialHubScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          showErrorDialog(context, 'فشل في مغادرة الفريق: ${e.toString()}');
          // إعادة المتغير لوضعه الطبيعي عند الفشل
          setState(() {
            _isLeaving = false;
          });
        }
      }
    }
  }

  void _showHubInfo() {
    if (_currentHub == null) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              title: Text('معلومات الفريق: ${_currentHub!.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الرمز السري لمشاركة الفريق:'),
                  const SizedBox(height: 8),
                  SelectableText(
                    _currentHub!.secretCode,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              actions: [
                if (!_isLeader)
                  TextButton.icon(
                    icon: const Icon(Icons.exit_to_app, color: Colors.orange),
                    label: const Text('مغادرة الفريق',
                        style: TextStyle(color: Colors.orange)),
                    onPressed: () {
                      Navigator.pop(context); // Close the info dialog first
                      _leaveHub();
                    },
                  ),
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                )
              ],
            ));
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
          if (_selectedProject != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAll,
              tooltip: 'تحديث الكل',
            ),
          if (_currentHub != null)
            IconButton(
              icon: const Icon(Icons.hub_outlined),
              onPressed: _showHubInfo,
              tooltip: 'معلومات الفريق',
            ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'فتح المساعد الذكي',
          ),
        ],
      ),
      drawer: ProjectSidebar(
        key: _sidebarKey,
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