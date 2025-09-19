import 'dart:async';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../models/project.dart';
import '../widgets/app_dialogs.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = true;
  final Map<String, bool> _savingStatus = {};
  Timer? _debounce;

  // --- الحالة المحلية لتفضيلات الإشعارات ---
  bool _allNotifications = true;
  bool _chatNotifications = true;
  bool _broadcasts = true;
  // --- إضافة: متغير جديد لإشعارات الأعضاء ---
  bool _memberActivityNotifications = true;
  bool _projectUpdates = true;
  Map<String, bool> _projectSpecificNotifications = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await _supabaseService.getNotificationPreferences();
      final projects = await _supabaseService.getProjects();

      // التأكد من وجود إدخال لكل مشروع
      for (var p in projects) {
        _projectSpecificNotifications.putIfAbsent(p.id, () => true);
      }

      // تحميل الإعدادات المحفوظة
      prefs.forEach((key, value) {
        if (key == 'all') _allNotifications = value;
        if (key == 'chat') _chatNotifications = value;
        if (key == 'broadcast') _broadcasts = value;
        // --- إضافة: تحميل الإعداد الجديد ---
        if (key == 'member_activity') _memberActivityNotifications = value;
        if (key == 'project_all') _projectUpdates = value;
        if (key.startsWith('project_')) {
          final projectId = key.replaceFirst('project_', '');
          if (_projectSpecificNotifications.containsKey(projectId)) {
            _projectSpecificNotifications[projectId] = value;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, 'فشل تحميل الإعدادات: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  void _updatePreference(String key, bool value) {
    setState(() {
      _savingStatus[key] = true;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final Map<String, bool> preferenceToSave = {key: value};
        await _supabaseService.saveNotificationPreferences(preferenceToSave);
      } catch (e) {
        if (mounted) {
          showErrorDialog(context, 'فشل حفظ الإعدادات: $e');
        }
      } finally {
        if (mounted) {
          setState(() {
            _savingStatus.remove(key);
          });
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    bool isCurrentlySaving = _savingStatus.containsValue(true);
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('إعدادات الإشعارات'),
            if (isCurrentlySaving) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ]
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<Project>>(
              future: _supabaseService.getProjects(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _projectSpecificNotifications.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                final projects = snapshot.data ?? [];

                return ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    _buildSectionTitle('الإعدادات العامة'),
                    _buildGeneralToggles(),
                    const Divider(height: 32),
                    _buildSectionTitle('إشعارات المشاريع'),
                    _buildProjectMasterToggle(),
                    if (projects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(child: Text('لا توجد مشاريع لعرضها.')),
                      )
                    else
                      _buildProjectToggles(projects),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildGeneralToggles() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('تلقي كل الإشعارات'),
          subtitle: const Text('التحكم في جميع إشعارات التطبيق'),
          value: _allNotifications,
          // --- إصلاح: تم تعديل هذه الدالة ---
          // الآن، عند إيقاف هذا الخيار، يتم فقط تعطيل المفاتيح الأخرى في الواجهة
          // دون تغيير قيمها المحفوظة، مما يسمح باستعادة حالتها عند إعادة التفعيل.
          onChanged: (value) {
            setState(() {
              _allNotifications = value;
            });
            _updatePreference('all', value);
          },
        ),
        SwitchListTile(
          title: const Text('إشعارات المحادثات'),
          value: _chatNotifications,
          onChanged: _allNotifications
              ? (v) {
                  setState(() => _chatNotifications = v);
                  _updatePreference('chat', v);
                }
              : null,
        ),
        SwitchListTile(
          title: const Text('رسائل الفريق العامة'),
          value: _broadcasts,
          onChanged: _allNotifications
              ? (v) {
                  setState(() => _broadcasts = v);
                   _updatePreference('broadcast', v);
                }
              : null,
        ),
        // --- إضافة: مفتاح تحكم جديد لإشعارات الأعضاء ---
        SwitchListTile(
          title: const Text('نشاط الأعضاء (مغادرة/طرد)'),
          value: _memberActivityNotifications,
          onChanged: _allNotifications
              ? (v) {
                  setState(() => _memberActivityNotifications = v);
                  _updatePreference('member_activity', v);
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildProjectMasterToggle() {
    return SwitchListTile(
      title: const Text('تلقي كل إشعارات المشاريع'),
      subtitle: const Text('التحكم في جميع الإشعارات المتعلقة بالمشاريع'),
      value: _projectUpdates,
      onChanged: _allNotifications
          ? (value) {
              // --- إصلاح: تم تعديل هذه الدالة أيضًا ---
              // يحافظ هذا الإصلاح على إعدادات الإشعارات المخصصة لكل مشروع.
              setState(() {
                _projectUpdates = value;
              });
              _updatePreference('project_all', value);
            }
          : null,
    );
  }

  Widget _buildProjectToggles(List<Project> projects) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Column(
        children: projects.map((project) {
          return SwitchListTile(
            title: Text(project.name, overflow: TextOverflow.ellipsis),
            value: _projectSpecificNotifications[project.id] ?? true,
            onChanged: _allNotifications && _projectUpdates
                ? (value) {
                    setState(
                        () => _projectSpecificNotifications[project.id] = value);
                     _updatePreference('project_${project.id}', value);
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, right: 8.0, top: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
