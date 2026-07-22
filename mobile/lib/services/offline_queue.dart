import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE task_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            is_emri_id INTEGER,
            enlem REAL,
            boylam REAL,
            fotograf_base64 TEXT,
            eklenme_tarihi TEXT
          )
        ''');
        await db.execute(_requestQueueSql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v2: arıza bildirimi / masraf gibi diğer istekler için genel kuyruk (Kural 3).
        if (oldVersion < 2) {
          await db.execute(_requestQueueSql);
        }
      },
    );
  }

  static const _requestQueueSql = '''
    CREATE TABLE request_queue(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      endpoint TEXT,
      body TEXT,
      eklenme_tarihi TEXT
    )
  ''';

  // İnternet yoksa görevi yerel veritabanına ekle.
  // Aynı iş emri için eski kayıt varsa üzerine yazılır (çift dokunuşta mükerrer olmasın).
  static Future<void> addToQueue(int isEmriId, double enlem, double boylam, String fotografBase64) async {
    final db = await database;
    await db.delete('task_queue', where: 'is_emri_id = ?', whereArgs: [isEmriId]);
    await db.insert('task_queue', {
      'is_emri_id': isEmriId,
      'enlem': enlem,
      'boylam': boylam,
      'fotograf_base64': fotografBase64,
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

  static Future<void> addRequest(String endpoint, Map<String, dynamic> body) async {
    final db = await database;
    await db.insert('request_queue', {
      'endpoint': endpoint,
      'body': jsonEncode(body),
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
}
