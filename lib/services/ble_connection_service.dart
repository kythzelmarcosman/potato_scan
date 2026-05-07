import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Manages BLE device connection lifecycle across screen navigation.
///
/// This service persists the connection even when the SensorDataScreen
/// is disposed/navigated away from, allowing seamless reconnection when
/// returning to the screen.
class BleConnectionService {
  BleConnectionService._();
  static final BleConnectionService instance = BleConnectionService._();

  BluetoothDevice? _connectedDevice;

  /// Get the currently connected device (if any).
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// Check if a device is currently connected.
  bool get isConnected => _connectedDevice != null;

  /// Store only the connected device for persistence across navigation.
  /// Subscriptions are NOT stored to avoid using dead/cancelled subscriptions.
  void setDevice(BluetoothDevice device) {
    _connectedDevice = device;
  }

  /// Clear the connection without disconnecting the device.
  /// Used when screen is disposed but we want to keep the connection alive.
  void clearReferences() {
    _connectedDevice = null;
  }

  /// Disconnect the device completely and clean up resources.
  Future<void> disconnect() async {
    final dev = _connectedDevice;
    _connectedDevice = null;

    if (dev != null) {
      try {
        await dev.disconnect();
        await dev.connectionState
            .where((s) => s == BluetoothConnectionState.disconnected)
            .first
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        // Device may already be disconnected
      }
    }
  }
}
