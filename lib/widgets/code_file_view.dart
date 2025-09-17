import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
// --- تعديل (3): استيراد الحزم اللازمة لحفظ الملف المؤقت ---
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'app_dialogs.dart';


class CodeFileView extends StatelessWidget {
  final String filePath;
  final String codeContent;
  final Map<String, String> allFiles;

  const CodeFileView({
    super.key,
    required this.filePath,
    required this.codeContent,
    required this.allFiles,
  });

  // --- تعديل (3): تغيير وظيفة المشاركة لإرسال ملف بدلاً من نص ---
  Future<void> _shareAllFilesAsFile(BuildContext context) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('DevNest Code Share');
      buffer.writeln('=' * 20);

      allFiles.forEach((path, content) {
        buffer.writeln('\n// --- FILE: $path ---\n');
        buffer.writeln(content);
        buffer.writeln('\n');
      });

      // 1. الحصول على مسار المجلد المؤقت
      final tempDir = await getTemporaryDirectory();
      // 2. إنشاء ملف نصي في المجلد المؤقت
      final file = File('${tempDir.path}/devnest_code_share.txt');
      // 3. كتابة كل محتوى الكود في هذا الملف
      await file.writeAsString(buffer.toString());

      // 4. استخدام Share.shareXFiles لمشاركة الملف الفعلي
      // هذا يتجاوز قيود عدد الأحرف في معظم التطبيقات
      await Share.shareXFiles(
        [XFile(file.path)], 
        subject: 'مشاركة ملفات الكود من DevNest'
      );

    } catch (e) {
      if (context.mounted) {
        showErrorDialog(context, 'حدث خطأ أثناء تحضير ملف المشاركة: $e');
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade700)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                )),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 16, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filePath,
                      style: TextStyle(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    tooltip: 'نسخ الكود',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: codeContent));
                      showSuccessDialog(context, 'تم نسخ الكود بنجاح!');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined,
                        size: 18),
                    tooltip: 'مشاركة كل الملفات',
                    // --- تعديل (3): استدعاء الدالة الجديدة ---
                    onPressed: () => _shareAllFilesAsFile(context),
                  )
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MarkdownBody(
                data: '```dart\n$codeContent\n```',
                selectable: true,
                styleSheet:
                    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  code: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14.0,
                      backgroundColor: Colors.transparent),
                  codeblockDecoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

