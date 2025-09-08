import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/project.dart';
import '../models/hub.dart';
import '../models/hub_member.dart';
import '../services/supabase_service.dart';
import 'bug_tracker_view.dart';
import '../widgets/ai_assistant_panel.dart';
import '../widgets/project_sidebar.dart';
import '../widgets/add_edit_project_dialog.dart';
import 'hub_management_screen.dart';
import 'initial_hub_screen.dart'; // ✨ --- Import for navigation --- ✨
import 'dart:async'; // ✨ --- Import for StreamSubscription --- ✨


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

  // ✨ --- Stream subscription to listen for membership changes (kick event) --- ✨
  StreamSubscription? _membershipSubscription;

  bool get _isLeader => _myMembership?.role == 'leader';

  @override
  void initState() {
    super.initState();
    _loadHubInfo();
  }

  @override
  void dispose() {
    // ✨ --- Cancel the subscription to prevent memory leaks --- ✨
    _membershipSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadHubInfo() async {
    try {
      final hub = await _supabaseService.getHubForUser();
      if (hub != null && mounted) {
        final currentUserId = _supabaseService.currentUserId;
        final member = await _supabaseService.getMemberInfo(hub.id);

        setState(() {
          _currentHub = hub;
          _myMembership = member;
        });

        // ✨ --- Start listening for membership changes after loading hub info --- ✨
        _listenForKickEvents(hub.id);

      } else if (hub == null && mounted) {
        // This case handles if the user's hub was deleted while they were away
        _handleKicked(wasKicked: false);
      }
    } catch (e) {
      print("Error loading hub info: $e");
    }
  }

  // ✨ --- Function to handle being kicked from a hub --- ✨
  void _handleKicked({bool wasKicked = true}) async {
    // Cancel listener to prevent multiple triggers
    _membershipSubscription?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hub_setup_complete', false);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false, // User must interact with the dialog
      builder: (context) => AlertDialog(
        title: Text(wasKicked ? 'تم طردك' : 'Hub لم يعد موجوداً'),
        content: Text(wasKicked
          ? 'لقد تم إزالتك من الـ Hub. يجب عليك الانضمام إلى hub جديد أو إنشاء واحد.'
          : 'يبدو أن الـ Hub الذي كنت فيه قد تم حذفه. يجب عليك الانضمام أو إنشاء hub جديد.'),
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

  // ✨ --- Sets up the real-time listener for the user's membership status --- ✨
  void _listenForKickEvents(String hubId) {
    _membershipSubscription?.cancel(); // Cancel previous subscription if any
    _membershipSubscription = _supabaseService.getMyMembershipStream(hubId).listen((member) {
      if (member == null && mounted) {
        _handleKicked();
      } else if (mounted) {
        // Update membership info in real-time if permissions change
        setState(() {
          _myMembership = member;
        });
      }
    });
  }

  void _onProjectSelected(Project? project) {
    setState(() {
      _selectedProject = project;
    });
  }
  
  void _editProject(Project project) {
     // Permission check moved to BugTrackerView where the button is
     showDialog(
      context: context,
      builder: (context) => AddEditProjectDialog(
        project: project,
        onProjectSaved: (isNew) async {
           // Refresh the project list and update the selected project
           final projects = await _supabaseService.getProjects();
           setState(() {
               _selectedProject = projects.firstWhere((p) => p.id == project.id, orElse: () => project);
           });
        },
      ),
    );
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                Navigator.push(context, MaterialPageRoute(builder: (context) => HubManagementScreen(hub: _currentHub!)));
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_selectedProject?.name ?? _currentHub?.name ?? 'DevNest'),
        actions: [
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
                    Icon(Icons.rule_folder_outlined, size: 100, color: Colors.grey[700]),
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
              project: _selectedProject!,
              onEditProject: () => _editProject(_selectedProject!),
              myMembership: _myMembership,
            ),
    );
  }
}
