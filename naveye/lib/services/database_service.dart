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
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE persons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        image_path TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<Person> insertPerson(Person person) async {
    final db = await database;
    final id = await db.insert('persons', person.toMap());
    return Person(id: id, name: person.name, imagePath: person.imagePath, createdAt: person.createdAt);
  }

  Future<List<Person>> getAllPersons() async {
    final db = await database;
    final result = await db.query('persons', orderBy: 'created_at DESC');
    return result.map((map) => Person.fromMap(map)).toList();
  }

  Future<void> deletePerson(int id) async {
    final db = await database;
    await db.delete('persons', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
