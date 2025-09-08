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

/// يعرض نافذة حوار خاصة بالأخطاء
void showErrorDialog(BuildContext context, String content) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('حدث خطأ'),
      content: Text(content),
      icon: Icon(Icons.error_outline, color: Colors.red.shade400),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
