import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_service.dart';
import 'offline_queue.dart';

/// İnternet bağlantısını izler ve bağlantı geldiğinde offline kuyruğunu
/// otomatik olarak API'ye gönderir (Kural 3: Offline-first).
class SyncService {
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static bool _isSyncing = false; // Aynı anda iki senkronizasyonu engeller

  /// connectivity_plus 7.x `List<ConnectivityResult>` döndürür.
  /// Listede gerçek bir ağ (wifi/mobil/ethernet/vpn) varsa internet var sayılır.
  static bool _isOnline(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
  }

  /// Anlık internet durumunu döndürür.
  static Future<bool> hasInternet() async {
    final results = await Connectivity().checkConnectivity();
    return _isOnline(results);
  }

  /// Uygulama açılışında çağrılır. Bağlantı değişimlerini dinlemeye başlar
  /// ve açılışta bekleyen kuyruğu bir kez göndermeyi dener.
  static void startListening() {
    _subscription ??= Connectivity().onConnectivityChanged.listen((results) {
      if (_isOnline(results)) {
        flushQueue();
      }
    });
    // Açılışta zaten internet varsa bekleyenleri gönder
    flushQueue();
  }

  static void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Kuyruktaki tüm görevleri ve bekleyen istekleri (arıza/masraf) sırayla API'ye gönderir.
  /// 'ok'       -> kuyruktan silinir (gönderildi sayılır)
  /// 'rejected' -> kuyruktan silinir ama sayılmaz (sunucu kalıcı reddetti; ör. görev zaten
  ///               kapalı — tekrar denemek anlamsız ve arkasındaki kayıtları tıkar)
  /// 'retry'    -> ağ/geçici hata; bu tur biter, kalanlar sonraki bağlantıda denenir.
  /// Gönderilen kayıt sayısını döndürür.
  static Future<int> flushQueue() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    int gonderilen = 0;

    try {
      // İnternet yoksa hiç uğraşma
      if (!await hasInternet()) return 0;

      final items = await OfflineQueue.getQueue();
      for (final item in items) {
        final int isEmriId = (item['is_emri_id'] as num).toInt();
        final double enlem = (item['enlem'] as num).toDouble();
        final double boylam = (item['boylam'] as num).toDouble();
        final String foto = item['fotograf_base64'] as String;

        final sonuc = await ApiService.saveTask(isEmriId, enlem, boylam, foto);
        if (sonuc == 'retry') break;
        await OfflineQueue.removeFromQueue(item['id'] as int);
        if (sonuc == 'ok') gonderilen++;
      }

      // Genel istek kuyruğu (arıza bildirimi, masraf vb. — Kural 3)
      final requests = await OfflineQueue.getRequests();
      for (final req in requests) {
        final body = jsonDecode(req['body'] as String) as Map<String, dynamic>;
        final sonuc = await ApiService.postQueued(req['endpoint'] as String, body);
        if (sonuc == 'retry') break;
        await OfflineQueue.removeRequest(req['id'] as int);
        if (sonuc == 'ok') gonderilen++;
      }
    } catch (_) {
      // Sessizce yut; bir sonraki bağlantı değişiminde tekrar denenecek.
    } finally {
      _isSyncing = false;
    }

    return gonderilen;
  }
}
