import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin localNotif = FlutterLocalNotificationsPlugin();

// Handler untuk notifikasi saat aplikasi di background
Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Inisialisasi Notifikasi Lokal
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
  List<String> logs = [];

  @override
  void initState() {
    super.initState();

    // 1. Ambil & Simpan Token FCM
    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) {
        db.child("fcm_tokens/$token").set(true);
      }
    });

    // 2. Listen Notifikasi (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      if (notification != null) {
        localNotif.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'smart_lamp_channel',
              'Smart Lamp Notifications',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
    });

    // 3. Listen Status Lampu Real-time
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

    // 4. Listen Riwayat Logs
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. BACKGROUND MENGGUNAKAN ASSET LOKAL (Fix statusCode: 0)
          Positioned.fill(
            child: Image.asset(
              "assets/bg.jpeg", 
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.blueGrey), 
            ),
          ),
          
          // 2. OVERLAY GELAP (Agar teks putih tetap kontras)
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.6)),
          ),

          // 3. KONTEN UTAMA
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    "SMART LAMP CONTROL",
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 3),
                  ),
                  const SizedBox(height: 40),
                  
                  // CARD STATUS (Glassmorphism Style)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.lightbulb_rounded, 
                          size: 100, 
                          color: status ? Colors.amber : Colors.white10
                        ),
                        const SizedBox(height: 15),
                        Text(
                          status ? "MENYALA" : "MATI",
                          style: TextStyle(
                            fontSize: 32, 
                            fontWeight: FontWeight.bold, 
                            color: status ? Colors.amber : Colors.white70
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text("Mode: $mode", style: const TextStyle(color: Colors.white70, fontSize: 16)),
                        Text(time, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // TOMBOL KONTROL
                  Row(
                    children: [
                      _actionBtn("NYALAKAN", Colors.green.shade600, () => db.child("command/value").set("ON")),
                      const SizedBox(width: 20),
                      _actionBtn("MATIKAN", Colors.redAccent.shade400, () => db.child("command/value").set("OFF")),
                    ],
                  ),
                  
                  const SizedBox(height: 40),

                  // SEKSI RIWAYAT
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Riwayat Aktivitas", 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...logs.map((log) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Text(
                      log, 
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)
                    ),
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onPress) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        onPressed: onPress,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
