import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationInfo {
  final String city;
  final String area;
  final String country;
  final double latitude;
  final double longitude;

  LocationInfo({
    required this.city,
    required this.area,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  String get displayName {
    if (area.isNotEmpty && area != city) {
      return '$area, $city';
    }
    return city;
  }

  String get fullDisplayName {
    if (area.isNotEmpty && area != city) {
      return '$area, $city, $country';
    }
    return '$city, $country';
  }
}

class LocationService {
  LocationInfo? _cachedLocation;

  LocationInfo? get cachedLocation => _cachedLocation;

  Future<LocationInfo?> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return null;
      }

      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied');
        return null;
      }

      // Get precise position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100,
        ),
      );

      // Reverse geocode to get address
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        _cachedLocation = LocationInfo(
          city: place.locality ?? place.administrativeArea ?? '',
          area: place.subLocality ?? place.thoroughfare ?? '',
          country: place.country ?? '',
          latitude: position.latitude,
          longitude: position.longitude,
        );
        debugPrint('Location: ${_cachedLocation!.fullDisplayName}');
        return _cachedLocation;
      }

      return null;
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  /// Geocode a zip/postal code to a full location.
  Future<LocationInfo?> geocodeZip(String zip) async {
    try {
      final locations = await locationFromAddress(zip);
      if (locations.isEmpty) return null;

      final loc = locations.first;
      final placemarks = await placemarkFromCoordinates(
        loc.latitude,
        loc.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        _cachedLocation = LocationInfo(
          city: place.locality ?? place.administrativeArea ?? zip,
          area: place.subLocality ?? place.postalCode ?? '',
          country: place.country ?? '',
          latitude: loc.latitude,
          longitude: loc.longitude,
        );
        debugPrint('Zip geocoded: ${_cachedLocation!.fullDisplayName}');
        return _cachedLocation;
      }
      return null;
    } catch (e) {
      debugPrint('Zip geocode error: $e');
      return null;
    }
  }
}
