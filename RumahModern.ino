#include <WiFi.h>
#include <FirebaseESP32.h>
#include <time.h>

/* ===== WIFI & FIREBASE ===== */
const char* ssid = "";
const char* password = "";

#define FIREBASE_HOST ""
#define FIREBASE_AUTH ""

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

/* ===== PIN ===== */
#define RELAY_PIN 18
#define SAKLAR_PIN 21

/* ===== STATE ===== */
bool lampuStatus = false;
bool lastScheduleState = false;

String startTime = "17:45";
String endTime   = "03:30";

/* ===== FUNGSI WAKTU ===== */
String waktuLengkap() {
  time_t now = time(nullptr);
  struct tm* t = localtime(&now);
  if (!t || t->tm_year < 120) return "--";

  const char* hari[] = {"Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu"};

  char buf[64];
  sprintf(buf,"%s, %02d/%02d/%04d %02d:%02d WIB",
          hari[t->tm_wday],
          t->tm_mday,
          t->tm_mon + 1,
          t->tm_year + 1900,
          t->tm_hour,
          t->tm_min);
  return String(buf);
}

/* ===== LOGIKA JADWAL ===== */
bool inSchedule(int h, int m) {
  int now = h * 60 + m;
  int s = startTime.substring(0,2).toInt() * 60 +
          startTime.substring(3,5).toInt();
  int e = endTime.substring(0,2).toInt() * 60 +
          endTime.substring(3,5).toInt();

  if (s <= e) return now >= s && now < e;
  return now >= s || now < e;
}

/* ===== SYNC FIREBASE ===== */
void syncFirebase(String mode) {
  Firebase.setBool(fbdo, "/lampu/status", lampuStatus);
  Firebase.setString(fbdo, "/lampu/mode", mode);
  Firebase.setString(fbdo, "/lampu/time", waktuLengkap());

  FirebaseJson log;
  log.set("event", lampuStatus ? "Light ON" : "Light OFF");
  log.set("mode", mode);
  log.set("time", waktuLengkap());
  Firebase.pushJSON(fbdo, "/logs", log);
}

/* ===== RELAY CONTROL ===== */
void setLamp(bool on, String mode) {
  lampuStatus = on;
  digitalWrite(RELAY_PIN, on ? HIGH : LOW);
  syncFirebase(mode);
}

/* ===== SETUP ===== */
void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(SAKLAR_PIN, INPUT_PULLUP);

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
  }

  configTime(7 * 3600, 0, "pool.ntp.org", "id.pool.ntp.org");

  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  time_t now = time(nullptr);
  while (now < 1000000) {
    delay(300);
    now = time(nullptr);
  }

  if (Firebase.getString(fbdo, "/settings/startTime"))
    startTime = fbdo.stringData();
  if (Firebase.getString(fbdo, "/settings/endTime"))
    endTime = fbdo.stringData();

  struct tm* t = localtime(&now);
  bool currSchedule = inSchedule(t->tm_hour, t->tm_min);
  lastScheduleState = currSchedule;

  lampuStatus = currSchedule;
  digitalWrite(RELAY_PIN, lampuStatus ? HIGH : LOW);
  syncFirebase("AUTO_BOOT");

  Firebase.setString(fbdo, "/command/value", "NONE");
}

/* ===== LOOP ===== */
void loop() {
  if (!Firebase.ready()) return;

  // Sync jadwal tiap 30 detik
  static unsigned long lastSync = 0;
  if (millis() - lastSync > 30000) {
    if (Firebase.getString(fbdo, "/settings/startTime"))
      startTime = fbdo.stringData();
    if (Firebase.getString(fbdo, "/settings/endTime"))
      endTime = fbdo.stringData();
    lastSync = millis();
  }

  // Manual switch fisik
  static bool lastBtn = HIGH;
  bool btn = digitalRead(SAKLAR_PIN);
  if (btn != lastBtn) {
    delay(50);
    if (digitalRead(SAKLAR_PIN) == btn && btn == LOW) {
      setLamp(!lampuStatus, "MANUAL_SWITCH");
    }
    lastBtn = btn;
  }

  // Command aplikasi (bulletproof)
  if (Firebase.getString(fbdo, "/command/value")) {
    String cmd = fbdo.stringData();
    if (cmd != "NONE") {
      if (cmd == "ON") setLamp(true, "MANUAL_APP");
      else if (cmd == "OFF") setLamp(false, "MANUAL_APP");
      Firebase.setString(fbdo, "/command/value", "NONE");
    }
  }

  // Auto schedule
  time_t now = time(nullptr);
  struct tm* t = localtime(&now);
  if (t && t->tm_year >= 120) {
    bool currSchedule = inSchedule(t->tm_hour, t->tm_min);
    if (currSchedule != lastScheduleState) {
      lastScheduleState = currSchedule;
      setLamp(currSchedule, "AUTO");
    }
  }

  delay(200);
}
