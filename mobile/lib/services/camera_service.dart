import 'dart:io';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import 'package:flutter/foundation.dart';

// Arka planda çalışacak fonksiyon
Future<Uint8List?> _processWatermark(Map<String, dynamic> data) async {
  try {
    final Uint8List bytes = data['bytes'];
    final double? lat = data['lat'];
    final double? lng = data['lng'];

    // Resmi decode et
    img.Image? originalImage = img.decodeImage(bytes);
    if (originalImage == null) return null;

    // Sadece çok büyük (örn. 12MP+) fotoğrafları makul boyuta indir; aksi halde dokunma.
    if (originalImage.width > 1920) {
      originalImage = img.copyResize(originalImage, width: 1920);
    }

    // Watermark Metni (mikrosaniyeleri at, saniyeye kadar göster).
    // Konum alınamadıysa en azından tarih/saat damgası basılır (Kural 4).
    String timestamp = DateTime.now().toString().split('.').first;
    String watermarkText = (lat != null && lng != null)
        ? "Tarih: $timestamp\nKonum: $lat, $lng"
        : "Tarih: $timestamp\nKonum: alinamadi";

    // Okunabilirlik için önce koyu gölge, üstüne kırmızı metin
    img.drawString(originalImage, watermarkText, font: img.arial48, x: 22, y: 22, color: img.ColorRgb8(0, 0, 0));
    img.drawString(originalImage, watermarkText, font: img.arial48, x: 20, y: 20, color: img.ColorRgb8(255, 60, 60));

    // Yüksek kaliteyle JPEG'e encode et
    return img.encodeJpg(originalImage, quality: 88);
  } catch (e) {
    return null;
  }
}

class CameraService {
  // Galeriyi atlayıp sadece kamerayı kullandıracak (Kural 2)
  static Future<List<CameraDescription>> getCameras() async {
    return await availableCameras();
  }

  // Fotoğrafa GPS ve Tarih bilgisi filigranı (watermark) basar (Kural 4).
  // Konum yoksa null geçilebilir; o durumda yalnızca tarih/saat damgalanır.
  static Future<String?> addWatermark(String imagePath, double? lat, double? lng) async {
    try {
      final File file = File(imagePath);
      final Uint8List bytes = await file.readAsBytes();
      
      // Isolate (Ayrı thread) içerisinde çalıştır, UI donmasın!
      final watermarkedBytes = await compute(_processWatermark, {
        'bytes': bytes,
        'lat': lat,
        'lng': lng,
      });

      if (watermarkedBytes != null) {
        await file.writeAsBytes(watermarkedBytes);
        return imagePath;
      }
      return null;
    } catch (e) {
      debugPrint("Watermark hatası: $e");
      return null;
    }
  }
}
