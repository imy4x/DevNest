import 'package:flutter/material.dart';

// ملف جديد لمركزة جميع نوافذ الحوار وتوحيد تصميمها

/// يعرض نافذة حوار معلومات عامة
void showInfoDialog(BuildContext context, String title, String content) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('حسنًا'),
        ),
      ],
    ),
  );
}

/// يعرض نافذة حوار خاصة بالنجاح
void showSuccessDialog(BuildContext context, String content) {
  showDialog(
    context: context,
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


/// يعرض نافذة حوار خاصة بالأخطاء
void showErrorDialog(BuildContext context, String content) {
  showDialog(
    context: context,
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

/// يعرض نافذة حوار لرفض الصلاحية
void showPermissionDeniedDialog(BuildContext context) {
   showDialog(
    context: context,
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
