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

/* ===== PIN & STATE ===== */
#define RELAY_PIN 18
#define SAKLAR_PIN 21

bool lampuStatus = false;
bool lastScheduleState = false;
bool scheduleEnable = true;
String controlSource = "AUTO"; 
String startTime = "17:45"; // Akan diupdate dari Firebase
String endTime   = "03:30"; // Akan diupdate dari Firebase

/* ===== FUNGSI UTILITAS ===== */
String waktuLengkap() {
  time_t now = time(nullptr);
  struct tm* t = localtime(&now);
  if (!t || t->tm_year < 120) return "--";
  const char* hari[] = {"Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu"};
  char buf[64];
  sprintf(buf,"%s, %02d/%02d/%04d %02d:%02d WIB",
    hari[t->tm_wday],t->tm_mday,t->tm_mon+1,
    t->tm_year+1900,t->tm_hour,t->tm_min);
  return String(buf);
}

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
  log.set("mode", mode);
  Firebase.pushJSON(fbdo, "/logs", log);

  Firebase.setBool(fbdo, "/lampu/status", lampuStatus);
  Firebase.setString(fbdo, "/lampu/mode", mode);
  Firebase.setString(fbdo, "/lampu/time", waktuLengkap());

  FirebaseJson ev;
  ev.set("text", msg);
  ev.set("mode", mode);
  Firebase.setJSON(fbdo, "/lampu/last_event", ev);
}

void setLamp(bool on, String mode) {
  digitalWrite(RELAY_PIN, on ? HIGH : LOW);
  lampuStatus = on;
  controlSource = mode.startsWith("MANUAL") ? "MANUAL" : "AUTO";
  Firebase.setString(fbdo, "/lampu/control", controlSource);
  pushLog(on ? "Lampu MENYALA" : "Lampu MATI", mode);
}

/* ===== SETUP ===== */
void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(SAKLAR_PIN, INPUT_PULLUP);

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }

  configTime(7 * 3600, 0, "pool.ntp.org", "id.pool.ntp.org");

  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);

  time_t now = time(nullptr);
  int retry = 0;
  while (now < 1000000 && retry < 20) { delay(500); now = time(nullptr); retry++; }

  // Ambil jadwal terbaru saat pertama kali nyala
  if (Firebase.getString(fbdo, "/settings/startTime")) startTime = fbdo.stringData();
  if (Firebase.getString(fbdo, "/settings/endTime")) endTime = fbdo.stringData();

  String lastMode = "AUTO";
  if (Firebase.getString(fbdo, "/lampu/control")) lastMode = fbdo.stringData();
  if (Firebase.getBool(fbdo, "/lampu/status")) lampuStatus = fbdo.boolData();

  struct tm* t = localtime(&now);
  bool currSchedule = scheduleEnable && inSchedule(t->tm_hour, t->tm_min);

  if (lastMode == "MANUAL") {
    digitalWrite(RELAY_PIN, lampuStatus ? HIGH : LOW);
  } else {
    digitalWrite(RELAY_PIN, currSchedule ? HIGH : LOW);
    lampuStatus = currSchedule;
  }
  
  lastScheduleState = currSchedule;
  Firebase.setBool(fbdo, "/lampu/status", lampuStatus);
  Firebase.setBool(fbdo, "/lampu/last_schedule", lastScheduleState);
  Firebase.setString(fbdo, "/command/value", "NONE");
}

/* ===== LOOP ===== */
void loop() {
  if (!Firebase.ready()) return;

  // 1. UPDATE JADWAL DARI FIREBASE (Agar sinkron dengan aplikasi)
  static unsigned long lastCheck = 0;
  if (millis() - lastCheck > 10000) { // Cek setiap 10 detik
    if (Firebase.getString(fbdo, "/settings/startTime")) startTime = fbdo.stringData();
    if (Firebase.getString(fbdo, "/settings/endTime")) endTime = fbdo.stringData();
    lastCheck = millis();
  }

  // 2. SAKLAR FISIK
  static bool lastBtn = HIGH;
  bool btn = digitalRead(SAKLAR_PIN);
  if (btn != lastBtn) {
    delay(50);
    if (digitalRead(SAKLAR_PIN) == btn && btn == LOW) {
      setLamp(!lampuStatus, "MANUAL_SWITCH");
    }
    lastBtn = btn;
  }

  // 3. KONTROL APLIKASI
  if (Firebase.getString(fbdo, "/command/value")) {
    String cmd = fbdo.stringData();
    if (cmd == "ON") { setLamp(true, "MANUAL_APP"); Firebase.setString(fbdo, "/command/value", "NONE"); }
    else if (cmd == "OFF") { setLamp(false, "MANUAL_APP"); Firebase.setString(fbdo, "/command/value", "NONE"); }
  }

  // 4. LOGIKA JADWAL (AUTO)
  time_t now = time(nullptr);
  struct tm* t = localtime(&now);
  if (t && t->tm_year >= 120) {
    bool currSchedule = scheduleEnable && inSchedule(t->tm_hour, t->tm_min);
    
    if (currSchedule != lastScheduleState) {
      lastScheduleState = currSchedule;
      Firebase.setBool(fbdo, "/lampu/last_schedule", lastScheduleState);

      if (currSchedule) {
        if (!lampuStatus) setLamp(true, "AUTO");
      } else {
        setLamp(false, "AUTO"); 
      }
    }
  }

  delay(200);
}
