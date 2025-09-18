import 'package:flutter/material.dart';

// --- (لا تغيير) ---
void showSuccessDialog(BuildContext context, String content) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('نجاح'),
      content: Text(content),
      icon: Icon(Icons.check_circle_outline, color: Colors.green.shade400, size: 32),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('موافق'),
        ),
      ],
    ),
  );
}

// --- (لا تغيير) ---
void showErrorDialog(BuildContext context, String content) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('حدث خطأ'),
      content: Text(content),
      icon: Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}

/// ✅ --- (جديد) نافذة مخصصة عند إدخال رابط GitHub غير صالح ---
void showInvalidGitHubRepoDialog(BuildContext context, String errorDetails) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('خطأ في مستودع GitHub'),
      content: Text(
          'تعذر الوصول إلى المستودع. الرجاء التأكد من أن الرابط صحيح وأن المستودع عام (public).\n\nالتفاصيل: $errorDetails'),
      icon: Icon(Icons.link_off, color: Colors.orange.shade400, size: 32),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('فهمت'),
        ),
      ],
    ),
  );
}

/// ✅ --- (جديد) نافذة مخصصة عند انقطاع الاتصال بالإنترنت ---
void showNoInternetDialog(BuildContext context, VoidCallback onRetry) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('انقطاع الاتصال'),
      content: const Text(
          'تعذر الاتصال بالخادم. الرجاء التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.'),
      icon: Icon(Icons.wifi_off, color: Colors.blue.shade300, size: 32),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onRetry();
          },
          child: const Text('إعادة المحاولة'),
        ),
      ],
    ),
  );
}

// --- (لا تغيير) ---
void showPermissionDeniedDialog(BuildContext context) {
   showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('وصول مرفوض'),
      content: const Text('ليس لديك الصلاحية الكافية للقيام بهذا الإجراء. الرجاء التواصل مع قائد الـ Hub.'),
      icon: Icon(Icons.gpp_bad_outlined, color: Colors.orange.shade400, size: 32),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('فهمت'),
        ),
      ],
    ),
  );
}

// --- (لا تغيير) ---
void showTryAgainLaterDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('حدث خطأ'),
      content: const Text('فشل الاتصال بالخدمة. الرجاء المحاولة مرة أخرى لاحقًا.'),
      icon: Icon(Icons.cloud_off, color: Colors.orange.shade400, size: 32),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('حسنًا'),
        ),
      ],
    ),
  );
}

// --- (لا تغيير) ---
void showServiceUnavailableDialog(BuildContext context, String content) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('الخدمة غير متاحة مؤقتاً'),
      content: Text(content),
      icon: Icon(Icons.cloud_off, color: Colors.orange.shade400, size: 32),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('حسنًا'),
        ),
      ],
    ),
  );
}
