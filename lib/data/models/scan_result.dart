class ScanResult {
  final int? resultId;
  final int imageId;
  final String diseaseLabel;
  final double confidence;
  final DateTime createdAt;

  ScanResult({
    this.resultId,
    required this.imageId,
    required this.diseaseLabel,
    required this.confidence,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'result_id': resultId,
      'image_id': imageId,
      'disease_label': diseaseLabel,
      'confidence': confidence,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ScanResult.fromMap(Map<String, dynamic> map) {
    return ScanResult(
      resultId: map['result_id'],
      imageId: map['image_id'],
      diseaseLabel: map['disease_label'],
      confidence: map['confidence'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
