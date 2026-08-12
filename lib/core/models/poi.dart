import 'geo.dart';
import 'opening_hours.dart';

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
    this.phoneNumber,
    this.website,
    this.openingHours,
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
  final String? phoneNumber;
  final Uri? website;
  final PlaceOpeningHours? openingHours;

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
    phoneNumber: phoneNumber,
    website: website,
    openingHours: openingHours,
  );
}
