import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_dialogs.dart';
import '../../services/supabase_service.dart';

// --- إضافة: تعداد لتحديد وضع المصادقة ---
enum AuthMode { login, signUp }

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key});

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _supabaseService = SupabaseService();
  // --- تعديل: استخدام التعداد لإدارة الحالة ---
  AuthMode _authMode = AuthMode.signUp;
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _performAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      if (_authMode == AuthMode.login) {
        // --- تعديل: منطق تسجيل الدخول ---
        final isAnonymous = _supabaseService.isUserAnonymous();
        if (isAnonymous) {
          final confirm = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('تنبيه'),
              content: const Text('تسجيل الدخول سيؤدي إلى فقدان بياناتك كزائر. هل ترغب في المتابعة؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('متابعة')),
              ],
            )
          );
          if (confirm != true) return;
        }

        await _supabaseService.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

      } else { // AuthMode.signUp
        // ربط الحساب المجهول الحالي ببيانات اعتماد جديدة
        await _supabaseService.linkAnonymousUser(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (mounted) {
          showSuccessDialog(context, 'تم إنشاء حسابك وتأمينه بنجاح!');
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }

    } on AuthException catch (e) {
      if (mounted) {
        showErrorDialog(context, 'فشل المصادقة: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, 'حدث خطأ غير متوقع: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // --- تعديل: تصميم جديد للنافذة ---
      title: const Text('تأمين حسابك'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _authMode == AuthMode.signUp 
                ? 'قم بإنشاء حساب جديد لربط بياناتك الحالية وتأمينها.'
                : 'سجل الدخول إلى حسابك الحالي (سيتم فقدان بيانات الزائر).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SegmentedButton<AuthMode>(
                segments: const [
                  ButtonSegment(value: AuthMode.signUp, label: Text('إنشاء حساب')),
                  ButtonSegment(value: AuthMode.login, label: Text('تسجيل دخول')),
                ],
                selected: {_authMode},
                onSelectionChanged: (newSelection) {
                  setState(() => _authMode = newSelection.first);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty || !value.contains('@')) {
                    return 'الرجاء إدخال بريد إلكتروني صالح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'كلمة المرور'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                  }
                  return null;
                },
              ),
              if (_authMode == AuthMode.signUp) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                  obscureText: true,
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'كلمتا المرور غير متطابقتين';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _performAuth,
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_authMode == AuthMode.login ? 'دخول' : 'إنشاء وتأمين'),
        ),
      ],
    );
  }
}
