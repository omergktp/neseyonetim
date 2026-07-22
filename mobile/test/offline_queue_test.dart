import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:glow_saha/services/offline_queue.dart';

void main() {
  // sqflite'ı test VM'inde (masaüstü) çalıştır
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    // Her test temiz kuyrukla başlasın
    final db = await OfflineQueue.database;
    await db.delete('task_queue');
    await db.delete('request_queue');
  });

  group('task_queue', () {
    test('ekle/getir/sil akışı', () async {
      await OfflineQueue.addToQueue(1, 41.0, 29.0, 'foto1');
      final kuyruk = await OfflineQueue.getQueue();
      expect(kuyruk.length, 1);
      expect(kuyruk.first['is_emri_id'], 1);

      await OfflineQueue.removeFromQueue(kuyruk.first['id'] as int);
      expect(await OfflineQueue.getQueue(), isEmpty);
    });

    test('aynı iş emri için mükerrer kayıt oluşmaz (çift dokunuş koruması)', () async {
      await OfflineQueue.addToQueue(7, 41.0, 29.0, 'ilk-foto');
      await OfflineQueue.addToQueue(7, 41.1, 29.1, 'ikinci-foto');
      final kuyruk = await OfflineQueue.getQueue();
      expect(kuyruk.length, 1);
      // Son kayıt geçerli olmalı (üzerine yazma)
      expect(kuyruk.first['fotograf_base64'], 'ikinci-foto');
    });

    test('farklı iş emirleri ayrı kayıtlardır', () async {
      await OfflineQueue.addToQueue(1, 0, 0, 'a');
      await OfflineQueue.addToQueue(2, 0, 0, 'b');
      expect((await OfflineQueue.getQueue()).length, 2);
    });
  });

  group('request_queue (arıza/masraf)', () {
    test('ekle/getir/sil akışı', () async {
      await OfflineQueue.addRequest('report_fault.php', {'site_id': 3, 'baslik': 'Test arıza'});
      final istekler = await OfflineQueue.getRequests();
      expect(istekler.length, 1);
      expect(istekler.first['endpoint'], 'report_fault.php');

      await OfflineQueue.removeRequest(istekler.first['id'] as int);
      expect(await OfflineQueue.getRequests(), isEmpty);
    });
  });
}
