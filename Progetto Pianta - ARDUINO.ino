#include <Wire.h>
#include <BH1750.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

// =====================
// CONFIG WIFI
// =====================
const char* WIFI_SSID = "SSID";
const char* WIFI_PASS = "PASS";

// =====================
// CONFIG SUPABASE
// =====================
// Esempio: https://abcd1234.supabase.co
const char* SUPABASE_URL = "https://abcd1234.supabase.co";
// Anon public key (Project Settings -> API)
const char* SUPABASE_ANON_KEY = "";
// Nome tabella su Supabase (es: plant_readings)
const char* TABLE_NAME = "readings";

// UUID della pianta (plant_id uuid)
const char* PLANT_ID = "30240b52-5edb-4c3a-a170-044750b2e0";

// =====================
// TIMING CONFIG
// =====================
const unsigned long SEND_EVERY_MINUTES = 60;   // ← CAMBIA QUI (1, 5, 10, ecc.)
const unsigned long SEND_EVERY_MS = SEND_EVERY_MINUTES * 60UL * 1000UL;

// Endpoint REST (Supabase PostgREST)
String supabaseInsertUrl() {
  // /rest/v1/<table>
  return String(SUPABASE_URL) + "/rest/v1/" + TABLE_NAME;
}

// =====================
// SENSORS CONFIG
// =====================
BH1750 lightMeter;

const int SDA_PIN = 21;
const int SCL_PIN = 22;

// Soil sensor AO -> ESP32 ADC pin
const int SOIL_PIN = 34;

// Calibrazione soil (metti i tuoi)
int SOIL_DRY = 3200;  // aria / secco
int SOIL_WET = 1400;  // acqua / molto bagnato

// =====================
// UTILS
// =====================
float readLuxAvg(int samples = 5) {
  float sum = 0;
  for (int i = 0; i < samples; i++) {
    sum += lightMeter.readLightLevel();
    delay(20);
  }
  return sum / samples;
}

int readSoilAvg(int samples = 10) {
  long sum = 0;
  for (int i = 0; i < samples; i++) {
    sum += analogRead(SOIL_PIN);
    delay(10);
  }
  return (int)(sum / samples);
}

int soilPercentFromRaw(int raw) {
  // RAW alto = secco, RAW basso = bagnato (tipico sensori resistivi)
  int pct = map(raw, SOIL_DRY, SOIL_WET, 0, 100);
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return pct;
}

// Rileva “sensore scollegato” (pin floating) con una euristica semplice
bool soilLooksDisconnected(int raw) {
  // Se è proprio fuori scala o instabile spesso è scollegato.
  // Range ADC 12-bit: 0..4095
  return (raw < 50 || raw > 4090);
}

void wifiEnsureConnected() {
  if (WiFi.status() == WL_CONNECTED) return;

  Serial.print("WiFi connecting to ");
  Serial.println(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(300);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("WiFi OK ✅ IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi FAIL ❌ (will retry later)");
  }
}

bool sendToSupabase(float lux, int soilPct) {
  if (WiFi.status() != WL_CONNECTED) return false;

  // WiFiClientSecure: per semplicità setInsecure() (no CA pinning).
  // In produzione: meglio impostare il certificato root.
  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  String url = supabaseInsertUrl();

  // JSON: inseriamo plant_id, moisture, lux
  // created_at lo lasciamo gestire al DB (default now()).
  String payload = String("{") +
    "\"plant_id\":\"" + PLANT_ID + "\"," +
    "\"moisture\":" + String(soilPct) + "," +
    "\"lux\":" + String(lux, 1) +
  "}";

  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", SUPABASE_ANON_KEY);
  http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
  http.addHeader("Prefer", "return=minimal");

  int code = http.POST(payload);
  String resp = http.getString();
  http.end();

  Serial.print("Supabase POST -> HTTP ");
  Serial.println(code);

  if (code >= 200 && code < 300) {
    Serial.println("Supabase OK ✅");
    return true;
  } else {
    Serial.println("Supabase ERROR ❌");
    Serial.println(resp);
    return false;
  }
}

// =====================
// SETUP / LOOP
// =====================
unsigned long lastSend = 0;

void setup() {
  Serial.begin(115200);
  delay(300);

  // ADC
  analogReadResolution(12); // 0..4095

  // I2C + BH1750
  Wire.begin(SDA_PIN, SCL_PIN);

  if (!lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE)) {
    Serial.println("BH1750 NOT FOUND. Check wiring: VCC/GND/SDA(21)/SCL(22).");
    while (true) delay(1000);
  }

  Serial.println("BH1750 OK ✅");
  Serial.println("Starting monitor...");
  Serial.println("Format: LUX=...; SOIL_RAW=...; SOIL_PCT=...; WIFI=...; SUPABASE=...");

  wifiEnsureConnected();
}

void loop() {
  // 1) Read sensors
  float lux = readLuxAvg(5);
  int soilRaw = readSoilAvg(10);

  // Se il sensore non è collegato (pin floating), non spariamo dati finti su Supabase.
  bool soilDisconnected = soilLooksDisconnected(soilRaw);
  int soilPct = soilDisconnected ? -1 : soilPercentFromRaw(soilRaw);

  // 2) Print
  Serial.print("LUX=");
  Serial.print(lux, 1);

  Serial.print("; SOIL_RAW=");
  Serial.print(soilRaw);

  Serial.print("; SOIL_PCT=");
  if (soilDisconnected) Serial.print("NA");
  else Serial.print(soilPct);

  Serial.print("; WIFI=");
  Serial.print(WiFi.status() == WL_CONNECTED ? "OK" : "NO");

  Serial.println();

  // 3) Periodic send
  unsigned long now = millis();
  if (now - lastSend >= SEND_EVERY_MS) {
    lastSend = now;

    wifiEnsureConnected();

    if (!soilDisconnected && WiFi.status() == WL_CONNECTED) {
      bool ok = sendToSupabase(lux, soilPct);
      Serial.print("SUPABASE=");
      Serial.println(ok ? "OK" : "FAIL");
    } else {
      Serial.println("SUPABASE=SKIP (soil disconnected or wifi down)");
    }
  }

  delay(500);
}