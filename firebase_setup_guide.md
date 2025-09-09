# دليل إعداد Firebase للمصادقة الهاتفية

## المشكلة: INVALID_APP_CREDENTIAL

هذا الخطأ يحدث عندما لا يكون Firebase مُعد بشكل صحيح للمصادقة الهاتفية. إليك الخطوات المطلوبة:

## 1. تفعيل Phone Authentication في Firebase Console

1. اذهب إلى [Firebase Console](https://console.firebase.google.com/)
2. اختر مشروعك: `educational-platform-16729`
3. اذهب إلى **Authentication** > **Sign-in method**
4. فعّل **Phone** provider
5. احفظ التغييرات

## 2. إضافة Authorized Domains

في نفس صفحة Sign-in method:
1. انزل إلى قسم **Authorized domains**
2. أضف النطاقات التالية:
   - `localhost`
   - `127.0.0.1`
   - `educational-platform-16729.firebaseapp.com`
   - `educational-platform-16729.web.app`

## 3. إعداد reCAPTCHA للويب

1. اذهب إلى [Google Cloud Console](https://console.cloud.google.com/)
2. اختر مشروعك: `educational-platform-16729`
3. فعّل **reCAPTCHA Enterprise API**
4. أو استخدم reCAPTCHA v2 العادي

## 4. إضافة SHA-256 Fingerprints للأندرويد

في Firebase Console:
1. اذهب إلى **Project Settings** > **General**
2. في قسم **Your apps**، اختر تطبيق Android
3. أضف SHA-256 fingerprints:

```bash
# للحصول على debug fingerprint
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# للحصول على release fingerprint
keytool -list -v -keystore your-release-key.keystore -alias your-key-alias
```

## 5. إعداد OAuth Consent Screen

1. اذهب إلى [Google Cloud Console](https://console.cloud.google.com/)
2. اختر **APIs & Services** > **OAuth consent screen**
3. املأ المعلومات المطلوبة:
   - App name: `Educational Platform`
   - User support email: بريدك الإلكتروني
   - Developer contact information: بريدك الإلكتروني

## 6. تحديث إعدادات التطبيق

تأكد من أن ملف `google-services.json` محدث ويحتوي على:
- `client_id` صحيح
- `api_key` صحيح
- `project_id` صحيح

## 7. إعادة تنزيل ملفات التكوين

بعد إجراء التغييرات:
1. أعد تنزيل `google-services.json` للأندرويد
2. أعد تنزيل `GoogleService-Info.plist` لـ iOS
3. حدث `firebase_options.dart`

## 8. اختبار التكوين

```bash
# تشغيل التطبيق
flutter run

# أو للويب
flutter run -d web-server --web-port 8080
```

## ملاحظات مهمة

- تأكد من أن رقم الهاتف يبدأ بـ `+964` للعراق
- استخدم أرقام هواتف حقيقية للاختبار
- قد تستغرق التغييرات في Firebase Console بضع دقائق لتصبح فعالة
- للاختبار، يمكنك إضافة أرقام هواتف تجريبية في Firebase Console

## أرقام الاختبار (اختياري)

في Firebase Console > Authentication > Sign-in method > Phone:
يمكنك إضافة أرقام هواتف تجريبية مع رموز تحقق ثابتة للاختبار.
