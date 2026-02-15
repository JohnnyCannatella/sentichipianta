import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PermissionService {
  Future<bool> requestNotificationPermissions() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final ios = plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final macos = plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    final macosGranted = await macos?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    final androidGranted = await android?.requestNotificationsPermission();

    return (iosGranted ?? true) &&
        (macosGranted ?? true) &&
        (androidGranted ?? true);
  }
}
