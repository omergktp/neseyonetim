import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:glow_saha/services/api_service.dart';
import 'package:glow_saha/services/offline_queue.dart';
import 'package:glow_saha/services/sync_service.dart';

/// flushQueue'nun kritik sözleşmesini GERÇEK bir HTTP sunucusuna karşı test eder:
/// 'ok' -> silinir ve sayılır; 'rejected' (4xx) -> silinir ama sayılmaz;
/// 'retry' (5xx/ağ) -> döngü durur, kayıt kuyrukta kalır.
/// Bu mantık bozulursa sahada görevler ya kaybolur ya kuyruk sonsuza dek tıkanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test tüm HTTP isteklerini bloklayan sahte bir HttpClient kurar;
  // bu testler YEREL (127.0.0.1) bir test sunucusu kullandığı için gerçek
  // istemciye ihtiyaç var. Global override'ı kaldırıyoruz.
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late HttpServer server;
  late List<int> yanitSirasi; // sunucunun sırayla dönecegi HTTP kodları

  setUp(() async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'test-token'});
    SyncService.internetKontrol = () async => true;

    final db = await OfflineQueue.database;
    await db.delete('task_queue');
    await db.delete('request_queue');

    yanitSirasi = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final kod = yanitSirasi.isNotEmpty ? yanitSirasi.removeAt(0) : 200;
      req.response.statusCode = kod;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'message': 'test'}));
      await req.response.close();
    });
    await ApiService.setServerIp('127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await server.close(force: true);
    SyncService.internetKontrol = SyncService.hasInternet;
  });

  test('ok sayılır; rejected silinir ama sayılmaz; kuyruk boşalır', () async {
    await OfflineQueue.addToQueue(1, 41.0, 29.0, 'fotoA'); // 400 -> rejected
    await OfflineQueue.addToQueue(2, 41.0, 29.0, 'fotoB'); // 200 -> ok
    await OfflineQueue.addRequest('report_fault.php', {'baslik': 'x'}); // 200 -> ok

    yanitSirasi = [400, 200, 200];

    final gonderilen = await SyncService.flushQueue();

    expect(gonderilen, 2, reason: 'rejected sayılmamalı, iki ok sayılmalı');
    expect(await OfflineQueue.getQueue(), isEmpty,
        reason: 'rejected kayıt kuyruğu tıkamamalı, silinmeli');
    expect(await OfflineQueue.getRequests(), isEmpty);
  });

  test('retry (5xx) döngüyü durdurur, kayıtlar kuyrukta kalır', () async {
    await OfflineQueue.addToQueue(1, 41.0, 29.0, 'fotoA'); // 500 -> retry, dur
    await OfflineQueue.addToQueue(2, 41.0, 29.0, 'fotoB'); // hiç denenmemeli

    yanitSirasi = [500];

    final gonderilen = await SyncService.flushQueue();

    expect(gonderilen, 0);
    expect((await OfflineQueue.getQueue()).length, 2,
        reason: 'geçici hatada hiçbir kayıt silinmemeli');
  });

  test('401 (oturum) retry sayılır: kayıt korunur, tekrar girişten sonra gönderilir', () async {
    await OfflineQueue.addToQueue(1, 41.0, 29.0, 'fotoA');
    yanitSirasi = [401];

    expect(await SyncService.flushQueue(), 0);
    expect((await OfflineQueue.getQueue()).length, 1);
  });

  test('internet yoksa hiç istek atılmaz', () async {
    SyncService.internetKontrol = () async => false;
    await OfflineQueue.addToQueue(1, 41.0, 29.0, 'fotoA');
    yanitSirasi = [200];

    expect(await SyncService.flushQueue(), 0);
    expect((await OfflineQueue.getQueue()).length, 1);
    expect(yanitSirasi.length, 1, reason: 'sunucuya hiç istek gitmemeli');
  });
}
