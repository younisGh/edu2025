import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:educational_platform/auth/signup_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _verificationId;
  int? _resendToken;
  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutBack),
    );
    // Trigger fade-in on page load
    _fadeController.forward();
  }

  // Method to handle password reset
  Future<void> _resetPassword() async {
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('الرجاء إدخال رقم الهاتف')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Don't initialize Firebase again - it's already initialized in main()

      // Normalize phone: digits only and remove leading 0
      String phone = _phoneController.text.trim();
      phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (phone.startsWith('0')) phone = phone.substring(1);
      final fullPhone = '+964$phone';

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieve on some devices
          await _verifyAndReset(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          String errorMessage = 'فشل إرسال رمز التحقق';
          if (e.code == 'invalid-phone-number') {
            errorMessage = 'رقم الهاتف غير صحيح';
          } else if (e.code == 'too-many-requests') {
            errorMessage = 'تم تجاوز عدد المحاولات المسموح بها';
          } else if (e.code == 'app-not-authorized') {
            errorMessage = 'التطبيق غير مخول لاستخدام المصادقة الهاتفية';
          } else if (e.code == 'invalid-app-credential') {
            errorMessage = 'خطأ في إعدادات التطبيق - يرجى المحاولة لاحقاً';
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$errorMessage (${e.code})')));
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _isLoading = false;
          });
          _showResetPasswordDialog();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('حدث خطأ: ${e.toString()}')));
    }
  }

  Future<void> _verifyAndReset(PhoneAuthCredential credential) async {
    try {
      // Sign in with the credential
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;

      // Show dialog to enter new password
      _showNewPasswordDialog();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التحقق: ${e.toString()}')));
    }
  }

  void _showResetPasswordDialog() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الرمز'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تم إرسال رمز التحقق إلى هاتفك'),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'أدخل الرمز',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              if (codeController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء إدخال الرمز')),
                );
                return;
              }

              try {
                final credential = PhoneAuthProvider.credential(
                  verificationId: _verificationId!,
                  smsCode: codeController.text.trim(),
                );

                Navigator.pop(context);
                await _verifyAndReset(credential);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('الرمز غير صحيح')));
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  void _showNewPasswordDialog() {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعيين كلمة مرور جديدة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              final newPassword = newPasswordController.text.trim();
              final confirmPassword = confirmPasswordController.text.trim();

              if (newPassword.isEmpty || confirmPassword.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء ملء جميع الحقول')),
                );
                return;
              }

              if (newPassword != confirmPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('كلمتا المرور غير متطابقتين')),
                );
                return;
              }

              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await user.updatePassword(newPassword);
                  if (!mounted) return;

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تحديث كلمة المرور بنجاح')),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('حدث خطأ: ${e.toString()}')),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Normalize phone for email mapping (must match signup normalization)
    String phone = _phoneController.text.trim();
    phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.startsWith('0')) phone = phone.substring(1);
    final email = '$phone@eduApp.com';
    final password = _passwordController.text
        .trim(); // Trimmed password as discussed

    // Print statements for debugging
    print('Attempting login with Email: $email');
    print('Attempting login with Password: $password');

    try {
      // Don't initialize Firebase again - it's already initialized in main()
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw Exception('لم يتم العثور على المستخدم بعد تسجيل الدخول.');
      }

      // Fetch user role from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final role = userData['role'] as String?;

        final newRoute = role == 'Admin'
            ? '/admin_dashboard'
            : '/users_dashboard';
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(newRoute, (route) => false);
      } else {
        // If user document doesn't exist, default to user dashboard and log it.
        print(
          'Warning: User document not found in Firestore for UID: ${user.uid}',
        );
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/users_dashboard', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      print(
        'Firebase Auth Exception: ${e.code} - ${e.message}',
      ); // Detailed Firebase error
      String message = 'فشل تسجيل الدخول';
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'INVALID_LOGIN_CREDENTIALS' ||
          e.code == 'invalid-credential') {
        message = 'رقم الهاتف أو كلمة المرور غير صحيحة';
      } else if (e.code == 'invalid-email') {
        message = 'صيغة البريد الإلكتروني غير صحيحة (ناتج عن رقم الهاتف)';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$message (رمز الخطأ: ${e.code})')),
        );
      }
    } catch (e) {
      // Catch any other unexpected errors
      print('Generic Exception: ${e.toString()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ غير متوقع: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFF3EDF7), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.all(32.0),
                  width: 450,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated logo
                        ScaleTransition(
                          scale: _scale,
                          child: FadeTransition(
                            opacity: _fade,
                            child: Image.asset(
                              'assets/images/edu.png',
                              height: 64,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF430DD6),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Phone Number Field
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'رقم الهاتف',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF1E1E1E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 360;
                            final fieldFont = TextStyle(
                              fontSize: isNarrow ? 14 : 16,
                            );
                            final hintFont = TextStyle(
                              fontSize: isNarrow ? 13 : 14,
                              color: Colors.black45,
                            );
                            final codeFont = TextStyle(
                              fontSize: isNarrow ? 12 : 14,
                              color: Colors.black54,
                            );
                            return TextFormField(
                              controller: _phoneController,
                              textAlign: TextAlign.right,
                              keyboardType: TextInputType.phone,
                              maxLines: 1,
                              style: fieldFont,
                              validator: (value) => value?.isEmpty ?? true
                                  ? 'الرجاء إدخال رقم الهاتف'
                                  : null,
                              decoration: InputDecoration(
                                hintText: 'ادخل رقم الهاتف',
                                hintStyle: hintFont,
                                isDense: isNarrow,
                                suffixIcon: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Text('+964', style: codeFont),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD9D9D9),
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: isNarrow ? 10 : 12,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // Password Field
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'كلمة المرور',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF1E1E1E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          textAlign: TextAlign.right,
                          obscureText: _obscurePassword,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'الرجاء إدخال كلمة المرور'
                              : null,
                          decoration: InputDecoration(
                            hintText: 'ادخل كلمة المرور',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFD9D9D9),
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Login Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2C2C2C),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 2,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'دخول',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Forgot Password
                        TextButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'نسيت كلمة المرور؟',
                                  style: TextStyle(
                                    color: Color(0xFF1E88E5),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),

                        // Register Link (responsive to avoid overflow)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 260;
                            final labelStyle = TextStyle(
                              color: const Color(0xFF6200EE),
                              fontWeight: FontWeight.bold,
                              fontSize: isNarrow ? 13 : 14,
                            );
                            final infoStyle = TextStyle(
                              color: Colors.grey,
                              fontSize: isNarrow ? 13 : 14,
                            );
                            return Directionality(
                              textDirection: TextDirection.rtl,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'ليس لديك حساب؟',
                                    style: infoStyle,
                                  ),
                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const SignUpPage(),
                                              ),
                                            ),
                                    child: Text(
                                      'إنشاء حساب جديد',
                                      style: labelStyle,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
