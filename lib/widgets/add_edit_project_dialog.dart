import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/supabase_service.dart';
import 'app_dialogs.dart';

class AddEditProjectDialog extends StatefulWidget {
  final Project? project;
  final Function(bool isNew) onProjectSaved;

  const AddEditProjectDialog({
    super.key,
    this.project,
    required this.onProjectSaved,
  });

  @override
  State<AddEditProjectDialog> createState() => _AddEditProjectDialogState();
}

class _AddEditProjectDialogState extends State<AddEditProjectDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  final _githubUserController = TextEditingController();
  final _githubRepoController = TextEditingController();
  final _githubUrlController = TextEditingController();
  late TabController _tabController;
  bool _isSyncing = false;

  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = false;

  bool get _isEditing => widget.project != null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (_isEditing) {
      _nameController.text = widget.project!.name;
      _descriptionController.text = widget.project!.description ?? '';
      _githubUrlController.text = widget.project!.githubUrl ?? '';
      _syncGitPartsFromUrl();
    }

    _githubUrlController.addListener(_syncGitPartsFromUrl);
    _githubUserController.addListener(_syncUrlFromGitParts);
    _githubRepoController.addListener(_syncUrlFromGitParts);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _githubUrlController.removeListener(_syncGitPartsFromUrl);
    _githubUserController.removeListener(_syncUrlFromGitParts);
    _githubRepoController.removeListener(_syncUrlFromGitParts);
    _nameController.dispose();
    _descriptionController.dispose();
    _githubUrlController.dispose();
    _githubUserController.dispose();
    _githubRepoController.dispose();
    super.dispose();
  }
  
  void _syncGitPartsFromUrl() {
    if (_isSyncing) return;
    _isSyncing = true;
    final url = _githubUrlController.text.trim();
    try {
      final lowerUrl = url.toLowerCase();
      if (lowerUrl.startsWith('https://github.com/') || lowerUrl.startsWith('http://github.com/')) {
        final uri = Uri.parse(url);
        if (uri.pathSegments.length >= 2 && uri.pathSegments[0].isNotEmpty && uri.pathSegments[1].isNotEmpty) {
          _githubUserController.text = uri.pathSegments[0];
          _githubRepoController.text = uri.pathSegments[1].replaceAll('.git', '');
        } else {
           _githubUserController.clear();
           _githubRepoController.clear();
        }
      } else {
           _githubUserController.clear();
           _githubRepoController.clear();
      }
    } catch (_) {
      _githubUserController.clear();
      _githubRepoController.clear();
    }
    Future.delayed(const Duration(milliseconds: 100), () => _isSyncing = false);
  }

  void _syncUrlFromGitParts() {
    if (_isSyncing) return;
    _isSyncing = true;
    final user = _githubUserController.text.trim();
    final repo = _githubRepoController.text.trim();
    if (user.isNotEmpty && repo.isNotEmpty) {
      _githubUrlController.text = 'https://github.com/$user/$repo';
    } else if (user.isEmpty && repo.isEmpty) {
      _githubUrlController.clear();
    }
    _isSyncing = false;
  }

  Future<void> _saveProject() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final projectData = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'github_url': _githubUrlController.text.trim().isEmpty
            ? null
            : _githubUrlController.text.trim(),
      };

      if (_isEditing) {
        projectData['id'] = widget.project!.id;
        await _supabaseService.updateProject(projectData);
      } else {
        await _supabaseService.addProject(projectData);
      }

      widget.onProjectSaved(!_isEditing);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, 'فشل العملية: ${e.toString().replaceFirst("Exception: ", "")}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ✅ --- (تم تعديل هذه الدالة لحل مشكلة التخطيط) ---
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'تعديل المشروع' : 'إضافة مشروع جديد'),
      // ✅ --- (تغليف المحتوى بـ SizedBox لتحديد حجم النافذة) ---
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: 520, // ارتفاع ثابت لمنع أخطاء التخطيط
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'اسم المشروع'),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'الرجاء إدخال اسم للمشروع'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'وصف المشروع (اختياري)'),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                Text('مستودع GitHub (اختياري)', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'بسيط'),
                    Tab(text: 'متقدم (رابط كامل)'),
                  ],
                ),
                SizedBox(
                  height: 200, // ارتفاع ثابت لمحتوى التابات
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 24.0),
                        child: Column(
                          children: [
                             TextFormField(
                              controller: _githubUserController,
                              decoration: const InputDecoration(
                                labelText: 'اسم المستخدم',
                                prefixText: 'github.com/',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _githubRepoController,
                               decoration: const InputDecoration(
                                labelText: 'اسم المستودع',
                                prefixText: '/',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 24.0),
                        child: TextFormField(
                          controller: _githubUrlController,
                          decoration: const InputDecoration(
                            labelText: 'رابط مستودع GitHub',
                            hintText: 'https://github.com/user/repo',
                            prefixIcon: Icon(Icons.link),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: _isLoading ? null : _saveProject,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

