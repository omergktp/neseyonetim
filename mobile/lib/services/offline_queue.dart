import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Offline-first kuyruk (Kural 3).
///
/// v3 şeması:
///  * Fotoğraflar artık base64 yerine cihazdaki DOSYA YOLU olarak saklanır
///    (satır başına 1-2 MB base64 → CursorWindow/OOM riski ve DB şişmesi
///    kalkar). Eski satırlardaki fotograf_base64 geriye dönük çalışır.
///  * istek_id: sunucu tarafı idempotency anahtarı (mükerrer kayıt önlenir).
///  * personel_id: kayıt sahibi — çıkış/yeniden girişte kuyruk başka
///    kullanıcının kimliğiyle GÖNDERİLMEZ.
///  * dead_letter: sunucunun kalıcı reddettiği kayıtlar sessizce silinmek
///    yerine buraya taşınır ve kullanıcıya gösterilir.
class OfflineQueue {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'glow_saha_queue.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE task_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            is_emri_id INTEGER,
            enlem REAL,
            boylam REAL,
            fotograf_base64 TEXT,
            fotograf_dosya TEXT,
            istek_id TEXT,
            personel_id INTEGER,
            eklenme_tarihi TEXT
          )
        ''');
        await db.execute(_requestQueueSql);
        await db.execute(_deadLetterSql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v2: arıza bildirimi / masraf gibi diğer istekler için genel kuyruk (Kural 3).
        if (oldVersion < 2) {
          await db.execute(_requestQueueSql);
        }
        // v3: dosya yolu + idempotency + sahiplik + dead-letter.
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE task_queue ADD COLUMN fotograf_dosya TEXT');
          await db.execute('ALTER TABLE task_queue ADD COLUMN istek_id TEXT');
          await db.execute('ALTER TABLE task_queue ADD COLUMN personel_id INTEGER');
          await db.execute('ALTER TABLE request_queue ADD COLUMN istek_id TEXT');
          await db.execute('ALTER TABLE request_queue ADD COLUMN personel_id INTEGER');
          await db.execute(_deadLetterSql);
        }
      },
    );
  }

  static const _requestQueueSql = '''
    CREATE TABLE request_queue(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      endpoint TEXT,
      body TEXT,
      istek_id TEXT,
      personel_id INTEGER,
      eklenme_tarihi TEXT
    )
  ''';

  static const _deadLetterSql = '''
    CREATE TABLE dead_letter(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tur TEXT,
      endpoint TEXT,
      ozet TEXT,
      eklenme_tarihi TEXT
    )
  ''';

  /// Çekilen fotoğrafı kalıcı kuyruk klasörüne kopyalar (kamera cache'i
  /// işletim sistemi tarafından temizlenebilir). Başarısızsa null döner.
  static Future<String?> fotoyuKaliciKopyala(String kaynakYol, String istekId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final klasor = Directory('${dir.path}/kuyruk_foto');
      await klasor.create(recursive: true);
      final hedef = '${klasor.path}/$istekId.jpg';
      await File(kaynakYol).copy(hedef);
      return hedef;
    } catch (_) {
      return null;
    }
  }

  /// Kuyruk fotoğraf dosyasını sessizce siler (gönderim bitince).
  static Future<void> fotoDosyasiniSil(String? yol) async {
    if (yol == null || yol.isEmpty) return;
    try {
      final f = File(yol);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // İnternet yoksa görevi yerel veritabanına ekle.
  // Aynı iş emri için eski kayıt varsa üzerine yazılır (çift dokunuşta mükerrer olmasın).
  static Future<void> addToQueue(int isEmriId, double enlem, double boylam, String fotografBase64,
      {String? istekId, int? personelId, String? fotografDosya}) async {
    final db = await database;
    // Üzerine yazarken eski kaydın fotoğraf dosyası öksüz kalmasın.
    final eski = await db.query('task_queue', where: 'is_emri_id = ?', whereArgs: [isEmriId]);
    for (final e in eski) {
      await fotoDosyasiniSil(e['fotograf_dosya'] as String?);
    }
    await db.delete('task_queue', where: 'is_emri_id = ?', whereArgs: [isEmriId]);
    await db.insert('task_queue', {
      'is_emri_id': isEmriId,
      'enlem': enlem,
      'boylam': boylam,
      'fotograf_base64': fotografBase64,
      'fotograf_dosya': fotografDosya,
      'istek_id': istekId,
      'personel_id': personelId,
      'eklenme_tarihi': DateTime.now().toIso8601String(),
    });
  }

  // Kuyruktaki görevleri getir
  static Future<List<Map<String, dynamic>>> getQueue() async {
    final db = await database;
    return await db.query('task_queue', orderBy: 'eklenme_tarihi ASC');
  }

  // Görev başarıyla API'ye iletildiğinde kuyruktan sil
  static Future<void> removeFromQueue(int id) async {
    final db = await database;
    await db.delete('task_queue', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Genel istek kuyruğu (arıza bildirimi, masraf vb. — Kural 3) ----

  static Future<void> addRequest(String endpoint, Map<String, dynamic> body,
      {String? istekId, int? personelId}) async {
    final db = await database;
    await db.insert('request_queue', {
      'endpoint': endpoint,
      'body': jsonEncode(body),
      'istek_id': istekId ?? body['istek_id'] as String?,
      'personel_id': personelId,
      'eklenme_tarihi': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getRequests() async {
    final db = await database;
    return await db.query('request_queue', orderBy: 'eklenme_tarihi ASC');
  }

  static Future<void> removeRequest(int id) async {
    final db = await database;
    await db.delete('request_queue', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Dead-letter: sunucunun kalıcı reddettiği kayıtlar ----

  static Future<void> addDeadLetter(String tur, String endpoint, String ozet) async {
    final db = await database;
    await db.insert('dead_letter', {
      'tur': tur,
      'endpoint': endpoint,
      'ozet': ozet,
      'eklenme_tarihi': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getDeadLetters() async {
    final db = await database;
    return await db.query('dead_letter', orderBy: 'eklenme_tarihi DESC');
  }

  static Future<void> clearDeadLetters() async {
    final db = await database;
    await db.delete('dead_letter');
  }
}
