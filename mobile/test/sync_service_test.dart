import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:glow_saha/services/offline_queue.dart';
import 'package:glow_saha/services/sync_service.dart';

/// flushQueue'nun kritik sözleşmesini test eder:
/// 'ok' -> silinir ve sayılır; 'rejected' -> silinir ama sayılmaz;
/// 'retry' -> döngü durur, kayıt kuyrukta kalır.
/// Bu mantık bozulursa sahada görevler ya kaybolur ya kuyruk sonsuza dek tıkanır.
///
/// Supabase geçişinden sonra gönderim ApiService.saveTask/postQueued yerine
/// SyncService'in test dikişleri (gorevGonder/istekGonder) üzerinden sahtelenir;
/// sözleşme ('ok'|'rejected'|'retry') aynıdır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late List<String> yanitSirasi; // sahte gönderimin sırayla dönecegi sonuçlar
  late int istekSayisi; // sahteye kaç çağrı geldi

  Future<String> sahteSonuc() async {
    istekSayisi++;
    return yanitSirasi.isNotEmpty ? yanitSirasi.removeAt(0) : 'ok';
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'test-token'});
    SyncService.internetKontrol = () async => true;
    SyncService.gorevGonder = (id, lat, lng, foto) => sahteSonuc();
    SyncService.istekGonder = (endpoint, body) => sahteSonuc();

    final db = await OfflineQueue.database;
    await db.delete('task_queue');
    await db.delete('request_queue');

    yanitSirasi = [];
    istekSayisi = 0;
  });

  tearDown(() {
    SyncService.internetKontrol = SyncService.hasInternet;
  });

  test('ok sayılır; rejected silinir ama sayılmaz; kuyruk boşalır', () async {
    await OfflineQueue.addToQueue(1, 41.0, 29.0, 'fotoA'); // rejected
    await OfflineQueue.addToQueue(2, 41.0, 29.0, 'fotoB'); // ok
    await OfflineQueue.addRequest('report_fault.php', {'baslik': 'x'}); // ok

    yanitSirasi = ['rejected', 'ok', 'ok'];

    final gonderilen = await SyncService.flushQueue();

    expect(gonderilen, 2, reason: 'rejected sayılmamalı, iki ok sayılmalı');
    expect(await OfflineQueue.getQueue(), isEmpty,
        reason: 'rejected kayıt kuyruğu tıkamamalı, silinmeli');
    expect(await OfflineQueue.getRequests(), isEmpty);
  });

  test('retry döngüyü durdurur, kayıtlar kuyrukta kalır', () async {
    await OfflineQueue.addToQueue(1, 41.0, 29.0, 'fotoA'); // retry -> dur
    await OfflineQueue.addToQueue(2, 41.0, 29.0, 'fotoB'); // hiç denenmemeli

    yanitSirasi = ['retry'];

    final gonderilen = await SyncService.flushQueue();

    expect(gonderilen, 0);
    expect((await OfflineQueue.getQueue()).length, 2,
        reason: 'geçici hatada hiçbir kayıt silinmemeli');
    expect(istekSayisi, 1, reason: 'retry sonrası kalanlar denenmemeli');
  });

  test('görev kuyruğu retry olsa da istek kuyruğu ayrıca denenir', () async {
    await OfflineQueue.addToQueue(1, 41.0, 29.0, 'fotoA'); // retry
    await OfflineQueue.addRequest('report_fault.php', {'baslik': 'x'}); // ok

    yanitSirasi = ['retry', 'ok'];

    final gonderilen = await SyncService.flushQueue();

    expect(gonderilen, 1);
    expect((await OfflineQueue.getQueue()).length, 1);
    expect(await OfflineQueue.getRequests(), isEmpty);
  });

  test('internet yoksa hiç gönderim denenmez', () async {
    SyncService.internetKontrol = () async => false;
    await OfflineQueue.addToQueue(1, 41.0, 29.0, 'fotoA');

    expect(await SyncService.flushQueue(), 0);
    expect((await OfflineQueue.getQueue()).length, 1);
    expect(istekSayisi, 0, reason: 'gönderim hiç denenmemeli');
  });
}
