import '../data/models/sensor_snapshot.dart';

class SensorSessionService {
  SensorSessionService._();
  static final SensorSessionService instance = SensorSessionService._();

  SensorSnapshot? _latest;

  SensorSnapshot? get latest => _latest;

  void update(SensorSnapshot snapshot) {
    _latest = snapshot;
  }

  void clear() {
    _latest = null;
  }
}
