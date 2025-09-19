import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // --- إضافة: للتحقق من الاتصال ---
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/initial_hub_screen.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';
import 'widgets/app_dialogs.dart'; // --- إضافة: للوصول إلى نوافذ الحوار ---

// مفتاح الملاح العام للوصول إلى Navigator من خارج واجهة المستخدم
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print("Handling a background message: ${message.messageId}");
}

// --- إضافة: دالة للتحقق من الاتصال بالإنترنت ---
Future<bool> checkInternetConnection() async {
  var connectivityResult = await (Connectivity().checkConnectivity());
  // --- تعديل: التحقق من جميع أنواع الاتصال ---
  if (connectivityResult.contains(ConnectivityResult.mobile) ||
      connectivityResult.contains(ConnectivityResult.wifi) ||
      connectivityResult.contains(ConnectivityResult.ethernet)) {
    return true;
  }
  return false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  
  // --- تعديل: التحقق من الإنترنت قبل محاولة تسجيل الدخول ---
  if (await checkInternetConnection()) {
    if (Supabase.instance.client.auth.currentSession == null) {
      try {
        await Supabase.instance.client.auth.signInAnonymously();
      } catch (e) {
        print("Error signing in anonymously: $e");
      }
    }
  }

  if (Supabase.instance.client.auth.currentSession != null) {
    await NotificationService().init(navigatorKey);
  }

  final prefs = await SharedPreferences.getInstance();
  final bool isHubSetupComplete = prefs.getBool('hub_setup_complete') ?? false;

  runApp(DevNestApp(isHubSetupComplete: isHubSetupComplete));
}

class DevNestApp extends StatelessWidget {
  final bool isHubSetupComplete;
  const DevNestApp({super.key, required this.isHubSetupComplete});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            // --- إضافة: فحص الاتصال عند بدء التشغيل ---
            builder: (context) {
              return FutureBuilder<bool>(
                future: checkInternetConnection(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(body: Center(child: CircularProgressIndicator()));
                  }
                  if (snapshot.data == false) {
                     // استخدام WidgetsBinding لعرض الحوار بعد بناء الواجهة
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      showNoInternetDialog(context, () {
                         // إعادة بناء التطبيق عند الضغط على إعادة المحاولة
                         (context as Element).reassemble();
                      });
                    });
                    // عرض واجهة فارغة أثناء ظهور الحوار
                    return const Scaffold(body: Center(child: Text("لا يوجد اتصال بالإنترنت")));
                  }
                  return child!;
                },
              );
            },
          ),
        ),
        breakpoints: [
          const Breakpoint(start: 0, end: 450, name: MOBILE),
          const Breakpoint(start: 451, end: 800, name: TABLET),
          const Breakpoint(start: 801, end: 1920, name: DESKTOP),
          const Breakpoint(start: 1921, end: double.infinity, name: '4K'),
        ],
      ),
      title: 'Dev Nest',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF9F70FD),
        scaffoldBackgroundColor: const Color(0xFF1A1B26),
        cardColor: const Color(0xFF2A2D3E),
        textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2A2D3E),
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF9F70FD),
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1B26),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade800),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF9F70FD)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF9F70FD),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF9F70FD)),
          foregroundColor: const Color(0xFF9F70FD),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        )),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF2A2D3E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF9F70FD).withOpacity(0.2),
          labelStyle: const TextStyle(color: Color(0xFF9F70FD), fontWeight: FontWeight.bold),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        tabBarTheme: TabBarThemeData(
          indicator: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Color(0xFF9F70FD),
                width: 2.5,
              ),
            ),
          ),
          labelColor: const Color(0xFF9F70FD),
          unselectedLabelColor: Colors.grey.shade400,
        )
      ),
      home: isHubSetupComplete ? HomeScreen(key: homeScreenKey) : const InitialHubScreen(),
    );
  }
}
