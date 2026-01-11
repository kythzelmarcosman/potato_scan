//import 'package:sqflite/sqflite.dart';
import '../models/scan_result.dart';
import 'database_helper.dart';

class ScanResultRepository {
  final dbHelper = DatabaseHelper.instance;

  Future<int> insertResult(ScanResult result) async {
    final db = await dbHelper.database;
    return await db.insert('scan_results', result.toMap());
  }

  Future<List<ScanResult>> getResultsByImageId(int imageId) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'scan_results',
      where: 'image_id = ?',
      whereArgs: [imageId],
      orderBy: 'created_at DESC',
    );

    return maps.map((e) => ScanResult.fromMap(e)).toList();
  }
}
