import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'potato_scanner.db');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE images (
        image_id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        captured_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE scan_results (
        result_id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_id INTEGER NOT NULL,
        disease_label TEXT NOT NULL, 
        confidence REAL NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (image_id) REFERENCES images (image_id)
      )
    ''');

    //   await db.execute('''
    //     CREATE TABLE environmental_data (
    //       env_id INTEGER PRIMARY KEY AUTOINCREMENT,
    //       image_id INTEGER NOT NULL,
    //       temperature REAL,
    //       humidity REAL,
    //       soil_moisture REAL,
    //       rainfall REAL,
    //       recorded_at TEXT NOT NULL,
    //       FOREIGN KEY (image_id) REFERENCES images (image_id)
    //     )
    //   ''');
  }
}
