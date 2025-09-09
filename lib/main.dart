import 'package:educational_platform/homePages/admin_dashboard.dart';
import 'package:educational_platform/homePages/manage_videos_page.dart';
import 'package:educational_platform/homePages/profile_page.dart';
import 'package:educational_platform/usersPage.dart';
import 'package:educational_platform/run_videos.dart';
import 'package:educational_platform/liveStreamPage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'auth/login_page.dart';
import 'package:educational_platform/homePages/guest_dashboard.dart';
import 'package:educational_platform/homePages/users_dashboard.dart';
import 'auth/signup_page.dart';
import 'services/settings_service.dart';
import 'package:educational_platform/homePages/notifications_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // تهيئة Firebase بطريقة مبسطة
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // تكوين Firebase Auth للغة العربية
    await FirebaseAuth.instance.setLanguageCode('ar');
  } catch (e) {
    // في حالة وجود خطأ، سنتجاهله ونتابع تشغيل التطبيق
    debugPrint('Firebase initialization warning: $e');
  }

  // تشغيل التطبيق مباشرة
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: SettingsService.instance.stream(),
      builder: (context, snapshot) {
        final settings = snapshot.data;
        final platformTitle =
            (settings != null && settings.platformTitle.isNotEmpty)
            ? settings.platformTitle
            : 'المنصة التعليمية';

        return MaterialApp(
          title: platformTitle,
          debugShowCheckedModeBanner: false,
          // تكوين اتجاه التطبيق من اليمين لليسار
          locale: const Locale('ar', 'SA'),
          supportedLocales: const [
            Locale('ar', 'SA'), // Arabic
            Locale('en', 'US'), // English fallback
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // إجبار الاتجاه RTL لجميع الصفحات
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            );
          },
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
            // إعادة الخط السابق Noto Kufi Arabic لكل الموقع
            fontFamily: GoogleFonts.notoKufiArabic().fontFamily,
            textTheme: GoogleFonts.notoKufiArabicTextTheme(
              Theme.of(context).textTheme,
            ),
          ),
          home: const GuestDashboard(),
          routes: {
            '/login': (context) => const LoginPage(),
            '/signup': (context) => const SignUpPage(),
            '/guest_dashboard': (context) => const GuestDashboard(),
            '/users_dashboard': (context) => const UsersDashboard(),
            '/admin_dashboard': (context) => const AdminDashboard(),
            '/manage_videos': (context) => const ManageVideosPage(),
            '/users_page': (context) => const UsersPage(),
            '/run_videos': (context) => const RunVideosPage(
              title: 'فيديو افتراضي',
              videoUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
              description: 'هذا وصف لفيديو افتراضي.',
            ),
            '/live_stream': (context) => const LiveStreamPage(),
            '/profile_page': (context) => const ProfilePage(),
            '/notifications': (context) => const NotificationsPage(),
          },
        );
      },
    );
  }
}
