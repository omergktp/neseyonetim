import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Son getCurrentLocation() çağrısı null döndüyse nedeni (kullanıcıya gösterilebilir).
  static String? sonHata;

  // Cihazın anlık konumunu alır. Sahte (mock) konum tespit edilirse reddedilir (Kural 4).
  static Future<Position?> getCurrentLocation() async {
    sonHata = null;
    bool serviceEnabled;
    LocationPermission permission;

    // Konum servisleri açık mı?
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      sonHata = 'Konum servisleri kapalı. Lütfen açın.';
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        sonHata = 'Konum izni verilmedi.';
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      sonHata = 'Konum izni kalıcı olarak reddedilmiş. Ayarlar > Uygulamalar üzerinden izin verin.';
      return null;
    }

    // Yüksek doğrulukla konumu al
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    // KURAL 4: Sahte GPS (mock location) uygulamalarıyla üretilen konum kabul edilmez.
    if (position.isMocked) {
      sonHata = 'Sahte (mock) konum tespit edildi. Lütfen sahte konum uygulamasını kapatın.';
      return null;
    }

    return position;
  }

  // İki konum arasındaki mesafeyi metre cinsinden hesaplar
  static double calculateDistance(double startLat, double startLng, double endLat, double endLng) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  // 50 Metre kuralı doğrulaması
  static bool isWithinRange(double currentLat, double currentLng, double siteLat, double siteLng, {double maxDistance = 50.0}) {
    double distance = calculateDistance(currentLat, currentLng, siteLat, siteLng);
    return distance <= maxDistance;
  }
}
