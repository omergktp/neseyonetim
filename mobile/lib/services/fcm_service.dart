import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';

// Uygulama arka planda/kapalıyken gelen mesajları işleyen üst düzey fonksiyon.
// 'notification' yükü Android sistem tepsisinde otomatik gösterilir; burada ek iş gerekmez.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

class FcmService {
  static final FirebaseMessaging _fm = FirebaseMessaging.instance;

  /// Uygulama açılışında bir kez çağrılır: izin ister, token'ı backend'e gönderir,
  /// ön planda gelen bildirimleri SnackBar ile gösterir.
  static Future<void> init(GlobalKey<ScaffoldMessengerState> messengerKey) async {
    // Android 13+ için bildirim izni
    await _fm.requestPermission(alert: true, badge: true, sound: true);

    // Mevcut oturum varsa token'ı kaydet
    await syncToken();

    // Token yenilenirse tekrar kaydet
    _fm.onTokenRefresh.listen((t) => ApiService.saveFcmToken(t));

    // Uygulama ön plandayken gelen bildirim: kullanıcıya SnackBar göster
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n != null) {
        messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('${n.title ?? 'Bildirim'}: ${n.body ?? ''}'),
            backgroundColor: Colors.indigo,
          ),
        );
      }
    });
  }

  /// Çıkışta çağrılır: backend'deki token'ı siler ve cihazdaki token'ı geçersiz kılar
  /// (sonraki kullanıcı için taze token üretilir). prefs.clear()'dan ÖNCE çağrılmalı.
  static Future<void> clearToken() async {
    try {
      await ApiService.clearFcmToken();
      await _fm.deleteToken();
    } catch (_) {
      // Sessizce yut
    }
  }

  /// Giriş yapıldığında veya açılışta cihaz token'ını backend'e (personeller.fcm_token) yazar.
  static Future<void> syncToken() async {
    try {
      final token = await _fm.getToken();
      if (token != null) {
        await ApiService.saveFcmToken(token);
      }
    } catch (_) {
      // Sessizce yut; bir sonraki açılış/yenilemede tekrar denenir.
    }
  }
}
