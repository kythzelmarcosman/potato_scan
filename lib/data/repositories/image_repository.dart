// import 'package:sqflite/sqflite.dart';
import '../models/image_entity.dart';
import 'database_helper.dart';

class ImageRepository {
  final dbHelper = DatabaseHelper.instance;

  Future<int> insertImage(ImageEntity image) async {
    final db = await dbHelper.database;
    return await db.insert('images', image.toMap());
  }

  Future<List<ImageEntity>> getAllImages() async {
    final db = await dbHelper.database;
    final maps = await db.query('images', orderBy: 'captured_at DESC');

    return maps.map((e) => ImageEntity.fromMap(e)).toList();
  }

  Future<ImageEntity?> getImageById(int imageId) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'images',
      where: 'image_id = ?',
      whereArgs: [imageId],
    );

    if (maps.isNotEmpty) {
      return ImageEntity.fromMap(maps.first);
    }
    return null;
  }

  Future<int> deleteImage(int imageId) async {
    final db = await dbHelper.database;
    return await db.delete(
      'images',
      where: 'image_id = ?',
      whereArgs: [imageId],
    );
  }
}
