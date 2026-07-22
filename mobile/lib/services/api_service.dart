import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Varsayılan sunucu IP'si (LAN). GEÇİCİ: canlıya geçene kadar giriş ekranından
  // değiştirilebilir ve cihaza kaydedilir; böylece ağ (ev/ofis) değişince kod
  // düzenleyip yeniden derlemeye gerek kalmaz.
  // Android Emülatör için: 10.0.2.2
  static const String _defaultServerIp = '192.168.1.116';
  static const String _prefServerIpKey = 'server_ip';
  static String _serverIp = _defaultServerIp;

  // TEK KAYNAK: Tüm API çağrıları bu adresi kullanır (kayıtlı IP'den türetilir).
  static String get baseUrl => 'http://$_serverIp/neseyonetim/backend/api';

  // Giriş ekranında göstermek için mevcut sunucu IP'si.
  static String get serverIp => _serverIp;

  // Uygulama açılışında kayıtlı IP'yi yükler (varsa). main()'de çağrılır.
  static Future<void> initBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitli = prefs.getString(_prefServerIpKey);
    if (kayitli != null && kayitli.trim().isNotEmpty) {
      _serverIp = kayitli.trim();
    }
  }

  // Kullanıcının girdiği sunucu adresini temizleyip kaydeder.
  // "http://192.168.1.5/foo" gibi girişlerden yalnızca host(:port) kısmını alır.
  static Future<void> setServerIp(String girdi) async {
    var ip = girdi.trim();
    if (ip.isEmpty) return;
    ip = ip.replaceAll(RegExp(r'^https?://'), ''); // şema varsa at
    ip = ip.replaceAll(RegExp(r'/.*$'), '');        // yol varsa at (host[:port] kalır)
    if (ip.isEmpty) return;
    _serverIp = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerIpKey, ip);
  }

  // Uygulamanın yürürlükteki sürümü. pubspec.yaml'daki `version` ile aynı tutulmalı.
  // Splash ekranı bunu sunucudaki MIN_APP_VERSION ile karşılaştırır.
  static const String appVersion = '1.0.0';

  // Backend kökü (api klasörü olmadan) — yüklenen dosyalara erişim için.
  static String get _root => baseUrl.endsWith('/api') ? baseUrl.substring(0, baseUrl.length - 4) : baseUrl;

  // DB'de saklı göreli dosya yolundan (örn. uploads/faults/x.jpg) tam URL üretir.
  static String fileUrl(String relativePath) => '$_root/$relativePath';

  // Kayıtlı JWT token'ı döndürür (yoksa null)
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  // Kayıtlı token'ın süresi (exp) geçerli mi? Sunucuya sormadan yerelde bakar;
  // böylece süresi dolmuş token'la Home'a düşüp 401 hatası yaşanmaz (offline'da da çalışır).
  static Future<bool> isTokenValid() async {
    final token = await _getToken();
    if (token == null) return false;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'];
      if (exp is! int) return false;
      // 60 sn tolerans: sınırdaki token'ı geçerli sayma (saat sapmasına karşı).
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 < exp - 60;
    } catch (_) {
      return false;
    }
  }

  // Oturum bilgilerini temizler (tema rengi ve sunucu IP'si korunur).
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('rol');
    await prefs.remove('ad_soyad');
  }

  // Authorization başlığı içeren standart header'ları üretir
  static Future<Map<String, String>> _authHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Giriş Yap
  static Future<Map<String, dynamic>> login(String firmaKodu, String telefon, String sifre) async {
    final url = Uri.parse('$baseUrl/login.php');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firma_kodu': firmaKodu,
          'telefon': telefon,
          'sifre': sifre,
        }),
      );

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (e) {
        if (response.statusCode == 404) {
          return {'success': false, 'message': 'Sunucu bulunamadı (404). Lütfen Sunucu (IP) adresini kontrol edin. (Örn: XAMPP htdocs dizini veya Port)'};
        }
        return {'success': false, 'message': 'Sunucudan geçersiz yanıt (HTML) alındı. IP adresi yanlış olabilir.'};
      }

      if (response.statusCode == 200) {
        // Beklenmeyen yanıt (token yok/bozuk) çökmesin diye doğrula.
        if (data is! Map || data['token'] is! String) {
          return {'success': false, 'message': 'Sunucudan beklenmeyen yanıt alındı (token eksik).'};
        }
        // Token ve Tema rengini kaydet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', data['token']);

        // Rol ve ad (arıza/masraf gibi role bağlı ekranlar için)
        final rol = data['kullanici']?['rol'];
        if (rol != null) await prefs.setString('rol', rol);
        final adSoyad = data['kullanici']?['ad_soyad'];
        if (adSoyad != null) await prefs.setString('ad_soyad', adSoyad);

        final hexColor = data['firma']?['tema_rengi'];
        if (hexColor != null) {
          await prefs.setString('theme_color', hexColor);
        }

        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Giriş başarısız.'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Sunucu bağlantı hatası: $e'};
    }
  }

  // Sürüm kontrolü (splash). Kimlik doğrulama gerektirmez.
  // Dönüş: { ok: bool, guncellemeZorunlu: bool, storeUrl: String, mesaj: String }
  // ok=false ise (internet/sunucu yok) çağıran taraf engellememeli; akışa devam etmeli (offline-first).
  static Future<Map<String, dynamic>> checkVersion() async {
    final url = Uri.parse('$baseUrl/version.php?v=$appVersion');
    try {
      final response = await http
          .get(url)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'ok': true,
          'guncellemeZorunlu': data['guncelleme_zorunlu'] == true,
          'storeUrl': data['store_url'] ?? '',
          'mesaj': data['mesaj'] ?? '',
        };
      }
      return {'ok': false};
    } catch (e) {
      // Ağ/sunucu hatası: kullanıcıyı engelleme.
      return {'ok': false};
    }
  }

  // Görevleri Getir
  static Future<Map<String, dynamic>> getTasks() async {
    final url = Uri.parse('$baseUrl/get_tasks.php');
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'Oturum süresi dolmuş.'};

    try {
      final response = await http.get(url, headers: await _authHeaders());

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'tasks': data['data']};
      } else {
        return {
          'success': false,
          'message': data['message'],
          // 401: token geçersiz/süresi dolmuş → çağıran taraf login'e yönlendirir.
          'sessionExpired': response.statusCode == 401,
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Görevi tamamla (kapanış: konum + filigranlı fotoğraf).
  // Dönüş: 'ok' (kaydedildi), 'rejected' (sunucu kalıcı olarak reddetti; tekrar denemek
  // anlamsız — ör. görev zaten kapatılmış), 'retry' (ağ/oturum/sunucu geçici hatası).
  // Bu ayrım offline kuyruğun tek bir "ölü" kayıt yüzünden sonsuza dek tıkanmasını önler.
  static Future<String> saveTask(int isEmriId, double lat, double lng, String base64Image) async {
    return postQueued('save_task.php', {
      'is_emri_id': isEmriId,
      'tamamlanma_enlem': lat,
      'tamamlanma_boylam': lng,
      'kapanis_fotograf_url': base64Image,
    });
  }

  // Kuyruklanabilir genel POST. Dönüş: 'ok' | 'rejected' | 'retry' (saveTask ile aynı sözleşme).
  static Future<String> postQueued(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) return 'ok';
      // 401: oturum sorunu — kullanıcı tekrar giriş yapınca gönderilebilir.
      if (response.statusCode == 401) return 'retry';
      if (response.statusCode >= 400 && response.statusCode < 500) return 'rejected';
      return 'retry';
    } catch (_) {
      return 'retry';
    }
  }

  // Kayıtlı kullanıcı rolünü döndürür (yonetici/temizlik/teknik) — yoksa null.
  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('rol');
  }

  // Firmadaki tesisleri getirir (arıza bildirimi için). Hata durumunda null döner
  // (boş liste ile karışmasın; çağıran taraf kullanıcıya hata gösterebilsin).
  static Future<List<dynamic>?> getSites() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/get_sites.php'), headers: await _authHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['data'] ?? [];
      }
    } catch (_) {}
    return null;
  }

  // FCM cihaz token'ını backend'e kaydeder (giriş yapılmış olmalı).
  static Future<void> saveFcmToken(String fcmToken) async {
    final t = await _getToken();
    if (t == null) return; // Oturum yoksa kaydetme
    try {
      await http.post(
        Uri.parse('$baseUrl/save_fcm_token.php'),
        headers: await _authHeaders(),
        body: jsonEncode({'fcm_token': fcmToken}),
      );
    } catch (_) {
      // Sessizce yut
    }
  }

  // Çıkışta: bu personelin FCM token'ını backend'den siler.
  static Future<void> clearFcmToken() async {
    final t = await _getToken();
    if (t == null) return;
    try {
      await http.post(
        Uri.parse('$baseUrl/clear_fcm_token.php'),
        headers: await _authHeaders(),
      );
    } catch (_) {
      // Sessizce yut
    }
  }

  // Görevi başlat (durum: bekliyor -> devam_ediyor). yontem: 'qr' veya 'konum'.
  // 'konum' yönteminde sunucu da mesafeyi doğrular; bu yüzden koordinatlar gönderilir.
  static Future<Map<String, dynamic>> startTask(int isEmriId, String yontem,
      {String? qrDeger, double? enlem, double? boylam}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/start_task.php'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'is_emri_id': isEmriId,
          'yontem': yontem,
          if (qrDeger != null) 'qr_deger': qrDeger,
          if (enlem != null) 'enlem': enlem,
          if (boylam != null) 'boylam': boylam,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Görev başlatıldı.'};
      }
      return {'success': false, 'message': data['message'] ?? 'Görev başlatılamadı.'};
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Checklist maddesini (alt görev) yapıldı/yapılmadı olarak işaretle.
  // Başarılıysa true döner; ağ/sunucu hatasında false (çağıran taraf eski duruma döner).
  static Future<bool> updateSubtask(int altGorevId, bool yapildi) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_subtask.php'),
        headers: await _authHeaders(),
        body: jsonEncode({'alt_gorev_id': altGorevId, 'yapildi': yapildi}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Teknik personele atanmış açık arızaları getirir. Hata durumunda null döner
  // (boş liste = gerçekten arıza yok; null = yüklenemedi).
  static Future<List<dynamic>?> getFaults() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/get_faults.php'), headers: await _authHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['data'] ?? [];
      }
    } catch (_) {}
    return null;
  }

  // Arıza durumunu güncelle. durum: 'cozuldu' | 'bekliyor' | 'dis_destek'.
  // 'cozuldu' için cozumFotograf (base64) zorunludur.
  static Future<Map<String, dynamic>> updateFault(int arizaId, String durum, {String? not, String? cozumFotograf}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_fault.php'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'ariza_id': arizaId,
          'durum': durum,
          if (not != null && not.isNotEmpty) 'not': not,
          if (cozumFotograf != null) 'cozum_fotograf': cozumFotograf,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Arıza güncellendi.'};
      }
      return {'success': false, 'message': data['message'] ?? 'İşlem başarısız.'};
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }
}
