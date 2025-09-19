import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/github_service.dart'; // --- إضافة: استيراد خدمة GitHub ---
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
  final _githubUrlController = TextEditingController();

  // --- إضافة: متغيرات للحالة والخدمات ---
  final GitHubService _githubService = GitHubService();
  bool _isCheckingUrl = false;
  // --- نهاية الإضافة ---

  final SupabaseService _supabaseService = SupabaseService();
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
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final githubUrl = _githubUrlController.text.trim();

    // --- إضافة: التحقق من رابط GitHub قبل الحفظ ---
    if (githubUrl.isNotEmpty) {
      setState(() => _isCheckingUrl = true);
      final isValid = await _githubService.isValidRepository(githubUrl);
      setState(() => _isCheckingUrl = false);

      if (!isValid && mounted) {
        showInvalidGitHubRepoDialog(context, 'الرابط غير صالح أو المستودع خاص.');
        return;
      }
    }
    // --- نهاية التحقق ---

    setState(() => _isLoading = true);
    try {
      final projectData = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'github_url': githubUrl.isEmpty ? null : githubUrl,
      };

      if (_isEditing) {
        await _supabaseService.updateProject({'id': widget.project!.id, ...projectData});
      } else {
        await _supabaseService.addProject(projectData);
      }

      widget.onProjectSaved(!_isEditing);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorDialog(context, 'فشل العملية: ${e.toString().replaceFirst("Exception: ", "")}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // تم تبسيط الواجهة وإزالة التابات لتجربة أفضل
    return AlertDialog(
      title: Text(_isEditing ? 'تعديل المشروع' : 'إضافة مشروع جديد'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                decoration: const InputDecoration(labelText: 'وصف المشروع (اختياري)'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _githubUrlController,
                decoration: InputDecoration(
                  labelText: 'رابط مستودع GitHub (اختياري)',
                  hintText: 'https://github.com/user/repo',
                  prefixIcon: const Icon(Icons.link),
                  // --- إضافة: عرض مؤشر التحميل عند فحص الرابط ---
                  suffixIcon: _isCheckingUrl
                      ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : null,
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final uri = Uri.tryParse(value.trim());
                    if (uri == null || !uri.isAbsolute || uri.host != 'github.com') {
                      return 'الرجاء إدخال رابط GitHub صالح';
                    }
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _isLoading || _isCheckingUrl ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: _isLoading || _isCheckingUrl ? null : _saveProject,
          child: _isLoading || _isCheckingUrl
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
