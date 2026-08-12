import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

abstract interface class NotificationService {
  Future<void> initialize();
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
}

class LocalNotificationService implements NotificationService {
  static const _carChannel = MethodChannel('charon/car');
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          notificationCategories: <DarwinNotificationCategory>[
            DarwinNotificationCategory(
              'charon_alert',
              options: <DarwinNotificationCategoryOption>{
                DarwinNotificationCategoryOption.allowInCarPlay,
                DarwinNotificationCategoryOption.allowAnnouncement,
              },
            ),
          ],
        ),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'routine_alerts',
          'Routine alerts',
          channelDescription: 'Private reminders based on learned routines',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: 'charon_alert'),
      ),
    );
    try {
      await _carChannel.invokeMethod<void>('showAlert', {
        'title': title,
        'body': body,
      });
    } on PlatformException {
      // The system notification is still delivered when no car is connected.
    }
  }
}
