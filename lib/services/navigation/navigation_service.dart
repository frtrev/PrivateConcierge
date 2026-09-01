import 'package:flutter/services.dart';
import '../../core/models/poi.dart';

abstract interface class NavigationService {
  Future<bool> navigateTo(PointOfInterest point);
}

class PlatformNavigationService implements NavigationService {
  const PlatformNavigationService();
  static const _channel = MethodChannel('charon/navigation');

  @override
  Future<bool> navigateTo(PointOfInterest point) async {
    try {
      return await _channel.invokeMethod<bool>('navigate', {
            'latitude': point.coordinates.latitude,
            'longitude': point.coordinates.longitude,
            'name': point.name,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
