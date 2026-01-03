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
        brightness: Brightness.dark,
        fontFamily: 'sans-serif',
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
  final ScrollController _logScrollController = ScrollController();

  bool status = false;
  String mode = "-";
  String time = "Syncing...";
  String startStr = "17:45";
  String endStr = "03:30";
  List<Map<dynamic, dynamic>> logs = [];

  @override
  void initState() {
    super.initState();
    _setupFirebase();
  }

  void _setupFirebase() {
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
          startStr = d["startTime"] ?? "17:45";
          endStr = d["endTime"] ?? "03:30";
        });
      }
    });

    db.child("logs").limitToLast(20).onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d != null) {
        final sortedLogs = d.values.map((v) => Map<dynamic, dynamic>.from(v as Map)).toList();
        sortedLogs.sort((a, b) => (b["time"] ?? "").compareTo(a["time"] ?? ""));
        setState(() => logs = sortedLogs);
      }
    });
  }

  Future<void> _pickTime(String key) async {
    TimeOfDay? picked = await showTimePicker(
      context: context, 
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (picked != null) {
      String formattedTime = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
      db.child("settings/$key").set(formattedTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset("assets/bg.jpeg", fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF1A1A2E))),
          ),
          Positioned.fill(child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.8)],
              ),
            ),
          )),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildAppBar(),
                  const Spacer(),
                  _buildMainCard(),
                  const SizedBox(height: 24),
                  _buildActionButtons(),
                  const SizedBox(height: 32),
                  _buildLogHeader(),
                  const SizedBox(height: 12),
                  _buildLogList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Column(
      children: [
        const Text("SMART HOME APP", style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 4)),
        const Text("Light Control", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
          child: Text(time, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        )
      ],
    );
  }

  Widget _buildMainCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: status ? [BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 40, spreadRadius: 5)] : [],
            ),
            child: Icon(Icons.lightbulb_rounded, size: 70, color: status ? Colors.amber : Colors.white10),
          ),
          const SizedBox(height: 16),
          Text(status ? "SYSTEM ACTIVE" : "SYSTEM INACTIVE", 
            style: TextStyle(fontSize: 14, letterSpacing: 2, color: status ? Colors.amber : Colors.white24, fontWeight: FontWeight.bold)),
          Text(status ? "Light is On" : "Light is Off", 
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 4),
          Text("Mode: $mode", style: const TextStyle(color: Colors.white38, fontSize: 12)),
          
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(color: Colors.white10)),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTimeToggle("START", startStr, "startTime"),
              const Padding(
                padding: EdgeInsets.only(bottom: 45),
                child: Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 15),
              ),
              _buildTimeToggle("END", endStr, "endTime"),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTimeToggle(String title, String val, String key) {
    return Column(
      children: [
        Text(title, 
          style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(val, 
          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 32,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.amber,
              side: const BorderSide(color: Colors.amber, width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => _pickTime(key),
            child: const Text("Change Schedule", 
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        _singleBtn("OFF", Colors.black45, () => db.child("command/value").set("OFF"), !status),
        const SizedBox(width: 16),
        _singleBtn("ON", Colors.amber, () => db.child("command/value").set("ON"), status),
      ],
    );
  }

  Widget _singleBtn(String label, Color color, VoidCallback action, bool isActive) {
    return Expanded(
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isActive ? Colors.white24 : Colors.transparent),
          ),
          child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.white24))),
        ),
      ),
    );
  }

  Widget _buildLogHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Last Activity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        TextButton(
          onPressed: () => db.child("logs").remove(),
          child: const Text("Clear Activity History", style: TextStyle(color: Colors.redAccent, fontSize: 13)),
        )
      ],
    );
  }

  Widget _buildLogList() {
    if (logs.isEmpty) return const Expanded(child: Center(child: Text("History Not Found", style: TextStyle(color: Colors.white10))));
    
    return Expanded(
      child: ListView.builder(
        controller: _logScrollController,
        padding: const EdgeInsets.only(bottom: 30),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[index];
          final isAuto = log["mode"]?.toString().contains("AUTO") ?? false;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: isAuto ? Colors.blueAccent : Colors.orangeAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log["event"] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(log["time"] ?? "-", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                  child: Text(log["mode"] ?? "-", style: const TextStyle(fontSize: 9, color: Colors.white54)),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
