import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:educational_platform/homePages/users_dashboard.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  String? _verificationId;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _canResendOtp = true;
  int _otpResendTime = 60;
  Timer? _resendTimer;
  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneNumberController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
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
    _fade = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutBack),
    );
    _fadeController.forward();
  }

  void _startResendTimer() {
    setState(() {
      _canResendOtp = false;
      _otpResendTime = 60;
    });

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_otpResendTime > 0) {
        setState(() => _otpResendTime--);
      } else {
        setState(() => _canResendOtp = true);
        timer.cancel();
      }
    });
  }

  Future<void> _resendOtp() async {
    if (!_canResendOtp) return;

    setState(() => _isLoading = true);
    _otpController.clear();

    try {
      // Don't initialize Firebase again - it's already initialized in main()

      // Format phone number properly (same as in _verifyPhoneNumber)
      String phoneNumber = _phoneNumberController.text.trim();
      phoneNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (phoneNumber.startsWith('0')) {
        phoneNumber = phoneNumber.substring(1);
      }
      final fullPhoneNumber = '+964$phoneNumber';

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInWithPhoneNumber(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل إعادة الإرسال: ${e.message}')),
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _isLoading = false;
          });
          _startResendTimer();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم إعادة إرسال رمز التحقق')),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
        // Use the last resending token when available to avoid creating a fresh session unnecessarily
        forceResendingToken: _resendToken,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء إعادة إرسال الرمز')),
        );
      }
    }
  }

  int? _resendToken;
  DateTime? _lastRequestTime;
  int _requestCount = 0;
  static const int _maxRequestsPerHour = 5;

  bool _canMakeRequest() {
    final now = DateTime.now();

    // Reset counter if more than 1 hour has passed
    if (_lastRequestTime != null &&
        now.difference(_lastRequestTime!).inHours >= 1) {
      _requestCount = 0;
    }

    return _requestCount < _maxRequestsPerHour;
  }

  Future<void> _verifyPhoneNumber() async {
    // Prevent overlapping requests which can invalidate the web reCAPTCHA token
    if (_isLoading) return;
    if (_formKey.currentState?.validate() ?? false) {
      // Check rate limiting
      if (!_canMakeRequest()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم تجاوز عدد المحاولات المسموح بها. يرجى المحاولة بعد ساعة',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      setState(() => _isLoading = true);

      try {
        // Format phone number properly
        String phoneNumber = _phoneNumberController.text.trim();
        // Remove any non-digit characters
        phoneNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');

        // Ensure the number starts with the country code
        if (phoneNumber.startsWith('0')) {
          phoneNumber = phoneNumber.substring(1);
        }

        final fullPhoneNumber = '+964$phoneNumber';

        // Validate phone number format for Iraq
        if (!RegExp(r'^\+964[0-9]{10}$').hasMatch(fullPhoneNumber)) {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'رقم الهاتف غير صحيح. يجب أن يكون 10 أرقام بعد رمز البلد',
                ),
              ),
            );
          }
          return;
        }

        // Update request tracking
        _requestCount++;
        _lastRequestTime = DateTime.now();

        // Create fresh reCAPTCHA verifier before each verification attempt
        await Future.delayed(const Duration(milliseconds: 1000));

        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: fullPhoneNumber,
          verificationCompleted: (PhoneAuthCredential credential) async {
            await _signInWithPhoneNumber(credential);
          },
          verificationFailed: (FirebaseAuthException e) {
            setState(() => _isLoading = false);
            if (mounted) {
              String errorMessage = 'فشل التحقق من رقم الهاتف';
              if (e.code == 'invalid-phone-number') {
                errorMessage = 'رقم الهاتف غير صحيح أو غير مدعوم';
              } else if (e.code == 'too-many-requests') {
                errorMessage =
                    'تم حظر الجهاز مؤقتاً بسبب كثرة المحاولات. يرجى المحاولة بعد عدة ساعات أو استخدام جهاز آخر';
              } else if (e.code == 'missing-client-identifier') {
                errorMessage = 'خطأ في إعدادات التطبيق. يرجى إبلاغ الدعم الفني';
              } else if (e.code == 'app-not-authorized') {
                errorMessage = 'التطبيق غير مخول لاستخدام المصادقة الهاتفية';
              } else if (e.code == 'invalid-app-credential') {
                errorMessage =
                    'انتهت صلاحية رمز الأمان. يرجى تحديث الصفحة والمحاولة مرة أخرى';
              } else if (e.code == 'quota-exceeded') {
                errorMessage =
                    'تم تجاوز الحد المسموح لإرسال الرسائل. حاول لاحقاً';
              } else if (e.code == 'captcha-check-failed') {
                errorMessage = 'فشل التحقق من الأمان. يرجى المحاولة مرة أخرى';
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '$errorMessage\nالرقم: $fullPhoneNumber\nالخطأ: ${e.code}',
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
              print('Phone verification failed: ${e.code} - ${e.message}');
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            setState(() {
              _verificationId = verificationId;
              _resendToken = resendToken;
              _isLoading = false;
            });
            _startResendTimer();
            _showOtpDialog();
            print('SMS sent successfully to: $fullPhoneNumber');
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            _verificationId = verificationId;
            print('Code auto-retrieval timeout for: $fullPhoneNumber');
          },
          timeout: const Duration(seconds: 120), // Increased timeout
          forceResendingToken: _resendToken,
        );
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('حدث خطأ: ${e.toString()}')));
        }
      }
    }
  }

  Future<void> _signInWithPhoneNumber(PhoneAuthCredential credential) async {
    // This method is now only used to confirm the phone number is valid.
    // The actual user creation will happen in _createUserWithEmailAndPassword.
    try {
      // We sign in temporarily to confirm the credential is valid.
      await FirebaseAuth.instance.signInWithCredential(credential);

      // IMPORTANT: Immediately sign out the phone user. We will create a new
      // user with email and password as the primary authentication method.
      await FirebaseAuth.instance.signOut();

      // Now, create the permanent user account with email and password.
      await _createUserWithEmailAndPassword();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التحقق من الرمز: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createUserWithEmailAndPassword() async {
    try {
      // Don't initialize Firebase again - it's already initialized in main()

      // Format phone number for email
      String phoneNumber = _phoneNumberController.text.trim();
      phoneNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (phoneNumber.startsWith('0')) {
        phoneNumber = phoneNumber.substring(1);
      }

      final email = '$phoneNumber@eduApp.com';
      final password = _passwordController.text.trim();

      // Create the user with email and password
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      if (user != null) {
        // Update display name
        await user.updateDisplayName(_nameController.text.trim());

        // Save user data to Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': _nameController.text.trim(),
          'phone': '+964$phoneNumber',
          'email': email,
          'role': 'user', // Default role
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Navigate to the user dashboard
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const UsersDashboard()),
            (route) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage = 'فشل إنشاء الحساب';
        if (e.code == 'weak-password') {
          errorMessage = 'كلمة المرور ضعيفة جدًا';
        } else if (e.code == 'email-already-in-use') {
          errorMessage = 'الحساب موجود مسبقًا';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  void _showOtpDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'أدخل رمز التحقق',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'تم إرسال رمز التحقق إلى الرقم\n${_phoneNumberController.text.trim()}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextFormField(
                  controller: _otpController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '- - - - - -',
                    hintStyle: const TextStyle(
                      letterSpacing: 8,
                      color: Colors.grey,
                    ),
                    border: const OutlineInputBorder(),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    if (value.length == 6) {
                      _verifyOtp();
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'لم تستلم الرمز؟ ',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  TextButton(
                    onPressed: _canResendOtp ? _resendOtp : null,
                    child: Text(
                      _canResendOtp
                          ? 'إعادة إرسال الرمز'
                          : 'إعادة إرسال بعد $_otpResendTime ثانية',
                      style: TextStyle(
                        color: _canResendOtp
                            ? Theme.of(context).primaryColor
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : _verifyOtp,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.length != 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء إدخال رمز مكون من 6 أرقام')),
        );
      }
      return;
    }

    if (_verificationId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('انتهت صلاحية جلسة التحقق، يرجى المحاولة مرة أخرى'),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );

      await _signInWithPhoneNumber(credential);

      if (mounted) {
        Navigator.pop(context); // Close OTP dialog
      }
    } catch (e) {
      String errorMessage = 'رمز التحقق غير صحيح';
      if (e is FirebaseAuthException) {
        if (e.code == 'invalid-verification-code') {
          errorMessage = 'رمز التحقق غير صحيح';
        } else if (e.code == 'session-expired') {
          errorMessage = 'انتهت صلاحية الجلسة، يرجى طلب رمز جديد';
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
                child: FadeTransition(
                  opacity: _fade,
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
                              'إنشاء حساب جديد',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF430DD6),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Name Field
                            const Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'الاسم',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF1E1E1E),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameController,
                              textAlign: TextAlign.right,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال الاسم';
                                }
                                return null;
                              },
                              decoration: InputDecoration(
                                hintText: 'أدخل الاسم الكامل',
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
                              ),
                            ),
                            const SizedBox(height: 20),

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
                                  controller: _phoneNumberController,
                                  textAlign: TextAlign.right,
                                  keyboardType: TextInputType.phone,
                                  maxLines: 1,
                                  style: fieldFont,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'الرجاء إدخال رقم الهاتف';
                                    } else if (!RegExp(
                                      r'^[0-9+\s-]{10,}$',
                                    ).hasMatch(value)) {
                                      return 'الرجاء إدخال رقم هاتف صحيح';
                                    }
                                    return null;
                                  },
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
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال كلمة المرور';
                                } else if (value.length < 6) {
                                  return 'يجب أن تكون كلمة المرور 6 أحرف على الأقل';
                                }
                                return null;
                              },
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
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Confirm Password Field
                            const Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'تأكيد كلمة المرور',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF1E1E1E),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _confirmPasswordController,
                              textAlign: TextAlign.right,
                              obscureText: _obscureConfirmPassword,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء تأكيد كلمة المرور';
                                } else if (value != _passwordController.text) {
                                  return 'كلمتا المرور غير متطابقتين';
                                }
                                return null;
                              },
                              decoration: InputDecoration(
                                hintText: 'أعد إدخال كلمة المرور',
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
                                    _obscureConfirmPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirmPassword =
                                          !_obscureConfirmPassword;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),

                            // Sign Up Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submitForm,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF430DD6),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 2,
                                ),
                                child: const Text(
                                  'إنشاء الحساب',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Already have an account
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text(
                                    'تسجيل الدخول',
                                    style: TextStyle(
                                      color: Color(0xFF6200EE),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Text(
                                  'لديك حساب بالفعل؟',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
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
        ),
      ),
    );
  }

  Future<void> _submitForm() async {
    // Prevent double-tap from sending multiple verification requests
    if (_isLoading) return;
    if (_formKey.currentState!.validate()) {
      // Check if passwords match
      if (_passwordController.text != _confirmPasswordController.text) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('كلمتا المرور غير متطابقتين'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Verify phone number and show OTP dialog
      await _verifyPhoneNumber();
    }
  }
}
