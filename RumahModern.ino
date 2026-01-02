#include <WiFi.h>
#include <FirebaseESP32.h>
#include <time.h>

/* ===== WIFI ===== */
const char* ssid = "";
const char* password = "";

/* ===== FIREBASE ===== */
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
bool scheduleEnable = true;
String startTime = "17:45";
String endTime   = "03:30";

/* ===== TIME ===== */
String waktuLengkap() {
  time_t now = time(nullptr);
  struct tm* t = localtime(&now);
  if (!t || t->tm_year < 120) return "--";
  const char* hari[] = {"Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu"};
  char buf[64];
  sprintf(buf,"%s, %02d/%02d/%04d %02d:%02d WIB",
    hari[t->tm_wday],t->tm_mday,t->tm_mon+1,t->tm_year+1900,t->tm_hour,t->tm_min);
  return String(buf);
}

/* ===== UTIL ===== */
bool inSchedule(int h, int m) {
  int now = h * 60 + m;
  int s = startTime.substring(0,2).toInt() * 60 + startTime.substring(3,5).toInt();
  int e = endTime.substring(0,2).toInt() * 60 + endTime.substring(3,5).toInt();
  if (s <= e) return now >= s && now < e;
  return now >= s || now < e;
}

void pushLog(String msg, String mode) {
  FirebaseJson log;
  log.set("event", msg);
  log.set("time", waktuLengkap());
  Firebase.pushJSON(fbdo, "/logs", log);

  Firebase.setBool(fbdo, "/lampu/status", lampuStatus);
  Firebase.setString(fbdo, "/lampu/mode", mode);
  Firebase.setString(fbdo, "/lampu/time", waktuLengkap());
  Firebase.setString(fbdo, "/lampu/last_event", msg);
}

/* ===== RELAY ===== */
void setLamp(bool on, String mode) {
  digitalWrite(RELAY_PIN, on ? HIGH : LOW);
  lampuStatus = on;
  pushLog(on ? "Lampu MENYALA" : "Lampu MATI", mode);
}

/* ===== SETUP ===== */
void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(SAKLAR_PIN, INPUT_PULLUP);

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) delay(500);

  configTime(7 * 3600, 0, "pool.ntp.org");

  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);

  Firebase.setString(fbdo, "/command/value", "NONE");
}

/* ===== LOOP ===== */
void loop() {

  if (!Firebase.ready()) return;

  /* === SAKLAR FISIK (PRIORITAS TERTINGGI) === */
  static bool lastBtn = HIGH;
  bool btn = digitalRead(SAKLAR_PIN);
  if (btn != lastBtn) {
    delay(50);
    if (digitalRead(SAKLAR_PIN) == btn && btn == LOW) {
      setLamp(!lampuStatus, "MANUAL");
    }
    lastBtn = btn;
  }

  /* === REMOTE APP === */
  if (Firebase.getString(fbdo, "/command/value")) {
    String cmd = fbdo.stringData();
    if (cmd == "ON") setLamp(true, "MANUAL");
    if (cmd == "OFF") setLamp(false, "MANUAL");
    if (cmd != "NONE") Firebase.setString(fbdo, "/command/value", "NONE");
  }

  /* === UPDATE JADWAL === */
  static unsigned long lastFetch = 0;
  if (millis() - lastFetch > 60000) {
    if (Firebase.getBool(fbdo, "/schedule/enable"))
      scheduleEnable = fbdo.boolData();
    if (Firebase.getString(fbdo, "/schedule/start"))
      startTime = fbdo.stringData();
    if (Firebase.getString(fbdo, "/schedule/end"))
      endTime = fbdo.stringData();
    lastFetch = millis();
  }

  /* === JADWAL EVENT BASED === */
  time_t now = time(nullptr);
  struct tm* t = localtime(&now);
  if (!t || t->tm_year < 120) return;

  bool currSchedule = scheduleEnable && inSchedule(t->tm_hour, t->tm_min);

  if (currSchedule != lastScheduleState) {
    setLamp(currSchedule, "AUTO");
    lastScheduleState = currSchedule;
  }

  delay(200);
}
