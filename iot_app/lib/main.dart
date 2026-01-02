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

  // Inisialisasi Notifikasi Lokal
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotif.initialize(const InitializationSettings(android: androidInit));

  await FirebaseMessaging.instance.requestPermission();
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
        fontFamily: 'sans-serif',
        colorSchemeSeed: Colors.blue,
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
  bool lampuStatus = false;
  String mode = "-", time = "-";
  bool enable = true;
  TimeOfDay start = const TimeOfDay(hour: 17, minute: 45); // Default sesuai instruksi
  TimeOfDay end = const TimeOfDay(hour: 3, minute: 30);   // Default sesuai instruksi
  List<String> logs = [];

  String f(TimeOfDay t) => "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  void showNotification(String title, String body) async {
    const androidDetail = AndroidNotificationDetails(
      'iot_lamp', 'Lampu Notif', 
      importance: Importance.max, 
      priority: Priority.high
    );
    await localNotif.show(
      DateTime.now().millisecond, title, body, 
      const NotificationDetails(android: androidDetail)
    );
  }

  // FITUR: Hapus Semua Riwayat
  void clearLogs() async {
    await db.child("logs").remove();
    setState(() => logs = []);
  }

  @override
  void initState() {
    super.initState();

    // 1. Listen Notifikasi
    db.child("lampu/last_event").onValue.listen((e) {
      final msg = e.snapshot.value as String?;
      if (msg != null && msg.isNotEmpty) showNotification("Rumah Ceria", msg);
    });

    // 2. Listen Status Lampu & Waktu Terakhir (Sync dengan Saklar & Auto-Recovery)
    db.child("lampu").onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d == null) return;
      setState(() {
        lampuStatus = d["status"] ?? false;
        mode = d["mode"] ?? "-";
        time = d["time"] ?? "--:--"; // Mencegah null saat startup
      });
    });

    // 3. Listen Jadwal
    db.child("schedule").onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d == null) return;
      setState(() {
        enable = d["enable"] ?? true;
        final sStr = d["start"] ?? "17:45";
        final eStr = d["end"] ?? "03:30";
        start = TimeOfDay(hour: int.parse(sStr.split(":")[0]), minute: int.parse(sStr.split(":")[1]));
        end = TimeOfDay(hour: int.parse(eStr.split(":")[0]), minute: int.parse(eStr.split(":")[1]));
      });
    });

    // 4. Listen Riwayat Log (Format Lengkap & Anti-Null)
    db.child("logs").limitToLast(10).onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d == null) {
        setState(() => logs = []);
        return;
      }
      final list = d.values.map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        String tValue = m["time"] ?? "--:--"; 
        String eValue = m["event"] ?? "Aktivitas";
        return "$tValue $eValue"; 
      }).toList().reversed.toList();
      setState(() => logs = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("SMART CONTROL", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CARD UTAMA
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: lampuStatus ? Colors.amber.shade400 : Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: lampuStatus ? Colors.amber.withOpacity(0.4) : Colors.black.withOpacity(0.05),
                      blurRadius: 30, offset: const Offset(0, 15),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Icon(Icons.lightbulb_circle, size: 100, color: lampuStatus ? Colors.white : Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(lampuStatus ? "ON" : "OFF", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: lampuStatus ? Colors.white : Colors.black87)),
                    Text("Last: $time", style: TextStyle(color: lampuStatus ? Colors.white70 : Colors.black38), textAlign: TextAlign.center),
                    Text("Mode: $mode", style: TextStyle(color: lampuStatus ? Colors.white70 : Colors.black38, fontSize: 12), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            // TOMBOL MANUAL
            Row(
              children: [
                _btn("ON", Icons.power, Colors.green, () => db.child("command/value").set("ON")),
                const SizedBox(width: 16),
                _btn("OFF", Icons.power_off, Colors.redAccent, () => db.child("command/value").set("OFF")),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // PANEL JADWAL
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
              child: Column(
                children: [
                  SwitchListTile(title: const Text("Auto Schedule", style: TextStyle(fontWeight: FontWeight.bold)), value: enable, onChanged: (v) => db.child("schedule/enable").set(v)),
                  const Divider(indent: 20, endIndent: 20),
                  _timeTile("Start Time", f(start), Icons.wb_sunny_rounded, Colors.orange, () async {
                    final t = await showTimePicker(context: context, initialTime: start);
                    if (t != null) db.child("schedule/start").set(f(t));
                  }),
                  _timeTile("End Time", f(end), Icons.nightlight_round, Colors.indigo, () async {
                    final t = await showTimePicker(context: context, initialTime: end);
                    if (t != null) db.child("schedule/end").set(f(t));
                  }),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // RIWAYAT AKTIVITAS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Activity History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
                IconButton(
                  onPressed: () {
                    // Konfirmasi sebelum hapus
                    showDialog(context: context, builder: (c) => AlertDialog(
                      title: const Text("Hapus Log?"),
                      content: const Text("Seluruh riwayat akan dihapus permanen."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")),
                        TextButton(onPressed: () { clearLogs(); Navigator.pop(c); }, child: const Text("Hapus", style: TextStyle(color: Colors.red))),
                      ],
                    ));
                  }, 
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent)
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (logs.isEmpty) const Center(child: Text("No recent activity", style: TextStyle(color: Colors.grey))),
            
            ...logs.map((log) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withOpacity(0.03))),
              child: Row(
                children: [
                  Icon(Icons.history, size: 20, color: Colors.blue.shade300),
                  const SizedBox(width: 12),
                  Expanded(child: Text(log, style: const TextStyle(fontSize: 13, color: Colors.black54))),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _btn(String t, IconData i, Color c, VoidCallback o) => Expanded(
    child: InkWell(
      onTap: o, borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withOpacity(0.2))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 20), const SizedBox(width: 8), Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold))]),
      ),
    ),
  );

  Widget _timeTile(String t, String v, IconData i, Color c, VoidCallback o) => ListTile(
    leading: Icon(i, color: c),
    title: Text(t, style: const TextStyle(fontSize: 15)),
    trailing: Text(v, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 15)),
    onTap: o,
  );
}