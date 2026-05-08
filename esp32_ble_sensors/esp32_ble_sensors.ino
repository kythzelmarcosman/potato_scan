#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <DHT.h>
#include <WiFi.h>
#include <WebServer.h>
#include <EEPROM.h>

// BLE UUIDs (must match Flutter app)
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CONFIG_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a9"

// EEPROM Storage
#define EEPROM_SIZE 512
#define SSID_ADDR 0
#define SSID_LEN 32
#define PASSWORD_ADDR (SSID_ADDR + SSID_LEN)
#define PASSWORD_LEN 64

char wifiSSID[SSID_LEN] = "";
char wifiPassword[PASSWORD_LEN] = "";

#define DHTPIN 4
#define DHTTYPE DHT22
#define SOIL_PIN 34

static const unsigned long kDhtIntervalMs = 2000;
static const unsigned long kSoilIntervalMs = 500;
static const unsigned long kNotifyIntervalMs = 2000;

DHT dht(DHTPIN, DHTTYPE);
BLECharacteristic *pCharacteristic;
WebServer server(80);
bool deviceConnected = false;
bool wifiReady = false;

float gHumidity = NAN;
float gTemperature = NAN;
int gSoilMoisturePercent = 0;

unsigned long lastDhtMs = 0;
unsigned long lastSoilMs = 0;
unsigned long lastNotifyMs = 0;
unsigned long lastAdvKickMs = 0;

volatile bool gPendingAdvRestart = false;

static void restartAdvertising() {
  delay(200);
  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  pAdv->stop();
  delay(100);
  pAdv->start();
  BLEDevice::startAdvertising();
}

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    deviceConnected = true;
  }
  void onDisconnect(BLEServer *pServer) {
    deviceConnected = false;
    gPendingAdvRestart = true;
  }
};

static void readSoilMoisture() {
  int soilMoistureRaw = analogRead(SOIL_PIN);
  int pct = map(soilMoistureRaw, 4095, 0, 0, 100);
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  gSoilMoisturePercent = pct;
}

static String buildJsonPayload() {
  String json = "{";
  json += "\"temperature\":";
  json += isnan(gTemperature) ? "null" : String(gTemperature, 2);
  json += ",\"humidity\":";
  json += isnan(gHumidity) ? "null" : String(gHumidity, 2);
  json += ",\"soilMoisture\":";
  json += String(gSoilMoisturePercent);
  json += "}";
  return json;
}

static void loadWifiCredentials() {
  EEPROM.readString(SSID_ADDR, wifiSSID, SSID_LEN);
  EEPROM.readString(PASSWORD_ADDR, wifiPassword, PASSWORD_LEN);
}

static void saveWifiCredentials(const char *ssid, const char *password) {
  strncpy(wifiSSID, ssid, SSID_LEN - 1);
  wifiSSID[SSID_LEN - 1] = '\0';
  strncpy(wifiPassword, password, PASSWORD_LEN - 1);
  wifiPassword[PASSWORD_LEN - 1] = '\0';
  EEPROM.writeString(SSID_ADDR, wifiSSID);
  EEPROM.writeString(PASSWORD_ADDR, wifiPassword);
  EEPROM.commit();
}

// Forward declaration so BLE callback can call it
static void setupWifiAndServer();

class ConfigCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String value = String((char *)pCharacteristic->getData());
    if (value.length() > 0) {
      int colonIndex = value.indexOf(':');
      if (colonIndex > 0) {
        String ssid = value.substring(0, colonIndex);
        String password = value.substring(colonIndex + 1);
        saveWifiCredentials(ssid.c_str(), password.c_str());

        // *** KEY FIX: connect to WiFi right after receiving credentials ***
        Serial.println("WiFi credentials received via BLE, connecting...");
        setupWifiAndServer();
      }
    }
  }
};

static void setupWifiAndServer() {
  if (strlen(wifiSSID) == 0) {
    Serial.println("No WiFi credentials saved!");
    wifiReady = false;
    return;
  }

  Serial.print("Connecting to: ");
  Serial.println(wifiSSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSSID, wifiPassword);

  int attempts = 0;
  const int maxAttempts = 40;
  while (WiFi.status() != WL_CONNECTED && attempts < maxAttempts) {
    delay(400);
    Serial.print(".");
    attempts++;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    wifiReady = true;
    Serial.print("Connected! IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi connection FAILED!");
    wifiReady = false;
    return;
  }

  server.on("/sensor", HTTP_GET, []() {
    server.send(200, "application/json", buildJsonPayload());
  });
  server.on("/health", HTTP_GET, []() {
    server.send(200, "application/json", "{\"ok\":true}");
  });
  server.begin();
  Serial.println("HTTP server started.");
}

void setup() {
  Serial.begin(115200);
  EEPROM.begin(EEPROM_SIZE);
  dht.begin();

  loadWifiCredentials();

  BLEDevice::init("PotatoScan_ESP32");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pConfigChar = pService->createCharacteristic(
      CONFIG_CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_WRITE);
  pConfigChar->setCallbacks(new ConfigCharacteristicCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  pAdvertising->setMinInterval(32);
  pAdvertising->setMaxInterval(160);
  BLEDevice::startAdvertising();
  Serial.println("BLE advertising started.");

  // Auto-connect on boot if credentials already in EEPROM
  setupWifiAndServer();
}

void loop() {
  const unsigned long now = millis();

  if (gPendingAdvRestart) {
    gPendingAdvRestart = false;
    restartAdvertising();
  }

  if (now - lastSoilMs >= kSoilIntervalMs) {
    lastSoilMs = now;
    readSoilMoisture();
  }

  if (now - lastDhtMs >= kDhtIntervalMs) {
    lastDhtMs = now;
    gHumidity = dht.readHumidity();
    gTemperature = dht.readTemperature();
  }

  if (deviceConnected && (now - lastNotifyMs >= kNotifyIntervalMs)) {
    lastNotifyMs = now;
    String payload = buildJsonPayload();
    pCharacteristic->setValue(payload.c_str());
    pCharacteristic->notify();
  }

  if (wifiReady) {
    server.handleClient();
  }

  if (!deviceConnected && (now - lastAdvKickMs >= 8000)) {
    lastAdvKickMs = now;
    BLEDevice::startAdvertising();
  }

  delay(10);
}