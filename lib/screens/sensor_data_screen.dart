import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_colors.dart';

/// Must match [esp32_ble_sensors.ino] BLE UUIDs and advertised name.
const String _kDeviceName = 'PotatoScan_ESP32';
final Guid _kServiceGuid = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
final Guid _kCharacteristicGuid = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

bool _bleSupported() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

class SensorDataScreen extends StatefulWidget {
  const SensorDataScreen({super.key});

  @override
  State<SensorDataScreen> createState() => _SensorDataScreenState();
}

class _SensorDataScreenState extends State<SensorDataScreen> {
  String _status = 'Disconnected';
  String? _error;

  double? _temperature;
  double? _humidity;
  int? _soilMoisture;
  DateTime? _lastUpdate;

  BluetoothDevice? _device;
  /// iOS only: last peripheral id for a quick reconnect attempt before scanning.
  String? _lastRemoteId;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  bool _busy = false;

  bool _isOurSensor(ScanResult r) {
    final name = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : r.device.advName;
    if (name == _kDeviceName || name.contains('PotatoScan')) return true;
    return r.advertisementData.serviceUuids.any(
      (u) => u.str128 == _kServiceGuid.str128,
    );
  }

  /// Scans by device name first (no [withServices] filter — unreliable on Android after disconnect).
  Future<ScanResult?> _scanForSensor() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));

    Future<ScanResult?> runPass({
      List<String> withNames = const [],
      List<String> withKeywords = const [],
    }) async {
      ScanResult? picked;
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (_isOurSensor(r)) {
            picked = r;
            FlutterBluePlus.stopScan();
            return;
          }
        }
      });

      try {
        await FlutterBluePlus.startScan(
          withNames: withNames,
          withKeywords: withKeywords,
          timeout: const Duration(seconds: 25),
        );

        await FlutterBluePlus.isScanning
            .where((s) => !s)
            .first
            .timeout(const Duration(seconds: 30));

        if (picked != null) return picked;
        for (final r in FlutterBluePlus.lastScanResults) {
          if (_isOurSensor(r)) return r;
        }
        return null;
      } finally {
        await sub.cancel();
        if (FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.stopScan();
        }
      }
    }

    var match = await runPass(withNames: [_kDeviceName]);
    if (match != null) return match;

    if (defaultTargetPlatform == TargetPlatform.android) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      match = await runPass(withKeywords: ['PotatoScan']);
      if (match != null) return match;
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    return runPass();
  }

  @override
  void dispose() {
    _valueSub?.cancel();
    _connectionSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  Future<bool> _ensureBlePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    var scan = await Permission.bluetoothScan.request();
    if (!scan.isGranted) return false;
    var connect = await Permission.bluetoothConnect.request();
    if (!connect.isGranted) return false;

    // Legacy Android: BLE scan may require location.
    final loc = await Permission.locationWhenInUse.status;
    if (!loc.isGranted) {
      await Permission.locationWhenInUse.request();
    }
    return true;
  }

  Future<void> _ensureBluetoothOn() async {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        /* user may decline */
      }
    }

    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException('Bluetooth did not turn on'),
        );
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Preparing…';
    });

    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        setState(() {
          _status = 'Unavailable';
          _error = 'Bluetooth LE is not supported on this device.';
        });
        return;
      }

      if (!await _ensureBlePermissions()) {
        setState(() {
          _status = 'Permission needed';
          _error = 'Bluetooth permissions are required to find the sensor.';
        });
        return;
      }

      await _ensureBluetoothOn();

      // Android: always scan again. Cached [BluetoothDevice.fromId] + system "paired" list
      // entries are often stale; the ESP32 must be found via fresh advertisements.
      // iOS: optional fast reconnect from last id (scan is still the fallback below).
      if (_lastRemoteId != null && defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          setState(() => _status = 'Reconnecting…');
          final cached = BluetoothDevice.fromId(_lastRemoteId!);
          await _attachToDevice(cached);
          return;
        } catch (_) {
          _lastRemoteId = null;
        }
      }

      setState(() => _status = 'Scanning…');

      final match = await _scanForSensor();
      if (match == null) {
        setState(() {
          _status = 'Not found';
          _error =
              'No $_kDeviceName found. Power the ESP32 and stay nearby, then retry.';
        });
        return;
      }

      await _attachToDevice(match.device);
    } catch (e) {
      setState(() {
        _status = 'Error';
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachToDevice(BluetoothDevice device) async {
    setState(() => _status = 'Connecting…');

    if (!device.isConnected) {
      await device.connect(timeout: const Duration(seconds: 35));
    }
    await device.discoverServices();

    BluetoothCharacteristic? target;
    for (final s in device.servicesList) {
      if (s.uuid != _kServiceGuid) continue;
      for (final c in s.characteristics) {
        if (c.uuid == _kCharacteristicGuid) {
          target = c;
          break;
        }
      }
      if (target != null) break;
    }

    if (target == null) {
      await device.disconnect();
      setState(() {
        _status = 'Incompatible device';
        _error = 'Could not find the sensor data characteristic.';
      });
      return;
    }

    _valueSub?.cancel();
    _valueSub = target.onValueReceived.listen(_onSensorBytes);
    device.cancelWhenDisconnected(_valueSub!, next: true);

    await target.setNotifyValue(true);

    _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((state) {
      if (!mounted) return;
      if (state == BluetoothConnectionState.disconnected) {
        setState(() {
          _status = 'Disconnected';
          _device = null;
        });
      }
    });
    device.cancelWhenDisconnected(_connectionSub!, next: true);

    setState(() {
      _device = device;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _lastRemoteId = device.remoteId.str;
      }
      _status = 'Receiving data';
    });
  }

  void _onSensorBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final text = utf8.decode(bytes);
      final map = jsonDecode(text) as Map<String, dynamic>;
      final t = map['temperature'];
      final h = map['humidity'];
      final s = map['soilMoisture'];
      setState(() {
        _temperature = t == null ? null : (t as num).toDouble();
        _humidity = h == null ? null : (h as num).toDouble();
        _soilMoisture = s == null ? null : (s as num).round();
        _lastUpdate = DateTime.now();
        _error = null;
      });
    } catch (_) {
      /* ignore malformed payloads */
    }
  }

  Future<void> _disconnect() async {
    _valueSub?.cancel();
    _valueSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;

    final dev = _device;
    _device = null;

    if (dev != null) {
      try {
        await dev.disconnect();
        await dev.connectionState
            .where((s) => s == BluetoothConnectionState.disconnected)
            .first
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        /* stack may already report disconnected */
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      setState(() {
        _status = 'Disconnected';
        _temperature = null;
        _humidity = null;
        _soilMoisture = null;
        _lastUpdate = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_bleSupported()) {
      return Scaffold(
        backgroundColor: AppColors.bgColor,
        appBar: AppBar(
          backgroundColor: AppColors.bgColor,
          title: const Text('Sensor Data'),
          centerTitle: true,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Bluetooth sensors are available on Android and iOS only.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.bgColor,
        title: const Text('Sensor Data'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _status,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.errorRed, fontSize: 14),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy || _device != null ? null : _connect,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: AppColors.textWhite,
                    ),
                    child: Text(_busy ? 'Please wait…' : 'Connect'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _device == null ? null : _disconnect,
                    child: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _metricRow(
                        Icons.thermostat,
                        'Temperature',
                        _temperature == null
                            ? '—'
                            : '${_temperature!.toStringAsFixed(1)} °C',
                      ),
                      const Divider(height: 28),
                      _metricRow(
                        Icons.water_drop,
                        'Humidity',
                        _humidity == null
                            ? '—'
                            : '${_humidity!.toStringAsFixed(1)} %',
                      ),
                      const Divider(height: 28),
                      _metricRow(
                        Icons.grass,
                        'Soil moisture',
                        _soilMoisture == null ? '—' : '$_soilMoisture %',
                      ),
                      const Spacer(),
                      if (_lastUpdate != null)
                        Text(
                          'Last update: ${_lastUpdate!.toLocal().toString().split('.').first}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryGreen, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}
