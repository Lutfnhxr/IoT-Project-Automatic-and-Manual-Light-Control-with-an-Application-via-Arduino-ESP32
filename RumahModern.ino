#include <WiFi.h>
#include <FirebaseESP32.h>
#include <time.h>

// --- KONFIGURASI ---
const char* ssid = "";
const char* password = "";
#define FIREBASE_HOST ""
#define FIREBASE_AUTH ""

#define RELAY_PIN 18 // Sesuaikan ke 18 atau 14 sesuai rangkaian Anda
#define SAKLAR_PIN 21 // Sesuaikan ke 21 atau 18 sesuai rangkaian Anda

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bool lampuStatus = false;
bool scheduleEnable = true;
String startTime = "17:45";
String endTime = "03:30";
bool lastJadwalState = false; 
bool startupCheckDone = false;

// Fungsi Waktu Lengkap (Sesuai Instruksi Sebelumnya)
String getWaktuLengkap() {
  time_t now = time(nullptr);
  struct tm* t = localtime(&now);
  if (!t || t->tm_year < 120) return "Memuat Waktu...";
  const char* hari[] = {"Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"};
  char buf[64];
  sprintf(buf, "%s, %02d/%02d/%04d, %02d.%02d WIB", 
          hari[t->tm_wday], t->tm_mday, t->tm_mon + 1, t->tm_year + 1900, t->tm_hour, t->tm_min);
  return String(buf);
}

void syncFirebase(String msg, String modeApp) {
  Firebase.setBool(fbdo, "/lampu/status", lampuStatus);
  Firebase.setString(fbdo, "/lampu/mode", modeApp);
  Firebase.setString(fbdo, "/lampu/last_event", msg);
  Firebase.setString(fbdo, "/lampu/time", getWaktuLengkap());
  
  FirebaseJson log;
  log.add("event", msg);
  log.add("time", getWaktuLengkap());
  Firebase.pushJSON(fbdo, "/logs", log);
}

void relayAction(bool nyala, String sumber) {
  digitalWrite(RELAY_PIN, nyala ? HIGH : LOW);
  lampuStatus = nyala;
  syncFirebase(nyala ? "Lampu Nyala" : "Lampu Mati", sumber);
  Serial.println("Lampu " + String(nyala ? "ON" : "OFF") + " via " + sumber);
}

// Fungsi cek apakah jam sekarang masuk dalam rentang jadwal
bool isNowInSchedule(int currH, int currM, String start, String end) {
  int curr = currH * 60 + currM;
  int s = start.substring(0, 2).toInt() * 60 + start.substring(3, 5).toInt();
  int e = end.substring(0, 2).toInt() * 60 + end.substring(3, 5).toInt();
  if (s <= e) return (curr >= s && curr < e);
  else return (curr >= s || curr < e); // Lewat tengah malam
}

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(SAKLAR_PIN, INPUT_PULLUP);
  
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  
  configTime(7 * 3600, 0, "pool.ntp.org");
  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
}

void loop() {
  if (Firebase.ready()) {
    time_t now = time(nullptr);
    struct tm* t = localtime(&now);

    // --- 1. LOGIKA AUTO-RECOVERY & PERPINDAHAN JADWAL ---
    if (t->tm_year >= 120) { // Jika waktu NTP sudah sinkron
      bool jadwalSekarang = isNowInSchedule(t->tm_hour, t->tm_min, startTime, endTime);

      // A. Cek sekali saat listrik baru nyala (Auto-recovery)
      if (!startupCheckDone) {
        Serial.println("Listrik Nyala! Cek Jadwal...");
        if (jadwalSekarang) relayAction(true, "AUTO_RECOVERY");
        else relayAction(false, "AUTO_RECOVERY");
        lastJadwalState = jadwalSekarang;
        startupCheckDone = true;
      }

      // B. Cek saat terjadi perubahan menit jadwal (Perpindahan ON ke OFF atau sebaliknya)
      if (jadwalSekarang != lastJadwalState) {
        relayAction(jadwalSekarang, "AUTO_JADWAL");
        lastJadwalState = jadwalSekarang;
      }
    }

    // --- 2. KONTROL SAKLAR FISIK (Selalu Bisa Digunakan) ---
    static bool lastBtn = HIGH;
    bool btn = digitalRead(SAKLAR_PIN);
    if (btn != lastBtn) {
      delay(50); // Debounce
      if (digitalRead(SAKLAR_PIN) == btn) {
        if (btn == LOW) relayAction(!lampuStatus, "MANUAL_SAKLAR");
        lastBtn = btn;
      }
    }

    // --- 3. KONTROL VIA APLIKASI (Remote Command) ---
    if (Firebase.getString(fbdo, "/command/value") && fbdo.stringData() != "NONE") {
      String cmd = fbdo.stringData();
      Firebase.setString(fbdo, "/command/value", "NONE");
      relayAction(cmd == "ON", "APP_REMOTE");
    }

    // --- 4. UPDATE JADWAL DARI FIREBASE (Tiap 1 menit) ---
    static unsigned long lastUpdate = 0;
    if (millis() - lastUpdate > 60000) {
      if (Firebase.get(fbdo, "/schedule/start")) startTime = fbdo.stringData();
      if (Firebase.get(fbdo, "/schedule/end")) endTime = fbdo.stringData();
      lastUpdate = millis();
    }
  }
}