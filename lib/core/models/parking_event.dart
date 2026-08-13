import 'geo.dart';

class ParkingEvent {
  const ParkingEvent({
    required this.id,
    required this.coordinates,
    required this.at,
  });

  final int id;
  final Coordinates coordinates;
  final DateTime at;
}
