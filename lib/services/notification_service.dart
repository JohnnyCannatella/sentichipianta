import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextNotificationId = 2000;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(settings);

      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } on MissingPluginException {
      // Plugin not registered (e.g. hot restart without full rebuild).
      return;
    }

    _initialized = true;
  }

  Future<void> showCriticalAlert({required String title, required String body}) {
    return _plugin.show(
      1001,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'critical_alerts',
          'Critical Alerts',
          channelDescription: 'Avvisi per condizioni critiche della pianta',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> showRoutineAlert({required String title, required String body}) {
    return _plugin.show(
      _nextNotificationId++,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'routine_alerts',
          'Routine Alerts',
          channelDescription: 'Promemoria e alert della routine della pianta',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
