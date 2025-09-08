import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class AddBugDialog extends StatefulWidget {
  final String projectId;
  final VoidCallback onBugAdded;

  const AddBugDialog({
    super.key,
    required this.projectId,
    required this.onBugAdded,
  });

  @override
  State<AddBugDialog> createState() => _AddBugDialogState();
}

class _AddBugDialogState extends State<AddBugDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  // --- تعديل: ترجمة أنواع الأخطاء ---
  String _selectedType = 'بسيط';
  final _bugTypes = ['حرج', 'بسيط', 'تحسين'];

  Future<void> _submitBug() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);

      try {
        final supabaseService = SupabaseService();
        final bugData = {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'type': _selectedType,
          'project_id': widget.projectId,
          // --- تعديل: إضافة الحالة الافتراضية باللغة العربية ---
          'status': 'مفتوح',
        };
        await supabaseService.addBug(bugData);

        if (mounted) {
          Navigator.of(context).pop();
          widget.onBugAdded();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل في إضافة الخطأ: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة خطأ جديد'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'العنوان'),
                validator: (value) => value!.trim().isEmpty ? 'الرجاء إدخال عنوان' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'الوصف'),
                maxLines: 4,
                validator: (value) => value!.trim().isEmpty ? 'الرجاء إدخال وصف' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: _bugTypes.map((String type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() => _selectedType = newValue!);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitBug,
          child: _isSubmitting
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('إضافة'),
        ),
      ],
    );
  }
}
