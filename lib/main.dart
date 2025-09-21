import 'package:educational_platform/homePages/admin_dashboard.dart';
import 'package:educational_platform/homePages/manage_videos_page.dart';
import 'package:educational_platform/homePages/profile_page.dart';
import 'package:educational_platform/homePages/users_page.dart';
import 'package:educational_platform/homePages/run_videos.dart';
import 'package:educational_platform/homePages/live_stream_page.dart';
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
import 'package:educational_platform/homePages/viewing_requests_page.dart';
import 'package:educational_platform/homePages/admin_video_details_page.dart';

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
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  // Keep primary Arabic font, add fallbacks for missing glyphs (Latin/emoji)
                  fontFamily: 'NotoKufiArabic',
                  fontFamilyFallback: ['NotoNaskhArabic', 'Roboto', 'sans-serif'],
                ),
                child: child!,
              ),
            );
          },
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
            // إعادة الخط السابق Noto Kufi Arabic لكل الموقع
            fontFamily: 'NotoKufiArabic',
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
            '/live_stream': (context) => const LiveStreamPage(),
            '/profile_page': (context) => const ProfilePage(),
            '/notifications': (context) => const NotificationsPage(),
            '/viewing_requests': (context) => const ViewingRequestsPage(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/admin_video_details') {
              final args = settings.arguments;
              if (args is Map) {
                final title = (args['title'] ?? '').toString();
                final videoUrl = (args['videoUrl'] ?? '').toString();
                final description = args['description']?.toString();
                return MaterialPageRoute(
                  builder: (_) => AdminVideoDetailsPage(
                    title: title,
                    videoUrl: videoUrl,
                    description: description,
                  ),
                  settings: settings,
                );
              }
              // Fallback if arguments are missing or invalid
              return MaterialPageRoute(
                builder: (_) => const AdminDashboard(),
                settings: settings,
              );
            }

            if (settings.name == '/run_videos') {
              final args = settings.arguments;
              if (args is Map) {
                final title = (args['title'] ?? '').toString();
                final videoUrl = (args['videoUrl'] ?? '').toString();
                final description = args['description']?.toString();
                return MaterialPageRoute(
                  builder: (_) => RunVideosPage(
                    title: title,
                    videoUrl: videoUrl,
                    description: (description != null && description.isNotEmpty)
                        ? description
                        : null,
                  ),
                  settings: settings,
                );
              }
              // If arguments are missing or invalid, fall back to a safe page
              return MaterialPageRoute(
                builder: (_) => const GuestDashboard(),
                settings: settings,
              );
            }
            return null; // Use default handling for other routes
          },
        );
      },
    );
  }
}
