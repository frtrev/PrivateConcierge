abstract interface class NotificationService {
  Future<void> initialize();
}

class PlaceholderNotificationService implements NotificationService {
  @override
  Future<void> initialize() async {}
}
