import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Supabase-native veri katmanı.
///
/// Metod imzaları ve dönüş biçimleri PHP dönemiyle AYNI tutulmuştur; böylece
/// ekran kodları değişmeden çalışır. Fark yalnızca içeride: HTTP+PHP yerine
/// Supabase (Auth Edge Function + PostgREST view + RPC + Storage).
///
/// Fotoğraflar: RPC'ye base64 gönderilmez; önce Storage'a yüklenir ve RPC'ye
/// "bucket/obje_yolu" biçiminde PATH geçilir. Gösterimde liste metodları
/// kısa ömürlü imzalı URL üretip ilgili alanı onunla değiştirir.
class ApiService {
  static SupabaseClient get _sb => SupabaseConfig.client;

  // ---- Bucket'lar ----
  static const String _bucketIsEmri = 'is-emri-fotograf';
  static const String _bucketAriza = 'ariza-fotograf';
  static const String _bucketMasraf = 'masraf-fis';

  static const String appVersion = '1.0.0';

  // -------- Oturum / token --------

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  /// JWT payload'ından bir claim okur (firma_id / personel_id / rol).
  /// GoTrue token'larında özel claim'ler app_metadata altındadır; eski düz
  /// claim'li token'larla geriye dönük uyumlu.
  static Future<String?> _claim(String key) async {
    final token = await _getToken();
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final meta = payload['app_metadata'];
      final v = (meta is Map ? meta[key] : null) ?? payload[key];
      return v?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _firmaId() async => int.tryParse(await _claim('firma_id') ?? '');
  static Future<int?> _personelId() async => int.tryParse(await _claim('personel_id') ?? '');

  /// Oturumdaki personelin id'si (offline kuyruk kayıtlarını sahibine
  /// bağlamak için ekranlardan da erişilir).
  static Future<int?> currentPersonelId() => _personelId();

  /// Basit UUID v4 üretimi (idempotency anahtarı; kripto güvenliği gerekmez,
  /// yalnız benzersizlik yeterli).
  static String uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Kayıtlı token'ın süresi (exp) hâlâ geçerli mi? (offline'da da çalışır)
  static Future<bool> isTokenValid() async {
    final token = await _getToken();
    if (token == null) return false;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'];
      if (exp is! int) return false;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 < exp - 60;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('refresh_token');
    await prefs.remove('rol');
    await prefs.remove('ad_soyad');
    await prefs.remove('firma_ad');
    await prefs.remove('firma_logo_url');
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('rol');
  }

  // -------- Storage yardımcıları --------

  static String _rndName() {
    final r = Random();
    final s = List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${DateTime.now().microsecondsSinceEpoch}_$s.jpg';
  }

  /// base64 görseli Storage'a yükler; DB'de saklanacak "bucket/obje_yolu" döner.
  /// Obje yolu firma_id ile başlar (Storage RLS izolasyonu).
  ///
  /// [sabitAd] verilirse nesne adı deterministik olur ve upsert açılır:
  /// offline kuyruk aynı kaydı tekrar denediğinde AYNI nesnenin üzerine yazar
  /// (öksüz dosya birikmez, mükerrer yükleme olmaz).
  static Future<String> _uploadBase64(String base64Image, String bucket, String subdir,
      {String? sabitAd}) async {
    final firma = await _firmaId();
    if (firma == null) throw const AuthException('Oturum bulunamadı.');
    final raw = base64Image.contains(',') ? base64Image.split(',').last : base64Image;
    final bytes = base64Decode(raw);
    final objectPath = '$firma/$subdir/${sabitAd ?? _rndName()}';
    await _sb.storage.from(bucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: 'image/jpeg', upsert: sabitAd != null),
        );
    return '$bucket/$objectPath';
  }

  /// "bucket/obje_yolu" değerinden kısa ömürlü imzalı görüntüleme URL'i üretir.
  static Future<String?> _signed(String? stored) async {
    if (stored == null || stored.isEmpty) return null;
    final i = stored.indexOf('/');
    if (i <= 0) return null;
    try {
      return await _sb.storage.from(stored.substring(0, i)).createSignedUrl(stored.substring(i + 1), 3600);
    } catch (_) {
      return null;
    }
  }

  // -------- Hata -> kuyruk sözleşmesi ('ok' | 'rejected' | 'retry') --------

  /// RPC'yi çalıştırır; kuyruk sözleşmesine göre sonuç döndürür.
  ///
  /// Sınıflandırma SQLSTATE koduna göre yapılır: yalnız KALICI iş kuralı
  /// redleri (PT4xx ve veri/kısıt/yetki sınıfları) 'rejected' sayılır;
  /// sunucu hatası (PT5xx/5xx), zaman aşımı, bağlantı sınıfları 'retry'dir.
  /// (Eski davranış tüm PostgrestException'ları rejected sayıp offline
  /// kuyrukta sessiz veri kaybına yol açıyordu.)
  static Future<String> _rpcQueued(String fn, Map<String, dynamic> params) async {
    try {
      await _sb.rpc(fn, params: params);
      return 'ok';
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      final kalici = code.startsWith('PT4') ||
          (code.length >= 2 && const ['22', '23', '42'].contains(code.substring(0, 2)));
      return kalici ? 'rejected' : 'retry';
    } on AuthException catch (_) {
      return 'retry'; // oturum sorunu — yeniden giriş sonrası denenebilir
    } on StorageException catch (_) {
      return 'retry';
    } on SocketException catch (_) {
      return 'retry';
    } on TimeoutException catch (_) {
      return 'retry';
    } catch (_) {
      return 'retry';
    }
  }

  /// RPC'yi çalıştırır; {success, message} döndürür (senkron ekranlar için).
  static Future<Map<String, dynamic>> _rpcResult(String fn, Map<String, dynamic> params,
      {String basari = 'İşlem tamamlandı.'}) async {
    try {
      final res = await _sb.rpc(fn, params: params);
      final msg = (res is Map && res['message'] != null) ? res['message'].toString() : basari;
      return {'success': true, 'message': msg, if (res is Map) 'data': res};
    } on PostgrestException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // ======================= GİRİŞ =======================

  static Future<Map<String, dynamic>> login(String firmaKodu, String telefon, String sifre) async {
    try {
      final res = await _sb.functions.invoke('login', body: {
        'firma_kodu': firmaKodu,
        'telefon': telefon,
        'sifre': sifre,
      });
      final data = res.data;
      if (res.status == 200 && data is Map && data['access_token'] is String) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', data['access_token']);
        if (data['refresh_token'] is String) {
          await prefs.setString('refresh_token', data['refresh_token']);
        }
        final rol = data['kullanici']?['rol'];
        if (rol != null) await prefs.setString('rol', rol.toString());
        final adSoyad = data['kullanici']?['ad_soyad'];
        if (adSoyad != null) await prefs.setString('ad_soyad', adSoyad.toString());
        final hexColor = data['firma']?['tema_rengi'];
        if (hexColor != null) await prefs.setString('theme_color', hexColor.toString());
        final firmaAd = data['firma']?['ad'];
        if (firmaAd != null) await prefs.setString('firma_ad', firmaAd.toString());
        // Firma logosu (public URL) — splash/marka alanlarında gösterilir.
        final logoUrl = data['firma']?['logo_url'];
        if (logoUrl is String && logoUrl.isNotEmpty) {
          await prefs.setString('firma_logo_url', logoUrl);
        } else {
          await prefs.remove('firma_logo_url');
        }
        return {'success': true, 'data': data};
      }
      final msg = (data is Map ? data['message'] : null) ?? 'Giriş başarısız.';
      return {'success': false, 'message': msg};
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = (d is Map && d['message'] != null) ? d['message'].toString() : 'Giriş başarısız.';
      return {'success': false, 'message': msg};
    } catch (e) {
      return {'success': false, 'message': 'Sunucu bağlantı hatası: $e'};
    }
  }

  /// Sürüm kontrolü. Supabase-native'de zorunlu güncelleme kapısı yok;
  /// offline-first davranışı korumak için engellemeden geçer.
  static Future<Map<String, dynamic>> checkVersion() async {
    return {'ok': false};
  }

  // ======================= OKUMA =======================

  /// Personelin kendi aktif görevleri (+ checklist + tesis). PHP get_tasks şekli.
  static Future<Map<String, dynamic>> getTasks() async {
    if (await _getToken() == null) return {'success': false, 'message': 'Oturum süresi dolmuş.'};
    try {
      final rows = await _sb
          .from('is_emirleri')
          // qr_kod bilinçli olarak seçilmez: QR değeri istemciye inmez (0011),
          // doğrulama tamamen sunucuda (start_task) yapılır.
          .select(
              'id,baslik,aciklama,durum,planlanan_baslangic_tarihi, siteler(ad,adres,enlem,boylam), is_emirleri_alt_gorevler(id,gorev_metni,yapildi_mi)')
          .inFilter('durum', ['bekliyor', 'devam_ediyor']).order('planlanan_baslangic_tarihi', ascending: true);

      final tasks = (rows as List).map((r) {
        final s = r['siteler'];
        final alt = (r['is_emirleri_alt_gorevler'] as List? ?? [])
            .map((a) => {
                  'id': a['id'],
                  'gorev_metni': a['gorev_metni'],
                  'yapildi_mi': (a['yapildi_mi'] == true) ? 1 : 0, // ekranlar 0/1 bekliyor
                })
            .toList();
        return {
          'id': r['id'],
          'baslik': r['baslik'],
          'aciklama': r['aciklama'],
          'durum': r['durum'],
          'planlanan_baslangic_tarihi': r['planlanan_baslangic_tarihi'],
          'site_adi': s?['ad'],
          'site_adresi': s?['adres'],
          'enlem': s?['enlem'],
          'boylam': s?['boylam'],
          'alt_gorevler': alt,
        };
      }).toList();

      // Bugün tamamlanan (yerel gün başlangıcı)
      final now = DateTime.now();
      final gunBas = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
      final tamam = await _sb
          .from('is_emirleri')
          .select('id')
          .eq('durum', 'tamamlandi')
          .gte('tamamlanma_tarihi', gunBas);

      return {'success': true, 'tasks': tasks, 'bugunTamamlanan': (tamam as List).length};
    } on PostgrestException catch (e) {
      return {'success': false, 'message': e.message, 'sessionExpired': false};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message, 'sessionExpired': true};
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  /// Firmadaki aktif tesisler (arıza bildirimi seçim listesi). Hata -> null.
  static Future<List<dynamic>?> getSites() async {
    try {
      final rows = await _sb
          .from('siteler')
          .select('id,ad,adres,enlem,boylam,aktif')
          .eq('aktif', true)
          .order('ad', ascending: true);
      return rows as List;
    } catch (_) {
      return null;
    }
  }

  /// Teknik personele atanmış açık arızalar. Hata -> null.
  static Future<List<dynamic>?> getFaults() async {
    try {
      final pid = await _personelId();
      if (pid == null) return null;
      final rows = await _sb
          .from('v_ariza')
          .select('*')
          .eq('teknik_personel_id', pid)
          .inFilter('durum', ['acik', 'bekliyor', 'dis_destek']).order('olusturma_tarihi', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      for (final a in list) {
        a['fotograf_url'] = await _signed(a['fotograf_url'] as String?);
        a['cozum_fotograf_url'] = await _signed(a['cozum_fotograf_url'] as String?);
      }
      return list;
    } catch (_) {
      return null;
    }
  }

  // ======================= YAZMA (mobil) =======================

  /// Görevi tamamla. Fotoğraf Storage'a yüklenir; sonra save_task RPC.
  /// [istekId] verilirse fotoğraf deterministik adla (upsert) yüklenir:
  /// offline kuyruk tekrar denediğinde mükerrer nesne oluşmaz.
  static Future<String> saveTask(int isEmriId, double lat, double lng, String base64Image,
      {String? istekId}) async {
    String? path;
    try {
      if (base64Image.isNotEmpty) {
        path = await _uploadBase64(base64Image, _bucketIsEmri, 'tasks',
            sabitAd: istekId != null ? 'q_$istekId.jpg' : null);
      }
    } on SocketException catch (_) {
      return 'retry';
    } on StorageException catch (_) {
      return 'retry';
    } catch (_) {
      return 'retry';
    }
    return _rpcQueued('save_task', {
      'p_is_emri_id': isEmriId,
      'p_enlem': lat,
      'p_boylam': lng,
      'p_kapanis_fotograf_path': path,
    });
  }

  /// Gövdedeki fotoğrafı çözer: [b64Key] base64 içerik ya da [dosyaKey]
  /// cihazdaki dosya yolu olabilir (offline kuyruk artık base64 yerine dosya
  /// yolu saklar — bellek ve DB şişmesini önler).
  static Future<String?> _bodyFoto(Map<String, dynamic> body, String b64Key, String dosyaKey) async {
    final b64 = body[b64Key];
    if (b64 is String && b64.isNotEmpty) return b64;
    final dosya = body[dosyaKey];
    if (dosya is String && dosya.isNotEmpty) {
      return base64Encode(await File(dosya).readAsBytes());
    }
    return null;
  }

  /// Kuyruklanabilir POST (offline replay). Endpoint adına göre RPC'ye eşlenir;
  /// fotoğraf önce Storage'a yüklenir. Sözleşme: 'ok'|'rejected'|'retry'.
  /// body['istek_id'] varsa hem yükleme adı hem RPC idempotency anahtarı olur.
  static Future<String> postQueued(String endpoint, Map<String, dynamic> body) async {
    final istekId = body['istek_id'] as String?;
    try {
      switch (endpoint) {
        case 'report_fault.php':
          String? foto;
          final b64 = await _bodyFoto(body, 'fotograf_url', 'fotograf_dosya');
          if (b64 != null) {
            foto = await _uploadBase64(b64, _bucketAriza, 'faults',
                sabitAd: istekId != null ? 'q_$istekId.jpg' : null);
          }
          return _rpcQueued('report_fault', {
            'p_site_id': body['site_id'],
            'p_baslik': body['baslik'],
            'p_aciklama': body['aciklama'],
            'p_fotograf_path': foto,
            'p_istek_id': istekId,
          });
        case 'add_expense.php':
          final b64 = await _bodyFoto(body, 'fis_fotograf_url', 'fis_fotograf_dosya');
          if (b64 == null) return 'rejected';
          final foto = await _uploadBase64(b64, _bucketMasraf, 'expenses',
              sabitAd: istekId != null ? 'q_$istekId.jpg' : null);
          // Türkçe klavyede ondalık ayracı virgül gelebilir.
          final tutar = num.tryParse(body['tutar'].toString().replaceAll(',', '.'));
          return _rpcQueued('add_expense', {
            'p_is_emri_id': body['is_emri_id'],
            'p_ariza_id': body['ariza_id'],
            'p_kalem_adi': body['kalem_adi'],
            'p_tutar': tutar,
            'p_fis_fotograf_path': foto,
            'p_istek_id': istekId,
          });
        default:
          return 'rejected';
      }
    } on FileSystemException catch (_) {
      return 'rejected'; // kuyruktaki fotoğraf dosyası kaybolmuş — tekrar denemek anlamsız
    } on SocketException catch (_) {
      return 'retry';
    } on StorageException catch (_) {
      return 'retry';
    } on TimeoutException catch (_) {
      return 'retry';
    } catch (_) {
      return 'retry';
    }
  }

  /// Görevi başlat (QR / konum). start_task RPC (konum doğrulaması sunucuda).
  static Future<Map<String, dynamic>> startTask(int isEmriId, String yontem,
      {String? qrDeger, double? enlem, double? boylam}) async {
    return _rpcResult('start_task', {
      'p_is_emri_id': isEmriId,
      'p_yontem': yontem,
      'p_qr_deger': qrDeger,
      'p_enlem': enlem,
      'p_boylam': boylam,
    }, basari: 'Görev başlatıldı.');
  }

  /// Checklist maddesini işaretle. Başarı -> true.
  static Future<bool> updateSubtask(int altGorevId, bool yapildi) async {
    try {
      await _sb.rpc('update_subtask', params: {'p_alt_gorev_id': altGorevId, 'p_yapildi': yapildi});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Arıza durumunu güncelle (teknik). 'cozuldu' için çözüm fotoğrafı zorunlu.
  static Future<Map<String, dynamic>> updateFault(int arizaId, String durum,
      {String? not, String? cozumFotograf}) async {
    String? path;
    if (cozumFotograf != null && cozumFotograf.isNotEmpty) {
      try {
        path = await _uploadBase64(cozumFotograf, _bucketAriza, 'resolutions');
      } catch (e) {
        return {'success': false, 'message': 'Çözüm fotoğrafı yüklenemedi: $e'};
      }
    }
    return _rpcResult('update_fault', {
      'p_ariza_id': arizaId,
      'p_durum': durum,
      'p_not': (not != null && not.isNotEmpty) ? not : null,
      'p_cozum_fotograf_path': path,
    }, basari: 'Arıza güncellendi.');
  }

  // -------- FCM token --------

  static Future<void> saveFcmToken(String fcmToken) async {
    if (await _getToken() == null) return;
    try {
      await _sb.rpc('set_fcm_token', params: {'p_fcm_token': fcmToken});
    } catch (_) {}
  }

  static Future<void> clearFcmToken() async {
    if (await _getToken() == null) return;
    try {
      await _sb.rpc('clear_fcm_token');
    } catch (_) {}
  }

  // ======================= YÖNETİCİ (admin) =======================

  static Future<Map<String, dynamic>?> getAdminDashboard() async {
    try {
      final res = await _sb.rpc('admin_dashboard', params: {'p_site_id': null});
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<dynamic>?> getAdminMasraflar({String? durum}) async {
    try {
      var q = _sb.from('v_masraf').select('*');
      if (durum != null) q = q.eq('durum', durum);
      final rows = await q.order('olusturma_tarihi', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      for (final m in list) {
        m['fis_fatura_fotograf'] = await _signed(m['fis_fatura_fotograf'] as String?);
      }
      return list;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> adminMasrafIslem(int id, String islem) async {
    return _rpcResult('admin_masraf_karar', {'p_id': id, 'p_karar': islem}, basari: 'İşlem tamamlandı.');
  }

  static Future<List<dynamic>?> getAdminArizalar() async {
    try {
      final rows = await _sb.from('v_ariza').select('*').order('olusturma_tarihi', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      for (final a in list) {
        a['fotograf_url'] = await _signed(a['fotograf_url'] as String?);
        a['cozum_fotograf_url'] = await _signed(a['cozum_fotograf_url'] as String?);
      }
      return list;
    } catch (_) {
      return null;
    }
  }
}
