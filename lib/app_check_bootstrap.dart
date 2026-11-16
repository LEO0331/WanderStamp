import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

Future<void> setupAppCheck() async {
  const siteKey = String.fromEnvironment('APP_CHECK_SITE_KEY');
  if (kIsWeb && siteKey.isNotEmpty) {
    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider(siteKey),
    );
  }
}
