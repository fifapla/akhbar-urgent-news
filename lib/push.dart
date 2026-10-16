// الإشعارات عبر فايربيس مع أنماط تنبيه (صوت واهتزاز، صوت، اهتزاز، صامت).
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

const bool pushSupported = true;

bool get _android => defaultTargetPlatform == TargetPlatform.android;

const List<String> _styles = ['sv', 's', 'v', 'q'];

/// قنوات الإشعارات في أندرويد: كل نمط له قناة بصوته واهتزازه.
Future<void> _channels() async {
  final pl = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (pl == null) return;
  await pl.createNotificationChannel(const AndroidNotificationChannel('urgent_sv', 'عاجل: صوت واهتزاز',
      importance: Importance.high, playSound: true, enableVibration: true));
  await pl.createNotificationChannel(const AndroidNotificationChannel('urgent_s', 'عاجل: صوت فقط',
      importance: Importance.high, playSound: true, enableVibration: false));
  await pl.createNotificationChannel(const AndroidNotificationChannel('urgent_v', 'عاجل: اهتزاز فقط',
      importance: Importance.high, playSound: false, enableVibration: true));
  await pl.createNotificationChannel(const AndroidNotificationChannel('urgent_q', 'عاجل: صامت',
      importance: Importance.low, playSound: false, enableVibration: false));
}

Future<void> _subscribe(String style) async {
  final m = FirebaseMessaging.instance;
  for (final s in _styles) {
    if (s == style) {
      await m.subscribeToTopic('urgent_$s');
    } else {
      await m.unsubscribeFromTopic('urgent_$s');
    }
  }
  await m.unsubscribeFromTopic('urgent');
}

Future<void> initPush(bool enabled, String style) async {
  if (!_android) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _channels();
  if (enabled) {
    await FirebaseMessaging.instance.requestPermission();
    await _subscribe(style);
  }
}

Future<void> setPush(bool enabled, String style) async {
  if (!_android) return;
  final m = FirebaseMessaging.instance;
  if (enabled) {
    await m.requestPermission();
    await _subscribe(style);
  } else {
    for (final s in _styles) {
      await m.unsubscribeFromTopic('urgent_$s');
    }
  }
}

Future<void> setPushStyle(String style) async {
  if (!_android) return;
  await _subscribe(style);
}
