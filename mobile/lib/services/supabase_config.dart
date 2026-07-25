import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase istemci yapılandırması.
///
/// Özel giriş korunuyor: `login` Edge Function firma kodu + telefon + şifre
/// doğrulayıp Supabase-uyumlu bir JWT üretir. Bu JWT SharedPreferences'ta
/// `jwt_token` altında saklanır ve [Supabase.initialize] `accessToken`
/// geri-çağrısıyla PostgREST / Realtime / Storage isteklerine iliştirilir.
/// Böylece GoTrue (e-posta/parola) hiç kullanılmadan, mevcut giriş akışı
/// aynen çalışır ve RLS token'daki firma_id claim'ini okur.
class SupabaseConfig {
  // Proje bilgileri (Dashboard > Project Settings > API).
  static const String supabaseUrl = 'https://bfkiifbzxwhbviluyzcp.supabase.co';

  // TODO: Dashboard > Project Settings > API > "anon public" anahtarını buraya koy.
  static const String supabaseAnonKey = 'SENIN_ANON_KEY';

  static const String _prefTokenKey = 'jwt_token';

  /// main() içinde runApp'ten önce çağrılır.
  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      // Kayıtlı özel JWT'yi her isteğe taşır. Token yoksa null döner
      // (anon anahtarla, RLS gereği hiçbir firma verisi görünmez).
      accessToken: () async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_prefTokenKey);
      },
    );
  }

  /// Kısayol: global Supabase istemcisi.
  static SupabaseClient get client => Supabase.instance.client;
}
