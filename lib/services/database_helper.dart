import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('forms_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(
      path, 
      version: 6, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE forms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        date TEXT,
        data TEXT,
        is_synced INTEGER DEFAULT 0,
        is_uploaded INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        form_type TEXT,
        title TEXT,
        date TEXT,
        data TEXT
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      // Clean slate: drop legacy tables if they exist
      await db.execute('DROP TABLE IF EXISTS forms');
      await db.execute('DROP TABLE IF EXISTS drafts');
      await _createDB(db, newVersion);
    } else if (oldVersion < 5) {
      await db.execute('ALTER TABLE forms ADD COLUMN is_synced INTEGER DEFAULT 0');
    } else if (oldVersion < 6) {
      await db.execute('ALTER TABLE forms ADD COLUMN is_uploaded INTEGER DEFAULT 0');
    }
  }

  Future<void> markAsUploaded(int id) async {
    final db = await instance.database;
    await db.update('forms', {'is_uploaded': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> saveDraft(String type, String title, Map<String, dynamic> data, {int? id}) async {
    final db = await instance.database;
    final jsonString = jsonEncode(data);
    final values = {
      'form_type': type,
      'title': title.isEmpty ? type : title,
      'date': DateTime.now().toString().split('.')[0],
      'data': jsonString,
    };

    if (id != null) {
      await db.update('drafts', values, where: 'id = ?', whereArgs: [id]);
      return id;
    } else {
      return await db.insert('drafts', values);
    }
  }

  Future<List<Map<String, dynamic>>> getAllDrafts() async {
    final db = await instance.database;
    final result = await db.query('drafts', orderBy: 'date DESC');
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>?> getDraft(int id) async {
    final db = await instance.database;
    final maps = await db.query('drafts', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final map = Map<String, dynamic>.from(maps.first);
      map['data'] = jsonDecode(map['data'] as String);
      return map;
    }
    return null;
  }

  Future<void> deleteDraft(int id) async {
    final db = await instance.database;
    await db.delete('drafts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllDrafts() async {
    final db = await instance.database;
    await db.delete('drafts');
  }

  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('forms');
    await db.delete('drafts');
  }

  Future<int> insertForm(Map<String, dynamic> data, {bool isSynced = false}) async {
    final db = await instance.database;
    return await db.insert('forms', {
      'type': data['ტიპი'] ?? 'უცნობი',
      'date': data['თარიღი'] ?? DateTime.now().toString().split('.')[0],
      'data': jsonEncode(data),
      'is_synced': isSynced ? 1 : 0,
    });
  }

  Future<void> updateForm(int id, Map<String, dynamic> data, {bool isSynced = false}) async {
    final db = await instance.database;
    await db.update('forms', {
      'type': data['ტიპი'] ?? 'უცნობი',
      'date': data['თარიღი'] ?? DateTime.now().toString().split('.')[0],
      'data': jsonEncode(data),
      'is_synced': isSynced ? 1 : 0,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markAsSynced(int id, {String? cloudId}) async {
    final db = await instance.database;
    if (cloudId != null) {
      // Also update the JSON data to include the cloud ID
      final maps = await db.query('forms', where: 'id = ?', whereArgs: [id]);
      if (maps.isNotEmpty) {
        final row = maps.first;
        final dataMap = Map<String, dynamic>.from(jsonDecode(row['data'] as String));
        dataMap['id'] = cloudId;
        await db.update('forms', {
          'is_synced': 1,
          'data': jsonEncode(dataMap),
        }, where: 'id = ?', whereArgs: [id]);
        return;
      }
    }
    await db.update('forms', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getForm(int id) async {
    final db = await instance.database;
    final maps = await db.query('forms', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final row = maps.first;
      Map<String, dynamic> dataMap;
      if (row['data'] != null) {
        dataMap = Map<String, dynamic>.from(jsonDecode(row['data'] as String));
      } else {
        dataMap = <String, dynamic>{};
      }
      dataMap['db_id'] = row['id'];
      return dataMap;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getAllForms() async {
    final db = await instance.database;
    final result = await db.query('forms', orderBy: 'date DESC');
    return result.map((row) {
      Map<String, dynamic> dataMap;
      if (row['data'] != null) {
        dataMap = Map<String, dynamic>.from(jsonDecode(row['data'] as String));
      } else {
        dataMap = <String, dynamic>{};
        row.forEach((key, value) => dataMap[key] = value?.toString() ?? '');
      }
      dataMap['db_id'] = row['id'];
      dataMap['is_synced'] = row['is_synced'] == 1;
      dataMap['is_uploaded'] = row['is_uploaded'] == 1;
      return dataMap;
    }).toList();
  }

  Future<void> deleteForm(int id) async {
    final db = await instance.database;
    await db.delete('forms', where: 'id = ?', whereArgs: [id]);
  }
}
