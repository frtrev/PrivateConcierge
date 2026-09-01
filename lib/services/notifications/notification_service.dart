import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum CarNotificationAction { read, directions }

abstract interface class NotificationService {
  Future<void> initialize();
  Future<void> show({
    required int id,
    required String title,
    required String body,
    CarNotificationAction action = CarNotificationAction.read,
    double? latitude,
    double? longitude,
    String? placeName,
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
        ?.requestPermissions(
          alert: true,
          badge: false,
          sound: true,
          carPlay: true,
        );
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    CarNotificationAction action = CarNotificationAction.read,
    double? latitude,
    double? longitude,
    String? placeName,
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
        iOS: DarwinNotificationDetails(
          categoryIdentifier: 'charon_alert',
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
    );
    try {
      await _carChannel.invokeMethod<void>('publishNotification', {
        'id': id,
        'title': title,
        'body': body,
        'action': action.name,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'placeName': ?placeName,
      });
    } on MissingPluginException {
      // The CarPlay bridge only exists on iOS.
    }
  }
}
