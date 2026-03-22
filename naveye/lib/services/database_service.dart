import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/person_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('naveye.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE persons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        image_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        embedding TEXT
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE persons ADD COLUMN embedding TEXT');
    }
  }

  Future<Person> insertPerson(Person person) async {
    final db = await database;
    final id = await db.insert('persons', person.toMap());
    return Person(
      id: id,
      name: person.name,
      imagePath: person.imagePath,
      createdAt: person.createdAt,
      embedding: person.embedding,
    );
  }

  Future<void> updateEmbedding(int id, List<double> embedding) async {
    final db = await database;
    // Use the same jsonEncode path as Person.toMap() to keep encoding consistent.
    await db.update(
      'persons',
      {'embedding': jsonEncode(embedding)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Person>> getAllPersons() async {
    final db = await database;
    final result = await db.query('persons', orderBy: 'created_at DESC');
    return result.map((map) => Person.fromMap(map)).toList();
  }

  Future<void> deletePerson(int id) async {
    final db = await database;
    // Fetch the image path first so we can delete the file after DB row is gone
    final rows = await db.query('persons', columns: ['image_path'],
        where: 'id = ?', whereArgs: [id]);
    await db.delete('persons', where: 'id = ?', whereArgs: [id]);
    // Delete the photo file — prevents storage leak on repeated add/delete
    if (rows.isNotEmpty) {
      final path = rows.first['image_path'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {} // non-fatal — file might already be gone
      }
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
