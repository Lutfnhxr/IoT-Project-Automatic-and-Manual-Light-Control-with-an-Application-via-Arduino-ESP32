import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
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

  // Perbaikan SystemUiMode untuk Full Screen
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

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
  
  // SOLUSI UTAMA: ScrollController untuk memaksa Scrollbar muncul
  final ScrollController _logScrollController = ScrollController();
  
  bool status = false;
  String mode = "-", time = "-";
  String startStr = "17:45";
  String endStr = "03:30";
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
          notification.hashCode, notification.title, notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'smart_lamp_channel', 'Smart Lamp Notifications',
              importance: Importance.max, priority: Priority.high,
            ),
          ),
        );
      }
    });

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

    db.child("settings").onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d != null) {
        setState(() {
          startStr = d["startTime"] ?? "18:00";
          endStr = d["endTime"] ?? "06:00";
        });
      }
    });

    db.child("logs").limitToLast(30).onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d == null) {
        setState(() => logs = []);
        return;
      }
      final list = d.values.map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        return "${m["time"] ?? "--"} - ${m["event"] ?? "Aktivitas"} (${m["mode"] ?? "-"})";
      }).toList().reversed.toList();
      setState(() => logs = list);
    });
  }

  Future<void> _pickTime(String key) async {
    TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      String formattedTime = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
      db.child("settings/$key").set(formattedTime);
    }
  }

  Future<void> _clearLogs() async {
    await db.child("logs").remove();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Riwayat telah dibersihkan")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/bg.jpeg", fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.blueGrey),
            ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.55))),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(
                children: [
                  const Text("SMART LAMP CONTROL", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  
                  const Spacer(flex: 1),

                  // CARD STATUS
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.lightbulb_rounded, size: 80, color: status ? Colors.amber : Colors.white10),
                        Text(status ? "Light up" : "Light Off", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: status ? Colors.amber : Colors.white70)),
                        Text("Last Mode: $mode", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const Divider(height: 35, color: Colors.white10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _timeDisplay("Start", startStr, () => _pickTime("startTime")),
                            const Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.arrow_forward_rounded, color: Colors.white24, size: 20)),
                            _timeDisplay("End", endStr, () => _pickTime("endTime")),
                          ],
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  Row(
                    children: [
                      _actionBtn("Turn On", Colors.green.shade600, () => db.child("command/value").set("ON")),
                      const SizedBox(width: 15),
                      _actionBtn("Turn Off", Colors.redAccent.shade400, () => db.child("command/value").set("OFF")),
                    ],
                  ),

                  const SizedBox(height: 25),

                  // HEADER RIWAYAT
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Activity History", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      GestureDetector(
                        onTap: _clearLogs,
                        child: const Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                            Text(" Clear History", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // AREA SCROLL LOG (FIXED SCROLLBAR)
                  Expanded(
                    flex: 3, 
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        scrollbarTheme: ScrollbarThemeData(
                          thumbColor: WidgetStateProperty.all(Colors.white.withOpacity(0.3)),
                          thickness: WidgetStateProperty.all(6.0),
                          radius: const Radius.circular(10),
                        ),
                      ),
                      child: Scrollbar(
                        controller: _logScrollController,
                        thumbVisibility: true,
                        child: logs.isEmpty
                            ? SingleChildScrollView(
                                controller: _logScrollController,
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Container(
                                  height: 200,
                                  alignment: Alignment.center,
                                  child: const Text("History Not Found", style: TextStyle(color: Colors.white24)),
                                ),
                              )
                            : ListView.builder(
                                controller: _logScrollController,
                                padding: const EdgeInsets.only(top: 5, bottom: 20, right: 15),
                                physics: const AlwaysScrollableScrollPhysics(), 
                                itemCount: logs.length,
                                itemBuilder: (context, index) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Text(logs[index], style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeDisplay(String label, String value, VoidCallback onTap) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SizedBox(
          height: 32,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blueAccent,
              side: const BorderSide(color: Colors.blueAccent, width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: onTap,
            child: const Text("Change Schedule", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onPress) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white,
          elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: onPress,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }
}
