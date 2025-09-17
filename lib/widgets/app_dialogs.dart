import 'package:flutter/material.dart';

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
