import 'geo.dart';

class PointOfInterest {
  const PointOfInterest({
    required this.id,
    required this.regionId,
    required this.name,
    required this.coordinates,
    required this.category,
    required this.subcategory,
    required this.address,
    this.description,
    this.distanceMeters,
  });
  final String id;
  final String regionId;
  final String name;
  final Coordinates coordinates;
  final String category;
  final String subcategory;
  final String address;
  final String? description;
  final double? distanceMeters;

  PointOfInterest withDistance(double value) => PointOfInterest(
    id: id,
    regionId: regionId,
    name: name,
    coordinates: coordinates,
    category: category,
    subcategory: subcategory,
    address: address,
    description: description,
    distanceMeters: value,
  );
}
