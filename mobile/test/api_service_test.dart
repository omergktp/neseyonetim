import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blokent/services/api_service.dart';

/// İmzası önemsiz (isTokenValid imza doğrulamaz, yalnızca exp'e bakar) bir JWT üretir.
String sahteJwt({int? exp}) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final payload = <String, dynamic>{'personel_id': 1, if (exp != null) 'exp': exp};
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64(payload)}.imza';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isTokenValid', () {
    final simdi = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    test('token yoksa false', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ApiService.isTokenValid(), false);
    });

    test('geçerli token (1 saat sonrası) true', () async {
      SharedPreferences.setMockInitialValues({'jwt_token': sahteJwt(exp: simdi + 3600)});
      expect(await ApiService.isTokenValid(), true);
    });

    test('süresi dolmuş token false', () async {
      SharedPreferences.setMockInitialValues({'jwt_token': sahteJwt(exp: simdi - 10)});
      expect(await ApiService.isTokenValid(), false);
    });

    test('60 sn tolerans: sınırdaki token geçerli sayılmaz', () async {
      // exp 30 sn sonra: 60 sn tolerans nedeniyle geçersiz kabul edilmeli
      SharedPreferences.setMockInitialValues({'jwt_token': sahteJwt(exp: simdi + 30)});
      expect(await ApiService.isTokenValid(), false);
    });

    test('exp alanı olmayan token false', () async {
      SharedPreferences.setMockInitialValues({'jwt_token': sahteJwt()});
      expect(await ApiService.isTokenValid(), false);
    });

    test('bozuk (JWT olmayan) token false ve çökmez', () async {
      SharedPreferences.setMockInitialValues({'jwt_token': 'bozuk-veri'});
      expect(await ApiService.isTokenValid(), false);
    });
  });

  group('clearSession', () {
    test('oturum anahtarlarını siler, tema korunur', () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'x',
        'rol': 'teknik',
        'ad_soyad': 'Test',
        'theme_color': '#FF0000',
      });
      await ApiService.clearSession();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), null);
      expect(prefs.getString('rol'), null);
      expect(prefs.getString('ad_soyad'), null);
      expect(prefs.getString('theme_color'), '#FF0000');
    });
  });
}
