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

  Future<List<ScanResult>> getUnsyncedResults() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'scan_results',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );
    return maps.map((e) => ScanResult.fromMap(e)).toList();
  }

  Future<void> markAsSynced(int resultId) async {
    final db = await dbHelper.database;
    await db.update(
      'scan_results',
      {
        'is_synced': 1,
        'synced_at': DateTime.now().toIso8601String(),
        'sync_error': null,
      },
      where: 'result_id = ?',
      whereArgs: [resultId],
    );
  }

  Future<void> markSyncFailed(int resultId, String error) async {
    final db = await dbHelper.database;
    await db.update(
      'scan_results',
      {
        'is_synced': 0,
        'sync_error': error.length > 250 ? error.substring(0, 250) : error,
      },
      where: 'result_id = ?',
      whereArgs: [resultId],
    );
  }
}
