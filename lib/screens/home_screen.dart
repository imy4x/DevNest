import 'dart:async';
import 'dart:io';
import 'package:http/http.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import 'notification_settings_screen.dart';
import 'auth_dialog.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

enum HubLoadState { loading, loaded, error }

final GlobalKey<_HomeScreenState> homeScreenKey = GlobalKey<_HomeScreenState>();

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
  bool _isLeaving = false;
  bool _isAnonymousUser = true;

  bool get _isLeader => _myMembership?.role == 'leader';
  bool get _canSendBroadcast => _myMembership?.canSendBroadcasts ?? false;

  @override
  void initState() {
    super.initState();
    _supabaseService.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        _checkUserStatus();
        _loadHubInfoWithRetry();
      }
    });
    _checkUserStatus();
    _loadHubInfoWithRetry();
  }

  void _checkUserStatus() {
    if (mounted) {
      setState(() {
        _isAnonymousUser = _supabaseService.isUserAnonymous();
      });
    }
  }

  void handleNotificationNavigation(String? type, String projectId) async {
    try {
      if (_hubLoadState != HubLoadState.loaded) {
        await _loadHubInfoWithRetry();
        if (_hubLoadState != HubLoadState.loaded) {
          debugPrint("Cannot navigate: Hub info not loaded.");
          return;
        }
      }

      final allProjects = await _supabaseService.getProjects();
      final targetProject = allProjects.firstWhere(
        (p) => p.id == projectId,
        orElse: () => throw Exception('Project not found from notification'),
      );

      if (mounted) {
        setState(() {
          _selectedProject = targetProject;
        });
      }

      if (type == 'chat') {
        _scaffoldKey.currentState?.openEndDrawer();
      }
    } catch (e) {
      debugPrint("Failed to navigate from notification: $e");
      if (mounted) {
        showErrorDialog(context,
            'لم يتم العثور على المشروع المرتبط بالإشعار.');
      }
    }
  }

  @override
  void dispose() {
    _hubMembersSubscription?.cancel();
    _hubSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadHubInfoWithRetry({int retries = 3}) async {
    if (!mounted) return;

    var connectivityResult = await (Connectivity().checkConnectivity());
    if (!connectivityResult.contains(ConnectivityResult.mobile) &&
        !connectivityResult.contains(ConnectivityResult.wifi) &&
        !connectivityResult.contains(ConnectivityResult.ethernet)) {
      _handleNetworkError();
      return;
    }

    setState(() => _hubLoadState = HubLoadState.loading);
    Object? lastError;

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
        break;
      } on SocketException catch (e) {
        lastError = e;
        debugPrint('Network error (SocketException): $e');
        break;
      } on ClientException catch (e) {
        lastError = e;
        debugPrint('Network error (ClientException): $e');
        break;
      } catch (e) {
        lastError = e;
        debugPrint('Error loading hub info (attempt ${i + 1}): $e');
      }
      if (i < retries - 1) await Future.delayed(const Duration(seconds: 2));
    }

    if (mounted && _hubLoadState != HubLoadState.loaded) {
      setState(() => _hubLoadState = HubLoadState.error);
      if (lastError is ClientException || lastError is SocketException) {
        _handleNetworkError();
      } else {
        _handleHubDeleted();
      }
    }
  }

  void _handleNetworkError() {
    if (!mounted) return;
    showNoInternetDialog(context, () {
      _loadHubInfoWithRetry();
    });
  }

  void _handleMemberKicked() => _cleanupAndNavigate(
      title: 'تم طردك',
      content:
          'لقد تم إزالتك من الفريق. يجب عليك الانضمام إلى فريق جديد أو إنشاء واحد.');
  void _handleHubDeleted() => _cleanupAndNavigate(
      title: 'الفريق لم يعد موجوداً',
      content:
          'يبدو أن الفريق الذي كنت فيه قد تم حذفه. يجب عليك الانضمام أو إنشاء فريق جديد.');

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('خروج')),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _supabaseService.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hub_setup_complete', false);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const InitialHubScreen()),
          (route) => false,
        );
      } catch (e) {
        showErrorDialog(context, 'فشل تسجيل الخروج: $e');
      }
    }
  }

  void _cleanupAndNavigate({required String title, required String content}) async {
    if (!mounted) return;
    _hubMembersSubscription?.cancel();
    _hubSubscription?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hub_setup_complete', false);
    if (!mounted) return;
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
                  MaterialPageRoute(
                      builder: (context) => const InitialHubScreen()),
                  (route) => false);
            },
            child: const Text('موافق'),
          )
        ],
      ),
    );
  }

  void _setupRealtimeListeners(String hubId) {
    _hubMembersSubscription?.cancel();
    _hubSubscription?.cancel();
    _hubMembersSubscription =
        _supabaseService.getHubMembersStream(hubId).listen((membersList) {
      if (!mounted || _isLeaving) return;
      final currentUserStillAMember = membersList
          .any((m) => m['user_id'] == _supabaseService.currentUserId);
      if (currentUserStillAMember) {
        final myData = membersList
            .firstWhere((m) => m['user_id'] == _supabaseService.currentUserId);
        if (mounted) setState(() => _myMembership = HubMember.fromJson(myData));
      } else {
        _handleMemberKicked();
      }
    });
    _hubSubscription = _supabaseService.getHubStream(hubId).listen((hub) {
      if (!mounted || _isLeaving) return;
      if (hub == null)
        _handleHubDeleted();
      else if (mounted) setState(() => _currentHub = hub);
    });
  }

  void _onProjectSelected(Project? project) =>
      setState(() => _selectedProject = project);

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
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('مغادرة',
                  style: TextStyle(color: Colors.orange))),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isLeaving = true);
      try {
        await _supabaseService.leaveHub(_myMembership!.id);
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('hub_setup_complete', false);
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const InitialHubScreen()),
              (route) => false);
        }
      } catch (e) {
        if (mounted) {
          showErrorDialog(context, 'فشل في مغادرة الفريق: ${e.toString()}');
          setState(() => _isLeaving = false);
        }
      }
    }
  }

  void _showMemberBroadcastDialog() {
    final broadcastController = TextEditingController();
    final broadcastFormKey = GlobalKey<FormState>();
    bool isSending = false;

    showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('إرسال رسالة عامة للفريق'),
                  content: Form(
                    key: broadcastFormKey,
                    child: TextFormField(
                      controller: broadcastController,
                      decoration:
                          const InputDecoration(labelText: 'نص الرسالة'),
                      validator: (v) => v!.trim().isEmpty
                          ? 'الرسالة لا يمكن أن تكون فارغة'
                          : null,
                    ),
                  ),
                  actions: [
                    TextButton(
                        onPressed:
                            isSending ? null : () => Navigator.pop(context),
                        child: const Text('إلغاء')),
                    ElevatedButton(
                      onPressed: isSending
                          ? null
                          : () async {
                              if (broadcastFormKey.currentState!
                                  .validate()) {
                                setState(() => isSending = true);
                                try {
                                  await _supabaseService
                                      .sendBroadcastNotification(
                                          broadcastController.text.trim(),
                                          fromLeader: false);
                                  if (mounted) {
                                    Navigator.pop(context);
                                    showSuccessDialog(
                                        context, 'تم إرسال الإشعار بنجاح.');
                                  }
                                } catch (e) {
                                  if (mounted)
                                    showErrorDialog(
                                        context, 'فشل الإرسال: $e');
                                } finally {
                                  if (mounted)
                                    setState(() => isSending = false);
                                }
                              }
                            },
                      child: isSending
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('إرسال'),
                    )
                  ],
                );
              },
            ));
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
            SelectableText(_currentHub!.secretCode,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          if (!_isLeader)
            TextButton.icon(
                icon: const Icon(Icons.exit_to_app, color: Colors.orange),
                label: const Text('مغادرة الفريق',
                    style: TextStyle(color: Colors.orange)),
                onPressed: () {
                  Navigator.pop(context);
                  _leaveHub();
                }),
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
                }),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'))
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
              Text('جاري تحميل بيانات الفريق...')
            ])),
      );
    }
    if (_hubLoadState == HubLoadState.error) {
      return Scaffold(body: Container());
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        // --- تعديل: استخدام Expanded لضمان ظهور العنوان ---
        title: Row(
          children: [
            Expanded(
              child: Text(
                _selectedProject?.name ?? _currentHub?.name ?? 'DevNest',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // --- تعديل: إبقاء الأزرار الأساسية فقط ---
          if (_selectedProject != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAll,
              tooltip: 'تحديث الكل',
            ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'فتح المساعد الذكي',
          ),
          // --- تعديل: نقل بقية الأزرار إلى قائمة منسدلة ---
          if (_currentHub != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'hub_info') _showHubInfo();
                if (value == 'broadcast') _showMemberBroadcastDialog();
                if (value == 'settings') {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NotificationSettingsScreen()));
                } else if (value == 'logout') {
                  _signOut();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'hub_info',
                  child: ListTile(
                    leading: Icon(Icons.hub_outlined),
                    title: Text('معلومات الفريق'),
                  ),
                ),
                if (!_isLeader && _canSendBroadcast)
                  const PopupMenuItem<String>(
                    value: 'broadcast',
                    child: ListTile(
                      leading: Icon(Icons.campaign_outlined),
                      title: Text('إرسال إشعار عام'),
                    ),
                  ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.notifications_active_outlined),
                    title: Text('إعدادات الإشعارات'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('تسجيل الخروج'),
                  ),
                ),
              ],
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
      body: Column(
        children: [
          if (_isAnonymousUser)
            Material(
              color: Colors.amber.shade900,
              child: InkWell(
                onTap: () async {
                  await showDialog(
                      context: context, builder: (_) => const AuthDialog());
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'أنت تستخدم حساب زائر. بياناتك قد تُفقد. اضغط هنا لإنشاء حساب وتأمين عملك.',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: _selectedProject == null
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
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text('أو قم بإنشاء مشروع جديد',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center),
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
          ),
        ],
      ),
    );
  }
}

