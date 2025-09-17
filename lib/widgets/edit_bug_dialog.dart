import 'package:flutter/material.dart';
import '../models/bug.dart';
import '../services/supabase_service.dart';
// --- إضافة: استيراد نوافذ الحوار ---
import 'app_dialogs.dart';


class EditBugDialog extends StatefulWidget {
  final Bug bug;
  final VoidCallback onBugEdited;

  const EditBugDialog({
    super.key,
    required this.bug,
    required this.onBugEdited,
  });

  @override
  State<EditBugDialog> createState() => _EditBugDialogState();
}

class _EditBugDialogState extends State<EditBugDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  bool _isSubmitting = false;

  late String _selectedType;
  final _bugTypes = ['حرج', 'بسيط', 'تحسين'];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.bug.title);
    _descriptionController = TextEditingController(text: widget.bug.description);
    _selectedType = widget.bug.type;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitChanges() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);

      try {
        final supabaseService = SupabaseService();
        final bugData = {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'type': _selectedType,
        };
        await supabaseService.updateBug(widget.bug.id, bugData);

        if (mounted) {
          Navigator.of(context).pop();
          widget.onBugEdited();
        }
      } catch (e) {
        // --- تعديل: استبدال SnackBar بنافذة حوار ---
        if (mounted) {
          showErrorDialog(context, 'فشل في تعديل الخطأ: $e');
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
      title: const Text('تعديل الخطأ/التحسين'),
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
          onPressed: _isSubmitting ? null : _submitChanges,
          child: _isSubmitting
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('حفظ التعديلات'),
        ),
      ],
    );
  }
}