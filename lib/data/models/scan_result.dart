class ScanResult {
  final int? resultId;
  final int imageId;
  final String diseaseLabel;
  final double confidence;
  final DateTime createdAt;
  final double? temperature;
  final double? humidity;
  final int? soilMoisture;
  final String? sensorSource;
  final bool isSynced;
  final DateTime? syncedAt;
  final String? syncError;

  ScanResult({
    this.resultId,
    required this.imageId,
    required this.diseaseLabel,
    required this.confidence,
    required this.createdAt,
    this.temperature,
    this.humidity,
    this.soilMoisture,
    this.sensorSource,
    this.isSynced = false,
    this.syncedAt,
    this.syncError,
  });

  Map<String, dynamic> toMap() {
    return {
      'result_id': resultId,
      'image_id': imageId,
      'disease_label': diseaseLabel,
      'confidence': confidence,
      'created_at': createdAt.toIso8601String(),
      'temperature': temperature,
      'humidity': humidity,
      'soil_moisture': soilMoisture,
      'sensor_source': sensorSource,
      'is_synced': isSynced ? 1 : 0,
      'synced_at': syncedAt?.toIso8601String(),
      'sync_error': syncError,
    };
  }

  factory ScanResult.fromMap(Map<String, dynamic> map) {
    return ScanResult(
      resultId: map['result_id'],
      imageId: map['image_id'],
      diseaseLabel: map['disease_label'],
      confidence: (map['confidence'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at']),
      temperature: map['temperature'] == null
          ? null
          : (map['temperature'] as num).toDouble(),
      humidity: map['humidity'] == null
          ? null
          : (map['humidity'] as num).toDouble(),
      soilMoisture: map['soil_moisture'],
      sensorSource: map['sensor_source'],
      isSynced: (map['is_synced'] ?? 0) == 1,
      syncedAt: map['synced_at'] == null
          ? null
          : DateTime.parse(map['synced_at']),
      syncError: map['sync_error'],
    );
  }
}
