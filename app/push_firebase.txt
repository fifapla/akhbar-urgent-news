// انسخ هذا المحتوى كله فوق محتوى الملف lib/push.dart بعد تنفيذ خطوات دليل الإشعارات.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

import 'firebase_options.dart';

const bool pushSupported = true;

bool get _android => defaultTargetPlatform == TargetPlatform.android;

Future<void> initPush(bool enabled) async {
  if (!_android) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (enabled) {
    await FirebaseMessaging.instance.requestPermission();
    await FirebaseMessaging.instance.subscribeToTopic('urgent');
  }
}

Future<void> setPush(bool enabled) async {
  if (!_android) return;
  final m = FirebaseMessaging.instance;
  if (enabled) {
    await m.requestPermission();
    await m.subscribeToTopic('urgent');
  } else {
    await m.unsubscribeFromTopic('urgent');
  }
}
