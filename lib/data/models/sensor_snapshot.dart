class SensorSnapshot {
  final double? temperature;
  final double? humidity;
  final int? soilMoisture;
  final String source;
  final DateTime capturedAt;

  const SensorSnapshot({
    required this.temperature,
    required this.humidity,
    required this.soilMoisture,
    required this.source,
    required this.capturedAt,
  });
}
