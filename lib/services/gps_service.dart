import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GpsService {
  Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentLocation({
    Duration timeLimit = const Duration(seconds: 30),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        throw Exception('Location permission denied');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeLimit,
      );

      return position;
    } on TimeoutException {
      final lastKnown = await getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }
      throw Exception('Location timeout. Please try again in an open area.');
    } catch (e) {
      throw Exception('Failed to get location: ${e.toString()}');
    }
  }

  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      return null;
    }
  }
}
