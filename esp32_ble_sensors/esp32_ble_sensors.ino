#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <DHT.h>

// BLE UUIDs (must match Flutter app)
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Sensor pins
#define DHTPIN 4
#define DHTTYPE DHT22
#define SOIL_PIN 34

// DHT22: allow at least ~2 s between reads
static const unsigned long kDhtIntervalMs = 2000;
// Soil: update often (analog read is cheap)
static const unsigned long kSoilIntervalMs = 500;
// Push to phone over BLE
static const unsigned long kNotifyIntervalMs = 2000;

DHT dht(DHTPIN, DHTTYPE);
BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

// Latest readings (updated continuously in loop)
float gHumidity = NAN;
float gTemperature = NAN;
int gSoilMoisturePercent = 0;

unsigned long lastDhtMs = 0;
unsigned long lastSoilMs = 0;
unsigned long lastNotifyMs = 0;
unsigned long lastAdvKickMs = 0;

/// Do not call [delay] inside BLE callbacks — defer to [loop].
volatile bool gPendingAdvRestart = false;

/// Bluedroid often needs stop→start + short waits; run from [loop] only.
static void restartAdvertising() {
  delay(200);
  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  pAdv->stop();
  delay(100);
  pAdv->start();
  BLEDevice::startAdvertising();
  Serial.println("Advertising restarted (discoverable again).");
}

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    deviceConnected = true;
    Serial.println("Client connected.");
  }
  void onDisconnect(BLEServer *pServer) {
    deviceConnected = false;
    Serial.println("Client disconnected — scheduling advertising restart.");
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
  if (isnan(gTemperature)) {
    json += "null";
  } else {
    json += String(gTemperature, 2);
  }
  json += ",\"humidity\":";
  if (isnan(gHumidity)) {
    json += "null";
  } else {
    json += String(gHumidity, 2);
  }
  json += ",\"soilMoisture\":";
  json += String(gSoilMoisturePercent);
  json += "}";
  return json;
}

void setup() {
  Serial.begin(115200);
  dht.begin();

  BLEDevice::init("PotatoScan_ESP32");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);

  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  // 0x06 / 0x12 = suggested conn intervals; keep both setters (library uses last call for max).
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  // Faster advertising when idle helps phones find the device again after disconnect.
  pAdvertising->setMinInterval(32);   // 20 ms (units of 0.625 ms)
  pAdvertising->setMaxInterval(160);    // 100 ms
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising as PotatoScan_ESP32 — sensors run continuously.");
}

void loop() {
  const unsigned long now = millis();

  if (gPendingAdvRestart) {
    gPendingAdvRestart = false;
    restartAdvertising();
  }

  // Continuous soil moisture sampling
  if (now - lastSoilMs >= kSoilIntervalMs) {
    lastSoilMs = now;
    readSoilMoisture();
  }

  // DHT22: respect minimum interval between reads
  if (now - lastDhtMs >= kDhtIntervalMs) {
    lastDhtMs = now;
    gHumidity = dht.readHumidity();
    gTemperature = dht.readTemperature();
    if (isnan(gHumidity) || isnan(gTemperature)) {
      Serial.println("DHT read failed (check wiring / sensor).");
    }
  }

  // Notify connected clients on a steady interval with latest values
  if (deviceConnected && (now - lastNotifyMs >= kNotifyIntervalMs)) {
    lastNotifyMs = now;
    String payload = buildJsonPayload();
    pCharacteristic->setValue(payload.c_str());
    pCharacteristic->notify();
    Serial.println("Notify: " + payload);
  }

  // Safety: if nothing is connected, periodically ensure we are advertising (recover from rare stack glitches).
  if (!deviceConnected && (now - lastAdvKickMs >= 8000)) {
    lastAdvKickMs = now;
    BLEDevice::startAdvertising();
  }

  delay(10);
}
