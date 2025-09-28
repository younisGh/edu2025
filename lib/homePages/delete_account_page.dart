import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _passwordController = TextEditingController();
  bool _confirm = false;
  bool _loading = false;
  String? _error;

  User? get _user => FirebaseAuth.instance.currentUser;

  bool get _usesPasswordProvider {
    final u = _user;
    if (u == null) return false;
    return u.providerData.any((p) => p.providerId == 'password');
  }

  Future<void> _delete() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      final user = _user;
      if (user == null) {
        setState(() {
          _error = 'لا يوجد مستخدم مسجل دخولًا.';
        });
        return;
      }

      // Reauthenticate if using email/password
      if (_usesPasswordProvider) {
        final password = _passwordController.text.trim();
        if (password.isEmpty) {
          setState(() {
            _error = 'الرجاء إدخال كلمة المرور لتأكيد الهوية.';
          });
          return;
        }
        final cred = EmailAuthProvider.credential(
          email: user.email ?? '',
          password: password,
        );
        await user.reauthenticateWithCredential(cred);
      }

      await user.delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الحساب بنجاح')),
        );
        // بعد الحذف يصبح المستخدم غير مسجل، نرجع لواجهة الزائر
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/guest_dashboard',
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      // requires-recent-login is common for sensitive actions
      if (e.code == 'requires-recent-login') {
        setState(() {
          _error =
              'لأمانك، تحتاج لإعادة تسجيل الدخول قبل حذف الحساب. الرجاء تسجيل الدخول مجددًا ثم العودة لهذه الصفحة.';
        });
      } else if (e.code == 'wrong-password') {
        setState(() {
          _error = 'كلمة المرور غير صحيحة.';
        });
      } else {
        setState(() {
          _error = 'حدث خطأ: ${e.message ?? e.code}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'حدث خطأ غير متوقع: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    final info = <Widget>[
      const Text(
        'حذف الحساب',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        user == null
            ? 'لا يوجد مستخدم مسجل دخولًا حاليًا.'
            : 'سيتم حذف حسابك نهائيًا من النظام. قد تفقد جميع البيانات المرتبطة بالحساب. لا يمكن التراجع عن هذه العملية.',
        style: const TextStyle(fontSize: 14, height: 1.8, color: Color(0xFF374151)),
      ),
      const SizedBox(height: 16),
      if (user != null && _usesPasswordProvider) ...[
        const Text(
          'لأسباب أمنية، الرجاء إدخال كلمة المرور لتأكيد الهوية:',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'كلمة المرور',
          ),
          onSubmitted: (_) {
            if (_confirm && !_loading) _delete();
          },
        ),
        const SizedBox(height: 16),
      ] else if (user != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFF59E0B)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'تم تسجيل الدخول باستخدام مزود ${user.providerData.isNotEmpty ? user.providerData.first.providerId : 'خارجي'}.'
            ' قد يُطلب منك إعادة تسجيل الدخول قبل الحذف (خاصة على الويب${kIsWeb ? '' : ''}).',
            style: const TextStyle(color: Color(0xFF92400E)),
          ),
        ),
        const SizedBox(height: 16),
      ],
      Row(
        children: [
          Checkbox(
            value: _confirm,
            onChanged: _loading
                ? null
                : (v) {
                    setState(() {
                      _confirm = v ?? false;
                    });
                  },
          ),
          const Expanded(
            child: Text(
              'أقر بأنني أرغب في حذف الحساب نهائيًا ولا يمكن التراجع عن ذلك.',
            ),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: const TextStyle(color: Colors.red),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: (!_confirm || _loading || user == null) ? null : _delete,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFEF2F2),
            foregroundColor: const Color(0xFF991B1B),
          ),
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever),
          label: const Text('حذف الحساب نهائيًا'),
        ),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _loading
            ? null
            : () {
                Navigator.of(context).maybePop();
              },
        icon: const Icon(Icons.arrow_back),
        label: const Text('رجوع'),
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('حذف الحساب')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                children: info,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
