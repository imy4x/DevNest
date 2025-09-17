import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
// --- إضافة: استيراد نوافذ الحوار ---
import '../widgets/app_dialogs.dart';

class InitialHubScreen extends StatefulWidget {
  const InitialHubScreen({super.key});

  @override
  State<InitialHubScreen> createState() => _InitialHubScreenState();
}

class _InitialHubScreenState extends State<InitialHubScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _nameEntered = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _navigateToHome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hub_setup_complete', true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  void _showCreateHubDialog() {
    final hubNameController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('إنشاء Hub جديد'),
        content: TextField(
          controller: hubNameController,
          decoration: const InputDecoration(labelText: 'اسم الـ Hub'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (hubNameController.text.trim().isEmpty) {
                showErrorDialog(context, 'الرجاء إدخال اسم للـ Hub');
                return;
              }
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                final secretCode = await _supabaseService.createHub(
                    hubNameController.text.trim(), _nameController.text.trim());
                await _showHubCreatedDialog(hubNameController.text.trim(), secretCode);
                await _navigateToHome();
              } catch (e) {
                 if(mounted) showErrorDialog(context, 'فشل إنشاء الـ Hub: $e');
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHubCreatedDialog(String hubName, String secretCode) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('تم إنشاء "$hubName" بنجاح!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('هذا هو الرمز السري للانضمام. شاركه مع فريقك:'),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                secretCode,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ملاحظة: لا يمكن استعادة هذا الرمز، احتفظ به في مكان آمن.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت، لنبدأ!'),
          )
        ],
      ),
    );
  }

  void _showJoinHubDialog() {
  final codeController = TextEditingController();
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('الانضمام إلى Hub'),
      content: TextField(
        controller: codeController,
        decoration: const InputDecoration(labelText: 'الرمز السري للـ Hub'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (!context.mounted) return;
            Navigator.pop(context);
          },
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () async {
            final code = codeController.text.trim();
            if (code.isEmpty) {
              if (!context.mounted) return;
              showErrorDialog(context, 'الرجاء إدخال الرمز السري');
              return;
            }

            // ✅ خلي رسالة التحميل تبان
            if (!mounted) return;
            setState(() => _isLoading = true);

            try {
              print("🔍 Trying to join hub with code: $code");
              await _supabaseService.joinHub(code, _nameController.text.trim());
              print("✅ Joined hub successfully!");

              if (!mounted) return;
              Navigator.pop(context); // Close dialog only if success
              await _navigateToHome();
            } catch (e, st) {
              print("❌ JoinHub error: $e\n$st");
              var errorMessage = e.toString().replaceFirst('Exception: ', '');
              if (errorMessage.contains('Hub not found with this secret code')) {
                errorMessage =
                    'الرمز السري الذي أدخلته غير صحيح. الرجاء التأكد منه والمحاولة مرة أخرى.';
              } else if (errorMessage
                  .contains('You are already a member of this hub')) {
                errorMessage = 'أنت بالفعل عضو في هذا الـ Hub.';
              }
              if (!context.mounted) return;
              showErrorDialog(context, 'فشل الانضمام: $errorMessage');
            } finally {
              if (!mounted) return;
              setState(() => _isLoading = false);
            }
          },
          child: const Text('انضمام'),
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.hub, size: 80),
                      const SizedBox(height: 24),
                      Text(
                        'مرحباً بك في DevNest',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ابدأ بكتابة اسمك، ثم قم بإنشاء Hub جديد لفريقك أو انضم إلى Hub موجود.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسمك الذي سيظهر للآخرين',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _nameEntered = value.trim().isNotEmpty;
                          });
                        },
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('إنشاء Hub جديد'),
                          onPressed: _nameEntered ? _showCreateHubDialog : null,
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(16)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.login),
                          label: const Text('الانضمام إلى Hub'),
                          onPressed: _nameEntered ? _showJoinHubDialog : null,
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}