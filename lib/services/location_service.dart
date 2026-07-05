import 'package:geolocator/geolocator.dart';

class LocationService {
  // Define your target Office Coordinates (Example: Mumbai coordinates)
  static const double officeLatitude = 19.151266317528332;
  static const double officeLongitude = 72.992270021164077;
  static const double allowedRadiusInMeters = 300.0; // 300-meter boundary

  /// Checks permissions and returns true if the employee is within the office boundary
  static Future<bool> isEmployeeAtOffice() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Check if location services are enabled on the device
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    // 2. Handle app-level location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied. Enable them in settings.');
    }

    // 3. Get current high-accuracy position
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    // 4. Calculate the distance using Geolocator's built-in math utility
    double distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      officeLatitude,
      officeLongitude,
    );

    // Return true if they are within 100 meters
    return distanceInMeters <= allowedRadiusInMeters;
  }
}