import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';

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

class _AddEditProjectDialogState extends State<AddEditProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _githubUrlController = TextEditingController();

  final SupabaseService _supabaseService = SupabaseService();
  final GitHubService _githubService = GitHubService();
  bool _isLoading = false;

  bool get _isEditing => widget.project != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.project!.name;
      _descriptionController.text = widget.project!.description ?? '';
      _githubUrlController.text = widget.project!.githubUrl ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _githubUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveProject() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);

      final githubUrl = _githubUrlController.text.trim();
      String? apkUrl;

      try {
        if (githubUrl.isNotEmpty) {
          try {
            apkUrl = await _githubService.fetchLatestApkUrl(githubUrl);
             if (mounted && apkUrl != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم العثور على ملف APK في آخر إصدار!'), backgroundColor: Colors.green),
              );
            }
          } catch (e) {
             if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('لم يتم العثور على إصدار APK: $e'), backgroundColor: Colors.orange),
              );
            }
          }
        }
        
        // --- تعديل: تم حذف الحقول الإضافية ---
        final projectData = {
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
          'github_url': githubUrl.isEmpty ? null : githubUrl,
          'apk_download_url': apkUrl,
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل حفظ المشروع: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'تعديل المشروع' : 'إضافة مشروع جديد'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم المشروع'),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'الرجاء إدخال اسم للمشروع' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'وصف المشروع'),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _githubUrlController,
                decoration: const InputDecoration(
                  labelText: 'رابط مستودع GitHub (اختياري)',
                  hintText: 'https://github.com/user/repo',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  if (!value.startsWith('https://github.com/')) {
                    return 'الرجاء إدخال رابط GitHub صالح';
                  }
                  return null;
                },
              ),
              // --- تعديل: تم حذف الحقول الإضافية من هنا ---
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _isLoading ? null : _saveProject,
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ'),
        ),
      ],
    );
  }
}
