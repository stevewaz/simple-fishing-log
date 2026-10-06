import 'package:geolocator/geolocator.dart';

enum LocationAccess {
  /// Permission granted and location services on.
  granted,

  /// Not yet asked, or previously denied but askable again.
  askable,

  /// Denied permanently — only system settings can change it.
  blocked,

  /// Location services are switched off on the device.
  servicesOff,
}

class LocationFix {
  const LocationFix(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class LocationService {
  /// Current state without prompting the user.
  Future<LocationAccess> access();

  /// Requests permission if needed, then returns one fix. Throws [LocationException].
  Future<LocationFix> currentLocation();

  Future<void> openSettings();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationAccess> access() async {
    // On web the services check isn't meaningful; the browser prompt is the source of truth.
    final permission = await Geolocator.checkPermission();
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return await Geolocator.isLocationServiceEnabled() ? LocationAccess.granted : LocationAccess.servicesOff;
      case LocationPermission.deniedForever:
        return LocationAccess.blocked;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.askable;
    }
  }

  @override
  Future<LocationFix> currentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('Location access is turned off for this app.');
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission was not granted.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Location services are turned off.');
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationFix(position.latitude, position.longitude);
    } catch (_) {
      // Includes timeouts. A single failure type keeps callers simple.
      throw const LocationException("Couldn't get your location.");
    }
  }

  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}
