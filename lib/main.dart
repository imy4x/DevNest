import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/initial_hub_screen.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';
// --- NEW: Background message handler must be a top-level function ---
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, like Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);

  print("Handling a background message: ${message.messageId}");
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- NEW: Initialize Firebase ---
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);


  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  await NotificationService().init();
  // --- NEW: Initialize Notification Service AFTER Supabase ---
  // This allows it to access the Supabase client if needed
  if (Supabase.instance.client.auth.currentSession != null) {
      await NotificationService().init();
  }


  if (Supabase.instance.client.auth.currentSession == null) {
    await Supabase.instance.client.auth.signInAnonymously();
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        builder: (context, child) => ResponsiveBreakpoints.builder(
          child: child!,
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

        // ✨ --- NEW "NEON INDIGO" THEME --- ✨
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF9F70FD), // Vibrant Purple
          scaffoldBackgroundColor: const Color(0xFF1A1B26), // Deep Indigo
          cardColor: const Color(0xFF2A2D3E), // Lighter Indigo/Purple
          textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF2A2D3E), // Match card color
            elevation: 0,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF9F70FD), // Vibrant Purple
            foregroundColor: Colors.white, // White icon on button
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
            indicator: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF9F70FD),
                  width: 2.5,
                ),
              ),
            ),
            labelColor: const Color(0xFF9F70FD),
            unselectedLabelColor: Colors.grey.shade400,
          )
        ),
        home: isHubSetupComplete ? const HomeScreen() : const InitialHubScreen(),
      ),
    );
  }
}
