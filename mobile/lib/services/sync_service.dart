import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  /// Test dikişi: birim testte gerçek connectivity eklentisi çalışmaz;
  /// test sahte bir kontrol enjekte eder. Üretimde daima hasInternet'tir.
  static Future<bool> Function() internetKontrol = hasInternet;

  /// Test dikişleri: birim testte gerçek Supabase istemcisi çalışmaz;
  /// test 'ok' | 'rejected' | 'retry' döndüren sahteler enjekte eder.
  /// Üretimde daima ApiService'e gider.
  static Future<String> Function(
          int isEmriId, double enlem, double boylam, String foto, String? istekId)
      gorevGonder = (id, enlem, boylam, foto, istekId) =>
          ApiService.saveTask(id, enlem, boylam, foto, istekId: istekId);
  static Future<String> Function(String endpoint, Map<String, dynamic> body) istekGonder =
      ApiService.postQueued;

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
  /// 'rejected' -> kuyruktan silinir ama SESSİZCE KAYBOLMAZ: dead-letter'a
  ///               taşınır ve kullanıcıya gösterilir (uzman paneli 🔴2b).
  /// 'retry'    -> ağ/geçici hata; bu tur biter, kalanlar sonraki bağlantıda denenir.
  /// Başka bir personelin (çıkış yapmış hesabın) kayıtları GÖNDERİLMEZ; o
  /// personel yeniden giriş yapana dek bekler (yanlış kimlikle yazım önlenir).
  /// Gönderilen kayıt sayısını döndürür.
  static Future<int> flushQueue() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    int gonderilen = 0;

    try {
      // İnternet yoksa hiç uğraşma
      if (!await internetKontrol()) return 0;

      final aktifPersonel = await ApiService.currentPersonelId();

      bool baskasinin(Object? sahip) =>
          sahip != null && aktifPersonel != null && (sahip as num).toInt() != aktifPersonel;

      final items = await OfflineQueue.getQueue();
      for (final item in items) {
        if (baskasinin(item['personel_id'])) continue;
        final int isEmriId = (item['is_emri_id'] as num).toInt();
        final double enlem = (item['enlem'] as num).toDouble();
        final double boylam = (item['boylam'] as num).toDouble();
        final String? istekId = item['istek_id'] as String?;
        final String? dosya = item['fotograf_dosya'] as String?;

        // v3: fotoğraf dosya yolundan okunur; eski satırlar base64 taşır.
        String foto = (item['fotograf_base64'] as String?) ?? '';
        if (foto.isEmpty && dosya != null && dosya.isNotEmpty) {
          try {
            foto = base64Encode(await File(dosya).readAsBytes());
          } catch (_) {
            await OfflineQueue.addDeadLetter(
                'gorev', 'save_task', 'Görev #$isEmriId: kanıt fotoğrafı cihazda bulunamadı.');
            await OfflineQueue.removeFromQueue(item['id'] as int);
            continue;
          }
        }

        final sonuc = await gorevGonder(isEmriId, enlem, boylam, foto, istekId);
        if (sonuc == 'retry') break;
        if (sonuc == 'rejected') {
          await OfflineQueue.addDeadLetter('gorev', 'save_task',
              'Görev #$isEmriId tamamlanamadı: sunucu kaydı kabul etmedi (görev kapatılmış/değişmiş olabilir).');
        }
        await OfflineQueue.removeFromQueue(item['id'] as int);
        await OfflineQueue.fotoDosyasiniSil(dosya);
        if (sonuc == 'ok') gonderilen++;
      }

      // Genel istek kuyruğu (arıza bildirimi, masraf vb. — Kural 3)
      final requests = await OfflineQueue.getRequests();
      for (final req in requests) {
        if (baskasinin(req['personel_id'])) continue;
        final body = jsonDecode(req['body'] as String) as Map<String, dynamic>;
        final endpoint = req['endpoint'] as String;
        final sonuc = await istekGonder(endpoint, body);
        if (sonuc == 'retry') break;
        if (sonuc == 'rejected') {
          final ozet = endpoint == 'add_expense.php'
              ? 'Masraf "${body['kalem_adi'] ?? '-'}" gönderilemedi: sunucu kaydı kabul etmedi.'
              : 'Arıza "${body['baslik'] ?? '-'}" gönderilemedi: sunucu kaydı kabul etmedi.';
          await OfflineQueue.addDeadLetter('istek', endpoint, ozet);
        }
        await OfflineQueue.removeRequest(req['id'] as int);
        await OfflineQueue.fotoDosyasiniSil(
            (body['fotograf_dosya'] ?? body['fis_fotograf_dosya']) as String?);
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
