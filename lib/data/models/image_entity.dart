class ImageEntity {
  int? imageId;
  String imagePath;
  DateTime capturedAt;

  ImageEntity({
    this.imageId,
    required this.imagePath,
    required this.capturedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'image_id': imageId,
      'image_path': imagePath,
      'captured_at': capturedAt.toIso8601String(),
    };
  }

  factory ImageEntity.fromMap(Map<String, dynamic> map) {
    return ImageEntity(
      imageId: map['image_id'],
      imagePath: map['image_path'],
      capturedAt: DateTime.parse(map['captured_at']),
    );
  }
}
