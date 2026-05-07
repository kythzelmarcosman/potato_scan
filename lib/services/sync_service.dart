import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../data/models/scan_result.dart';
import '../data/repositories/scan_result_repository.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final ScanResultRepository _scanResultRepository = ScanResultRepository();
  Timer? _timer;
  bool _isSyncing = false;

  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const String _tableName = String.fromEnvironment(
    'SUPABASE_SCAN_TABLE',
    defaultValue: 'scan_results',
  );

  bool get isConfigured =>
      _supabaseUrl.trim().isNotEmpty && _supabaseAnonKey.trim().isNotEmpty;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncNow();
    });
    unawaited(syncNow());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> syncNow() async {
    if (_isSyncing || !isConfigured) return;
    _isSyncing = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final hasNetwork = connectivity.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) return;

      final unsynced = await _scanResultRepository.getUnsyncedResults();
      for (final result in unsynced) {
        await _pushResult(result);
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pushResult(ScanResult result) async {
    if (result.resultId == null) return;
    final uri = Uri.parse('$_supabaseUrl/rest/v1/$_tableName');
    try {
      final response = await http.post(
        uri,
        headers: {
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode({
          'local_result_id': result.resultId,
          'image_id': result.imageId,
          'disease_label': result.diseaseLabel,
          'confidence': result.confidence,
          'created_at': result.createdAt.toIso8601String(),
          'temperature': result.temperature,
          'humidity': result.humidity,
          'soil_moisture': result.soilMoisture,
          'sensor_source': result.sensorSource,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _scanResultRepository.markAsSynced(result.resultId!);
      } else {
        await _scanResultRepository.markSyncFailed(
          result.resultId!,
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      await _scanResultRepository.markSyncFailed(
        result.resultId!,
        e.toString(),
      );
    }
  }
}
