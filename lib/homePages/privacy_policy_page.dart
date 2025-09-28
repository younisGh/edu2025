import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get _isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      _sectionTitle('سياسة الخصوصية'),
      _paragraph(
        'نحن نلتزم بحماية خصوصيتك. توضح هذه السياسة كيفية جمعنا ومعالجتنا واستخدامنا لمعلوماتك عند استخدامك لمنصتنا التعليمية. باستخدامك للتطبيق فأنت توافق على ممارسات الخصوصية الموضحة هنا.',
      ),
      _divider(),
      _sectionTitle('المعلومات التي نجمعها'),
      _bulletList([
        'معلومات الحساب: الاسم، البريد الإلكتروني، وصورة الملف الشخصي (إن وُجدت).',
        'بيانات الاستخدام: سجلات المشاهدة، التفضيلات، التفاعل مع الفيديوهات والبث المباشر.',
        'الملفات والوسائط: عند رفع صور أو ملفات تعليمية ضمن حدود الصلاحيات.',
        if (_isAndroid || _isIOS)
          'أذونات الجهاز (اختياري): الكاميرا والميكروفون للبث المباشر ومكالمات الفيديو.',
      ]),
      _divider(),
      _sectionTitle('كيفية استخدامنا للمعلومات'),
      _bulletList([
        'تقديم الخدمات الأساسية: تشغيل الفيديوهات، البث المباشر، وإدارة الحساب.',
        'تحسين التجربة: تخصيص المحتوى واقتراحات الفيديوهات وتحليلات الأداء.',
        'التواصل: إرسال إشعارات مهمة حول الدروس أو التحديثات (يمكنك التحكم في الإشعارات).',
        'الأمان: كشف ومنع الأنشطة غير المصرح بها أو المخالفة لشروط الاستخدام.',
      ]),
      _divider(),
      _sectionTitle('التخزين والأمان'),
      _bulletList([
        'نستخدم خدمات سحابية موثوقة لتخزين البيانات مع ضوابط وصول صارمة.',
        if (kIsWeb)
          'الويب: قد نستخدم LocalStorage/SessionStorage لتخزين تفضيلات بسيطة على جهازك.',
        if (_isAndroid || _isIOS)
          'الجوال: يتم الالتزام بإرشادات النظام الأساسي لضمان أمان البيانات والأذونات.',
      ]),
      _divider(),
      _sectionTitle('مشاركة البيانات'),
      _bulletList([
        'لا نبيع بياناتك الشخصية.',
        'قد نشارك بيانات محدودة مع مزودي خدمات موثوقين (مثل البث أو الإشعارات) بهدف تشغيل الميزات الأساسية فقط.',
        'نلتزم بالحد الأدنى من البيانات اللازمة لتقديم الخدمة.',
      ]),
      _divider(),
      _sectionTitle('حقوقك'),
      _bulletList([
        'الوصول إلى بياناتك وتحديثها.',
        'طلب حذف بياناتك حيثما كان ذلك ممكنًا قانونيًا وتقنيًا.',
        'إدارة تفضيلات الإشعارات وجمع البيانات من الإعدادات.',
      ]),
      _divider(),
      _sectionTitle('ملفات تعريف الارتباط (Cookies)'),
      _paragraph(
        kIsWeb
            ? 'قد يستخدم الموقع ملفات تعريف الارتباط لتحسين الأداء والتجربة. يمكنك إدارة إعدادات الكوكيز من إعدادات المتصفح.'
            : 'لا يستخدم التطبيق ملفات تعريف الارتباط على الأجهزة، وقد تستخدم خدمات الجهات الخارجية تقنيات مشابهة بما يتوافق مع سياساتها.',
      ),
      _divider(),
      _sectionTitle('سياسات خاصة بالمنصة'),
      if (_isAndroid)
        _platformCard('Android', [
          'استخدام الكاميرا والميكروفون يتطلب موافقتك الصريحة.',
          'يمكنك تعديل الأذونات من إعدادات النظام في أي وقت.',
        ]),
      if (_isIOS)
        _platformCard('iOS', [
          'نلتزم بإرشادات Apple للخصوصية.',
          'إشعارات، كاميرا، وميكروفون تتطلب موافقة المستخدم ويمكن إلغاؤها من الإعدادات.',
        ]),
      if (kIsWeb)
        _platformCard('Web', [
          'قد نستخدم التخزين المحلي للمتصفح لتحسين الأداء وتجربة المستخدم.',
          'يمكنك مسح بيانات الموقع من إعدادات المتصفح.',
        ]),
      if (_isWindows || _isLinux || _isMacOS)
        _platformCard('سطح المكتب', [
          'يتم تخزين بيانات التفضيلات محليًا على الجهاز أو في السحابة حسب الإعدادات.',
          'يمكنك حذف البيانات المحلية عبر إعدادات التطبيق أو النظام.',
        ]),
      _divider(),
      _sectionTitle('خصوصية الأطفال'),
      _paragraph(
        'لا نستهدف الأطفال دون السن القانوني بشكل مباشر. إذا كنت تعتقد أنه تم جمع بيانات طفل بالخطأ، الرجاء التواصل معنا لحذفها.',
      ),
      _divider(),
      _sectionTitle('التغييرات على هذه السياسة'),
      _paragraph(
        'قد نقوم بتحديث هذه السياسة من حين لآخر. سنخطرك بأي تغييرات جوهرية من خلال التطبيق أو عبر الإشعارات.',
      ),
      _divider(),
      _sectionTitle('التواصل معنا'),
      _paragraph(
        'للاستفسارات المتعلقة بالخصوصية، يمكنك التواصل مع فريق الدعم عبر صفحة الإعدادات أو قنوات الاتصال المعلنة داخل المنصة.',
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سياسة الخصوصية')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                itemBuilder: (_, i) => sections[i],
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemCount: sections.length,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    );
  }

  Widget _paragraph(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        height: 1.8,
        color: Color(0xFF374151),
      ),
    );
  }

  Widget _bulletList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (e) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Text(
                    e,
                    style: const TextStyle(fontSize: 14, height: 1.8),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  Widget _platformCard(String title, List<String> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.privacy_tip, color: Color(0xFF6D28D9)),
              const SizedBox(width: 8),
              Text(
                'اعتبارات منصة $title',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _bulletList(items),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 24);
}
