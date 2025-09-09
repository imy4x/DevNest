import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hub.dart';
import '../models/hub_member.dart';
import '../services/supabase_service.dart';
import '../widgets/app_dialogs.dart';
import 'initial_hub_screen.dart';

class HubManagementScreen extends StatefulWidget {
  final Hub hub;
  const HubManagementScreen({super.key, required this.hub});

  @override
  State<HubManagementScreen> createState() => _HubManagementScreenState();
}

class _HubManagementScreenState extends State<HubManagementScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  late Future<List<HubMember>> _membersFuture;
  bool _isDeletingHub = false;

  @override
  void initState() {
    super.initState();
    _refreshMembers();
  }

  void _refreshMembers() {
    setState(() {
      _membersFuture = _supabaseService.getHubMembers(widget.hub.id);
    });
  }
  
  Future<void> _updatePermissions(HubMember member, {bool? canAdd, bool? canEdit, bool? canChat, bool? canAddProj}) async {
    try {
      await _supabaseService.updateMemberPermissions(
        memberId: member.id,
        canAddBugs: canAdd ?? member.canAddBugs,
        canEditBugs: canEdit ?? member.canEditBugs,
        canUseChat: canChat ?? member.canUseChat,
        canManageProjects: canAddProj ?? member.canManageProjects,
      );
      if(mounted) {
        showSuccessDialog(context, 'تم تحديث الصلاحيات بنجاح.');
      }
       _refreshMembers();
    } catch(e) {
      if(mounted) {
        showErrorDialog(context, 'فشل تحديث الصلاحيات: $e');
      }
    }
  }

  Future<void> _editDisplayName(HubMember member) async {
    final nameController = TextEditingController(text: member.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل اسم العضو'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'أدخل الاسم الجديد'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      try {
        await _supabaseService.updateMemberDisplayName(memberId: member.id, newName: newName);
        _refreshMembers();
      } catch (e) {
        if (mounted) {
          showErrorDialog(context, 'فشل تحديث الاسم: $e');
        }
      }
    }
  }


  Future<void> _removeMember(HubMember member) async {
    final confirm = await showDialog<bool>(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الطرد'),
        content: Text('هل أنت متأكد من رغبتك في طرد "${member.displayName ?? 'هذا العضو'}"؟ سيتم تغيير الرمز السري للـ Hub بعد هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('طرد وتغيير الرمز', style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );

    if (confirm == true) {
      try {
        await _supabaseService.removeMember(member.id);
        if (mounted) {
           // ✨ --- تعديل: تم تحديث رسالة النجاح لتعكس تغيير الرمز --- ✨
           showSuccessDialog(context, 'تم طرد العضو وتحديث رمز الـ Hub بنجاح.');
        }
        _refreshMembers();
      } catch (e) {
        if(mounted) {
          showErrorDialog(context, 'فشل طرد العضو: $e');
        }
      }
    }
  }

  Future<void> _deleteHub() async {
    final members = await _supabaseService.getHubMembers(widget.hub.id);
    if (members.length > 1) {
      showErrorDialog(context, 'لا يمكنك حذف الـ Hub بوجود أعضاء آخرين. الرجاء طرد جميع الأعضاء أولاً.');
      return;
    }

    final hubNameController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف Hub "${widget.hub.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('هذا الإجراء نهائي ولا يمكن التراجع عنه. سيتم حذف جميع المشاريع والأخطاء والبيانات المرتبطة بهذا الـ Hub.'),
            const SizedBox(height: 16),
            Text('للتأكيد، الرجاء كتابة اسم الـ Hub: "${widget.hub.name}"'),
            const SizedBox(height: 8),
            TextField(
              controller: hubNameController,
              decoration: InputDecoration(
                hintText: widget.hub.name,
              ),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: hubNameController,
            builder: (context, value, child) {
              return FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: value.text == widget.hub.name
                  ? () => Navigator.pop(context, true)
                  : null,
                child: const Text('حذف نهائي'),
              );
            },
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isDeletingHub = true);
      try {
        await _supabaseService.deleteHub(widget.hub.id);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hub_setup_complete', false);
        
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const InitialHubScreen()),
            (route) => false
          );
        }

      } catch (e) {
        if (mounted) {
           showErrorDialog(context, 'فشل حذف الـ Hub: ${e.toString()}');
        }
      } finally {
        if (mounted) {
          setState(() => _isDeletingHub = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إدارة أعضاء "${widget.hub.name}"'),
      ),
      body: _isDeletingHub 
      ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('جاري حذف الـ Hub...')],))
      : FutureBuilder<List<HubMember>>(
        future: _membersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('لا يوجد أعضاء في هذا الـ Hub.'));
          }

          final members = snapshot.data!;
          final currentUser = _supabaseService.currentUserId;

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isLeader = member.role == 'leader';
                    final isCurrentUser = member.userId == currentUser;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                 Expanded(
                                   child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              member.displayName ?? 'عضو غير مسمى',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (!isLeader)
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, size: 18),
                                              onPressed: () => _editDisplayName(member),
                                              tooltip: 'تعديل الاسم',
                                            )
                                        ],
                                      ),
                                      if (isLeader)
                                        const Chip(label: Text('قائد'), backgroundColor: Colors.blueGrey, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact,)
                                      else if (isCurrentUser)
                                        const Chip(label: Text('أنت'), backgroundColor: Colors.purple, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact,),
                                    ],
                                   ),
                                 ),
                                 if(!isLeader)
                                   IconButton(
                                     icon: const Icon(Icons.person_remove_outlined),
                                     color: Colors.orange.shade300,
                                     tooltip: 'طرد العضو',
                                     onPressed: () => _removeMember(member),
                                   )
                               ],
                             ),
                            const Divider(),
                             SwitchListTile(
                              title: const Text('إدارة المشاريع (إضافة/تعديل)'),
                              value: member.canManageProjects,
                               onChanged: isLeader ? null : (value) {
                                 _updatePermissions(member, canAddProj: value);
                              },
                            ),
                            SwitchListTile(
                              title: const Text('السماح بإضافة أخطاء'),
                              value: member.canAddBugs,
                              onChanged: isLeader ? null : (value) {
                                 _updatePermissions(member, canAdd: value);
                              },
                            ),
                             SwitchListTile(
                              title: const Text('السماح بتعديل الأخطاء'),
                              value: member.canEditBugs,
                               onChanged: isLeader ? null : (value) {
                                 _updatePermissions(member, canEdit: value);
                              },
                            ),
                            SwitchListTile(
                              title: const Text('السماح باستخدام المحادثة'),
                              value: member.canUseChat,
                               onChanged: isLeader ? null : (value) {
                                 _updatePermissions(member, canChat: value);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  color: Colors.red.shade900.withOpacity(0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                         Text('منطقة الخطر', style: Theme.of(context).textTheme.titleLarge),
                         const SizedBox(height: 8),
                         const Text('الإجراء التالي لا يمكن التراجع عنه.'),
                         const SizedBox(height: 16),
                         FilledButton.icon(
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('حذف هذا الـ Hub نهائياً'),
                          onPressed: _deleteHub,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                         )
                      ],
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}
