import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:educational_platform/homePages/admin_dashboard.dart';
import 'package:educational_platform/auth/login_page.dart';
import 'package:educational_platform/homePages/users_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:educational_platform/services/notification_service.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          // User is logged in, check their role.
          // Initialize notification token registration (fire-and-forget)
          NotificationService.instance.initAndRegisterToken();
          return RoleBasedRedirect(userId: snapshot.data!.uid);
        }

        // User is not logged in, show the login page.
        return const LoginPage();
      },
    );
  }
}

class RoleBasedRedirect extends StatelessWidget {
  final String userId;

  const RoleBasedRedirect({super.key, required this.userId});

  Future<String?> _getUserRole() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (userDoc.exists) {
        return userDoc.data()?['role'] as String?;
      }
    } catch (e) {
      debugPrint('Error fetching user role: $e');
    }
    return null; // Default or error case
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getUserRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          // Handle error or no data case, default to user dashboard
          return const UsersDashboard();
        }

        final role = snapshot.data;
        if (role?.toLowerCase() == 'admin') {
          return const AdminDashboard();
        } else {
          return const UsersDashboard();
        }
      },
    );
  }
}
