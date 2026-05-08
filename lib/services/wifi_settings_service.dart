import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing WiFi sensor settings.
/// Persists WiFi SSID, password, and other configuration across app sessions.
class WiFiSettingsService {
  WiFiSettingsService._();
  static final WiFiSettingsService instance = WiFiSettingsService._();

  static const String _ssidKey = 'wifi_ssid';
  static const String _passwordKey = 'wifi_password';
  static const String _endpointKey = 'wifi_endpoint';

  /// Default WiFi endpoint for ESP32
  static const String defaultEndpoint = 'http://192.168.4.1/sensor';

  late SharedPreferences _prefs;
  bool _initialized = false;

  /// Initialize the service (must be called before using)
  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  /// Get the stored WiFi SSID
  String getSSID() {
    _ensureInitialized();
    return _prefs.getString(_ssidKey) ?? '';
  }

  /// Set the WiFi SSID
  Future<void> setSSID(String ssid) async {
    _ensureInitialized();
    await _prefs.setString(_ssidKey, ssid);
  }

  /// Get the stored WiFi password
  String getPassword() {
    _ensureInitialized();
    return _prefs.getString(_passwordKey) ?? '';
  }

  /// Set the WiFi password
  Future<void> setPassword(String password) async {
    _ensureInitialized();
    await _prefs.setString(_passwordKey, password);
  }

  /// Get the stored WiFi endpoint URL
  String getEndpoint() {
    _ensureInitialized();
    return _prefs.getString(_endpointKey) ?? defaultEndpoint;
  }

  /// Set the WiFi endpoint URL
  Future<void> setEndpoint(String endpoint) async {
    _ensureInitialized();
    await _prefs.setString(_endpointKey, endpoint);
  }

  /// Reset to default settings
  Future<void> resetToDefaults() async {
    _ensureInitialized();
    await _prefs.remove(_ssidKey);
    await _prefs.remove(_endpointKey);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'WiFiSettingsService not initialized. Call initialize() first.',
      );
    }
  }
}
