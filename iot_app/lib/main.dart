import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin localNotif = FlutterLocalNotificationsPlugin();

Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotif.initialize(const InitializationSettings(android: androidInit));

  FirebaseMessaging.onBackgroundMessage(_bgHandler);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, 
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark, 
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference db = FirebaseDatabase.instance.ref();
  bool status = false;
  String mode = "-", time = "-";
  String startStr = "18:00"; // Default jika data belum ada
  String endStr = "06:00";   // Default jika data belum ada
  List<String> logs = [];

  @override
  void initState() {
    super.initState();

    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) db.child("fcm_tokens/$token").set(true);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      if (notification != null) {
        localNotif.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'smart_lamp_channel', 'Smart Lamp Notifications',
              importance: Importance.max, priority: Priority.high,
            ),
          ),
        );
      }
    });

    // Ambil Status Lampu
    db.child("lampu").onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d != null) {
        setState(() {
          status = d["status"] ?? false;
          mode = d["mode"] ?? "-";
          time = d["time"] ?? "-";
        });
      }
    });

    // AMBIL JADWAL DARI FIREBASE (Agar Sinkron dengan ESP32)
    db.child("settings").onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d != null) {
        setState(() {
          startStr = d["startTime"] ?? "18:00";
          endStr = d["endTime"] ?? "06:00";
        });
      }
    });

    db.child("logs").limitToLast(10).onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d == null) return;
      final list = d.values.map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        return "${m["time"] ?? "--"} - ${m["event"] ?? "Aktivitas"} (${m["mode"] ?? "-"})";
      }).toList().reversed.toList();
      setState(() => logs = list);
    });
  }

  // FUNGSI UNTUK MERUBAH JAM
  Future<void> _pickTime(String key) async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      // Format jam agar menjadi HH:mm (Misal 07:05)
      String formattedTime = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
      db.child("settings/$key").set(formattedTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/bg.jpeg", 
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.blueGrey), 
            ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.6))),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    "SMART LAMP CONTROL",
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 3),
                  ),
                  const SizedBox(height: 30),
                  
                  // CARD STATUS
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.lightbulb_rounded, size: 80, color: status ? Colors.amber : Colors.white10),
                        Text(
                          status ? "MENYALA" : "MATI",
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: status ? Colors.amber : Colors.white70),
                        ),
                        Text("Mode: $mode", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const Divider(height: 30, color: Colors.white10),
                        
                        // FITUR SETTING JADWAL
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _timeDisplay("MULAI", startStr, () => _pickTime("startTime")),
                            const Icon(Icons.arrow_forward_rounded, color: Colors.white24),
                            _timeDisplay("SELESAI", endStr, () => _pickTime("endTime")),
                          ],
                        )
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      _actionBtn("NYALAKAN", Colors.green.shade600, () => db.child("command/value").set("ON")),
                      const SizedBox(width: 20),
                      _actionBtn("MATIKAN", Colors.redAccent.shade400, () => db.child("command/value").set("OFF")),
                    ],
                  ),
                  
                  const SizedBox(height: 30),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Riwayat Aktivitas", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  ...logs.map((log) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(log, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget Tampilan Jam Jadwal
  Widget _timeDisplay(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const Text("Klik untuk ubah", style: TextStyle(color: Colors.blue, fontSize: 8)),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onPress) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        onPressed: onPress,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
