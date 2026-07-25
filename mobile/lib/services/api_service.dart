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
  static Future<String> _uploadBase64(String base64Image, String bucket, String subdir) async {
    final firma = await _firmaId();
    if (firma == null) throw const AuthException('Oturum bulunamadı.');
    final raw = base64Image.contains(',') ? base64Image.split(',').last : base64Image;
    final bytes = base64Decode(raw);
    final objectPath = '$firma/$subdir/${_rndName()}';
    await _sb.storage.from(bucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
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
  static Future<String> _rpcQueued(String fn, Map<String, dynamic> params) async {
    try {
      await _sb.rpc(fn, params: params);
      return 'ok';
    } on PostgrestException catch (_) {
      // İş kuralı reddi (PTxxx / 4xx) — tekrar denemek anlamsız.
      return 'rejected';
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
          .select(
              'id,baslik,aciklama,durum,qr_kod,planlanan_baslangic_tarihi, siteler(ad,adres,enlem,boylam), is_emirleri_alt_gorevler(id,gorev_metni,yapildi_mi)')
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
          'qr_kod': r['qr_kod'],
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
          .select('id,ad,adres,enlem,boylam,qr_kod,aktif')
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
  static Future<String> saveTask(int isEmriId, double lat, double lng, String base64Image) async {
    String? path;
    try {
      if (base64Image.isNotEmpty) path = await _uploadBase64(base64Image, _bucketIsEmri, 'tasks');
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

  /// Kuyruklanabilir POST (offline replay). Endpoint adına göre RPC'ye eşlenir;
  /// gömülü base64 fotoğraf önce Storage'a yüklenir. Sözleşme: 'ok'|'rejected'|'retry'.
  static Future<String> postQueued(String endpoint, Map<String, dynamic> body) async {
    try {
      switch (endpoint) {
        case 'report_fault.php':
          String? foto;
          if (body['fotograf_url'] != null) {
            foto = await _uploadBase64(body['fotograf_url'], _bucketAriza, 'faults');
          }
          return _rpcQueued('report_fault', {
            'p_site_id': body['site_id'],
            'p_baslik': body['baslik'],
            'p_aciklama': body['aciklama'],
            'p_fotograf_path': foto,
          });
        case 'add_expense.php':
          final foto = await _uploadBase64(body['fis_fotograf_url'], _bucketMasraf, 'expenses');
          return _rpcQueued('add_expense', {
            'p_is_emri_id': body['is_emri_id'],
            'p_ariza_id': body['ariza_id'],
            'p_kalem_adi': body['kalem_adi'],
            'p_tutar': num.tryParse(body['tutar'].toString()),
            'p_fis_fotograf_path': foto,
          });
        default:
          return 'rejected';
      }
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
