import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/splash_screen.dart';
import 'services/sync_service.dart';
import 'services/fcm_service.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

// Ön planda gelen bildirimleri göstermek için global messenger anahtarı
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Kayıtlı sunucu IP'sini yükle (giriş ekranından değiştirilebilir; GEÇİCİ çözüm)
  await ApiService.initBaseUrl();

  // Firebase'i başlat ve FCM'i kur (bildirim izni + token kaydı + ön plan bildirimleri)
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  await FcmService.init(scaffoldMessengerKey);

  // İnternet bağlantısını izlemeye başla; bağlantı gelince offline kuyruğu
  // otomatik gönderilecek (Kural 3: Offline-first).
  SyncService.startListening();

  // Local storage'dan tema rengini oku (giriş/yönlendirme kararını Splash verir).
  final prefs = await SharedPreferences.getInstance();
  final themeColor = prefs.getString('theme_color') ?? '#3B82F6'; // Varsayılan Mavi

  runApp(MyApp(
    themeColorHex: themeColor,
  ));
}

class MyApp extends StatelessWidget {
  final String themeColorHex;

  const MyApp({
    Key? key,
    required this.themeColorHex,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glow Saha',
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.parseHex(themeColorHex)),
      home: SplashScreen(themeColorHex: themeColorHex),
    );
  }
}
