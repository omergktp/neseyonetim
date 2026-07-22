import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../screens/faults_screen.dart';
import '../screens/task_detail_screen.dart';
import '../utils/ui_utils.dart';
import 'api_service.dart';

// Uygulama arka planda/kapalıyken gelen mesajları işleyen üst düzey fonksiyon.
// 'notification' yükü Android sistem tepsisinde otomatik gösterilir; burada ek iş gerekmez.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

class FcmService {
  static final FirebaseMessaging _fm = FirebaseMessaging.instance;

  /// Uygulama açılışında bir kez çağrılır: izin ister, token'ı backend'e gönderir,
  /// ön planda gelen bildirimleri gösterir, bildirime tıklanınca ilgili ekrana götürür.
  static Future<void> init(GlobalKey<ScaffoldMessengerState> messengerKey) async {
    // Android 13+ için bildirim izni
    await _fm.requestPermission(alert: true, badge: true, sound: true);

    // Mevcut oturum varsa token'ı kaydet
    await syncToken();

    // Token yenilenirse tekrar kaydet
    _fm.onTokenRefresh.listen((t) => ApiService.saveFcmToken(t));

    // Uygulama ön plandayken gelen bildirim: "Gör" aksiyonlu SnackBar
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n != null) {
        UiUtils.showSnackBar(
          '${n.title ?? 'Bildirim'}: ${n.body ?? ''}',
          actionLabel: 'Gör',
          onAction: () => openFromMessage(message),
        );
      }
    });

    // Arka plandayken bildirime tıklanıp uygulama öne gelirse
    FirebaseMessaging.onMessageOpenedApp.listen(openFromMessage);

    // Uygulama kapalıyken bildirime tıklanıp açıldıysa: splash/giriş akışının
    // oturmasını bekleyip yönlendir.
    final initial = await _fm.getInitialMessage();
    if (initial != null) {
      Future.delayed(const Duration(seconds: 3), () => openFromMessage(initial));
    }
  }

  /// Bildirimin data yüküne göre ilgili ekranı açar:
  /// tip=ariza -> Arızalarım listesi; is_emri_id varsa -> görev detayı.
  static Future<void> openFromMessage(RemoteMessage message) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    if (message.data['tip'] == 'ariza') {
      nav.push(MaterialPageRoute(builder: (_) => const FaultsScreen()));
      return;
    }

    final idStr = message.data['is_emri_id']?.toString();
    if (idStr == null) return;

    // Görev detayına gitmek için güncel görev kaydını çek.
    final res = await ApiService.getTasks();
    if (res['success'] != true) return;
    final tasks = (res['tasks'] as List?) ?? const [];
    final task = tasks.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['id'].toString() == idStr,
          orElse: () => null,
        );
    if (task != null) {
      nav.push(MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)));
    }
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
