import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase istemci yapılandırması.
///
/// Özel giriş korunuyor: `login` Edge Function firma kodu + telefon + şifre
/// doğrulayıp gerçek bir Supabase oturumu (access + refresh token) üretir.
/// Access token SharedPreferences'ta `jwt_token` altında saklanır ve
/// [Supabase.initialize] `accessToken` geri-çağrısıyla PostgREST / Realtime /
/// Storage isteklerine iliştirilir. Böylece GoTrue'nun e-posta/parola akışı
/// hiç kullanılmadan mevcut giriş akışı aynen çalışır ve RLS token'daki
/// firma_id claim'ini okur.
///
/// Oturum tazeleme: `accessToken` geri-çağrısı her istekte token'ın süresine
/// bakar; dolmak üzereyse `refresh_token` ile sessizce yeniler. Yenileme tek
/// uçuşludur (aynı anda gelen istekler aynı yenilemeyi bekler) — GoTrue
/// refresh token'ları döndürümlü (rotation) olduğu için yarış, oturumu
/// geçersiz kılabilirdi.
class SupabaseConfig {
  // Proje bilgileri (Dashboard > Project Settings > API).
  static const String supabaseUrl = 'https://bfkiifbzxwhbviluyzcp.supabase.co';

  // Halka açık istemci anahtarı (publishable). Veri erişimini RLS korur.
  static const String supabaseAnonKey = 'sb_publishable_HdcOSN5v1E4YBoQok996Mg_W1i1xnGx';

  static const String _prefTokenKey = 'jwt_token';
  static const String _prefRefreshKey = 'refresh_token';

  /// main() içinde runApp'ten önce çağrılır.
  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      // Her isteğe geçerli (gerekirse tazelenmiş) token'ı taşır. Token yoksa
      // null döner (anon anahtarla, RLS gereği hiçbir firma verisi görünmez).
      accessToken: () => getValidToken(),
    );
  }

  /// Kısayol: global Supabase istemcisi.
  static SupabaseClient get client => Supabase.instance.client;

  /// Kayıtlı token'ı döndürür; süresi dolmuşsa/dolmak üzereyse önce
  /// refresh_token ile yenilemeyi dener. Yenileme başarısız olsa bile eldeki
  /// token döner (sunucu 401 verirse üst katman zaten ele alır).
  static Future<String?> getValidToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_prefTokenKey);
    if (token == null) return null;
    if (!_suresiDolmakUzere(token)) return token;
    await refreshSession();
    return prefs.getString(_prefTokenKey);
  }

  /// exp claim'ine 120 sn'den az kaldıysa true (bozuk token da true sayılır).
  static bool _suresiDolmakUzere(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'];
      if (exp is! int) return true;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp - 120;
    } catch (_) {
      return true;
    }
  }

  static Future<String>? _refreshUcusta;

  /// Oturumu refresh_token ile yeniler. Sonuç:
  ///   'ok'      -> yeni access token kaydedildi
  ///   'invalid' -> refresh token yok/geçersiz (yeniden giriş gerekir)
  ///   'network' -> sunucuya ulaşılamadı (oturum düşürülmemeli; offline-first)
  static Future<String> refreshSession() {
    return _refreshUcusta ??= _refresh().whenComplete(() => _refreshUcusta = null);
  }

  static Future<String> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_prefRefreshKey);
    if (refreshToken == null || refreshToken.isEmpty) return 'invalid';

    HttpClient? http;
    try {
      http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await http
          .postUrl(Uri.parse('$supabaseUrl/auth/v1/token?grant_type=refresh_token'));
      req.headers.set('apikey', supabaseAnonKey);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({'refresh_token': refreshToken})));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();

      if (res.statusCode == 200) {
        final data = jsonDecode(body);
        if (data is Map && data['access_token'] is String) {
          await prefs.setString(_prefTokenKey, data['access_token']);
          if (data['refresh_token'] is String) {
            await prefs.setString(_prefRefreshKey, data['refresh_token']);
          }
          return 'ok';
        }
        return 'invalid';
      }
      if (res.statusCode >= 400 && res.statusCode < 500) {
        // Refresh token geçersiz/iptal edilmiş: bir daha denemenin anlamı yok.
        await prefs.remove(_prefRefreshKey);
        return 'invalid';
      }
      return 'network';
    } on TimeoutException {
      return 'network';
    } on SocketException {
      return 'network';
    } catch (_) {
      return 'network';
    } finally {
      http?.close(force: true);
    }
  }
}
